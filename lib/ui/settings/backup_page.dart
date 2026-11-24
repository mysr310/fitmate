import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../../services/lan_server.dart';

/// 提取简短错误信息（不带堆栈）
String briefError(Object e) {
  final s = e.toString();
  final firstLine = s.split('\n').first.trim();
  return firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine;
}

/// 备份与电脑联动页
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final LanTransferServer _lan = LanTransferServer();
  String? _lanPort;
  List<String> _ips = const [];
  bool _busy = false; // 备份写入中
  bool _restoring = false; // A9：恢复流程互斥
  bool _lanStarting = false; // A7：局域网服务启动互斥

  @override
  void dispose() {
    _lan.stop();
    _lan.uploadedFile.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _lan.uploadedFile.addListener(_onLanUpload);
  }

  Future<void> _onLanUpload() async {
    final path = _lan.uploadedFile.value;
    if (path == null || !mounted || _restoring) return;
    await _restoreFromFile(path);
    if (mounted) {
      setState(() {
        _lan.uploadedFile.value = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final backupsAsync = ref.watch(backupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('备份与电脑联动')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Header('备份到电脑'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '把全部数据打包成 .fitbak 文件，经微信「文件传输助手」发送到电脑保存。'
              '换手机或手机故障时，可从备份完整恢复（AI Key 不包含在内，恢复后重新粘贴即可）。',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('（当前是网页预览，备份功能请使用手机 App）',
                  style: TextStyle(fontSize: 12)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _createBackup,
                    icon: _busy
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.backup),
                    label: const Text('立即备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _restoring ? null : _shareLatest,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('分享最新备份（微信）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _restoring ? null : _importBackup,
                    label: const Text('导入备份恢复'),
                  ),
                ],
              ),
            ),
          ],
          const _Header('局域网直传（同一 Wi-Fi，备用）'),
          if (_lanPort == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                onPressed: _lanStarting ? null : _startLan,
                icon: _lanStarting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi),
                label: Text(_lanStarting ? '启动中…' : '开启电脑传输服务'),
              ),
            )
          else ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('电脑浏览器输入以下任一地址',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final ip in _ips)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        // A8：完整网址已带访问令牌
                        'http://$ip:$_lanPort?k=${_lan.token}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_ips.isNotEmpty)
                    QrImageView(
                      data: 'http://${_ips.first}:$_lanPort?k=${_lan.token}',
                      size: 140,
                      backgroundColor: Colors.white,
                    ),
                  const Text(
                    '（二维码用另一台手机扫；电脑直接输网址）\n网页里可以下载备份到电脑、上传备份到手机',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _stopLan,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('关闭传输服务'),
                  ),
                ],
              ),
            ),
          ],
          const _Header('备份历史'),
          backupsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('加载失败：$e'),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无备份记录', style: TextStyle(fontSize: 13)),
                );
              }
              return Column(
                children: [
                  for (final b in list)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        b.kind == 'auto' ? Icons.schedule : Icons.backup_outlined,
                        size: 20,
                      ),
                      title: Text(
                        b.path.split(Platform.pathSeparator).last.split('/').last,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${(b.sizeBytes / 1024).toStringAsFixed(0)} KB · '
                        '${b.kind == 'auto' ? '自动' : '手动'}'
                        ' · ${DateTime.fromMillisecondsSinceEpoch(b.createdAt * 1000)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '分享',
                            icon: const Icon(Icons.send_outlined, size: 20),
                            onPressed: () => _shareFile(b.path),
                          ),
                          IconButton(
                            tooltip: '从此备份恢复',
                            icon: const Icon(Icons.restore, size: 20),
                            onPressed: () => _restoreFromFile(b.path),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final f = await ref.read(backupServiceProvider).createBackup(auto: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('备份完成：${f.path.split(Platform.pathSeparator).last.split('/').last}\n点「分享最新备份」发到电脑微信'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败：${briefError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLatest() async {
    try {
      final f = await ref.read(backupServiceProvider).latestBackup();
      if (f == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('还没有备份，先点「立即备份」')));
        }
        return;
      }
      await _shareFile(f.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：${briefError(e)}')));
      }
    }
  }

  Future<void> _shareFile(String path) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text: '健身管家备份文件',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：${briefError(e)}')));
      }
    }
  }

  Future<void> _importBackup() async {
    if (_restoring || _busy) return; // A9：恢复与备份互斥
    try {
      final picked = await FilePicker.pickFile();
      final path = picked?.path;
      if (path == null || !mounted) return;
      await _restoreFromFile(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：${briefError(e)}')));
      }
    }
  }

  Future<void> _restoreFromFile(String path) async {
    if (_restoring) return; // A9：多条恢复入口（导入/历史/局域网）互斥
    _restoring = true;
    try {
      final svc = ref.read(backupServiceProvider);
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      final parsed = await svc.parseBackup(bytes);
      if (!mounted) return;
      final mode = await _askRestoreMode(parsed.payload);
      if (mode == null) return;
      final summary = await svc.restore(
            payload: parsed.payload,
            photos: parsed.photos,
            overwrite: mode == 'overwrite',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复完成：$summary'), duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('恢复失败：${briefError(e)}'),
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      _restoring = false;
    }
  }

  Future<String?> _askRestoreMode(Map<String, dynamic> payload) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text(
            '该备份创建于 ${DateTime.fromMillisecondsSinceEpoch((payload['created_at'] as int? ?? 0) * 1000)}\n\n'
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
  }

  Future<void> _startLan() async {
    if (_lanStarting || _lanPort != null) return; // A7：启动互斥，防连点泄漏服务
    _lanStarting = true;
    try {
      final dir = await ref.read(backupServiceProvider).backupDir;
      // 先取 IP 再起服务：IP 获取失败时服务不会被遗留运行
      final ips = await LanTransferServer.localIps();
      if (!mounted) return;
      if (ips.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到可用的局域网 IPv4 地址，请检查 Wi-Fi')));
        return;
      }
      final port = await _lan.start(backupDirPath: dir.path);
      if (!mounted) {
        // A7：页面已销毁时立即关闭服务，避免后台常驻
        await _lan.stop();
        return;
      }
      setState(() {
        _lanPort = port;
        _ips = ips;
      });
    } catch (e) {
      await _lan.stop(); // 任何失败都确保服务关闭，下次点击可重新启动
      if (mounted) {
        setState(() {
          _lanPort = null;
          _ips = const [];
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('启动失败：${briefError(e)}')));
      }
    } finally {
      _lanStarting = false;
    }
  }

  Future<void> _stopLan() async {
    await _lan.stop();
    if (mounted) {
      setState(() => _lanPort = null);
    }
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
