import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'backup_page.dart' show briefError;

/// 备份恢复完整流程（解析 → 选择覆盖/合并 → 恢复 → 结果提示）。
/// 「导入备份」「备份历史」「微信用其他应用打开」三条入口共用，
/// 调用方负责互斥（备份页用 _restoring，intent 用 handler 内标志）。
Future<void> runBackupRestoreFlow(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final svc = ref.read(backupServiceProvider);
  try {
    final bytes = await File(path).readAsBytes();
    if (!context.mounted) return;
    final parsed = await svc.parseBackup(bytes);
    if (!context.mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text(
            '该备份创建于 ${DateTime.fromMillisecondsSinceEpoch((parsed.payload['created_at'] as int? ?? 0) * 1000)}\n\n'
            '· 覆盖恢复：清空本机数据，完全变成备份里的样子\n'
            '· 合并恢复：保留本机数据，把备份里的记录并入（计划将导入为未启用）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('合并恢复')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'), child: const Text('覆盖恢复')),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    final summary = await svc.restore(
      payload: parsed.payload,
      photos: parsed.photos,
      overwrite: mode == 'overwrite',
    );
    if (context.mounted) {
      // N2：覆盖恢复会替换档案/配置，已打开的编辑页（重建/档案/AI 接口）
      // 表单里还是旧值——关闭所有已 push 的页面，回到主界面再提示
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复完成：$summary'), duration: const Duration(seconds: 4)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('恢复失败：${briefError(e)}'),
        duration: const Duration(seconds: 4),
      ));
    }
  }
}
