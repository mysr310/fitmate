import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 训练历史
class PlanHistoryPage extends ConsumerWidget {
  const PlanHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(workoutLogsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('训练历史')),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Text(
                '还没有训练记录\n从训练页点「开始训练」完成第一次打卡吧',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24, top: 4),
            itemCount: logs.length,
            itemBuilder: (context, i) => _HistoryTile(log: logs[i]),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final WorkoutLog log;

  const _HistoryTile({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final exAsync = ref.watch(exercisesOfLogProvider(log.id));
    final exercises = exAsync.value ?? const <ExerciseLog>[];
    final duration = log.completedAt == null
        ? null
        : Duration(seconds: log.completedAt! - log.startedAt);
    final doneCount = exercises.where((e) => e.done).length;

    return Dismissible(
      key: ValueKey('log_${log.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      // R3-低12：删除失败返回 false，条目留在列表
      confirmDismiss: (_) async {
        try {
          await ref.read(databaseProvider).deleteWorkoutLog(log.id);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
          }
          return false;
        }
      },
      child: Card(
        child: ExpansionTile(
          shape: const Border(),
          title: Text(
            '${log.dayTitle.isEmpty ? '训练' : log.dayTitle} · ${log.date}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            [
              if (duration != null) '时长 ${duration.inMinutes}分钟',
              if (log.feeling.isNotEmpty) '感受：${log.feeling}',
              '完成 $doneCount 个动作',
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            if (exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('（无动作明细）', style: TextStyle(fontSize: 12)),
              )
            else
              for (final e in exercises)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e.done ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: e.done ? scheme.primary : scheme.outline,
                  ),
                  title: Text(e.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '完成 ${e.doneSets}组 × ${e.doneReps}'
                    '${e.doneWeightKg != null ? ' · ${fmtWeight(e.doneWeightKg!)}kg' : ''}'
                    '（计划 ${e.plannedSets}组×${e.plannedReps}）',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
