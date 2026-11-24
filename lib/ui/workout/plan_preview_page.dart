import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/parsers.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// AI 计划预览 → 确认保存
class PlanPreviewPage extends ConsumerStatefulWidget {
  final WeeklyPlanAi plan;

  const PlanPreviewPage({required this.plan, super.key});

  @override
  ConsumerState<PlanPreviewPage> createState() => _PlanPreviewPageState();
}

class _PlanPreviewPageState extends ConsumerState<PlanPreviewPage> {
  bool _saving = false;

  Future<void> _save({required bool makeActive}) async {
    if (_saving) return; // R3-低11
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final id = await db.insertFullPlan(
        name: widget.plan.planName,
        source: 'ai',
        note: widget.plan.summary,
        makeActive: makeActive,
        days: [
          for (final d in widget.plan.days)
            PlanDaySpec(
              weekday: d.weekday,
              isRest: d.isRest,
              title: d.title,
              note: d.note,
              exercises: [
                for (final ex in d.exercises)
                  PlanExerciseSpec(
                    name: ex.name,
                    sets: ex.sets,
                    reps: ex.reps,
                    weightKg: ex.weightKg,
                    restSeconds: ex.restSeconds,
                    note: ex.note,
                    orderIdx: ex.orderIdx,
                  ),
              ],
            ),
        ],
      );
      if (makeActive) {
        await db.setActivePlan(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(makeActive ? '计划已保存并启用' : '计划已保存（未启用）'),
        ));
        // 回到训练页并关闭预览
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trainingDays = widget.plan.days.where((d) => !d.isRest).length;

    return Scaffold(
      appBar: AppBar(title: const Text('计划预览')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.plan.planName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('共 $trainingDays 个训练日 · ${widget.plan.days.length - trainingDays} 个休息日',
                            style: TextStyle(fontSize: 12, color: scheme.outline)),
                        if (widget.plan.summary.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(widget.plan.summary,
                              style: const TextStyle(fontSize: 13, height: 1.5)),
                        ],
                      ],
                    ),
                  ),
                ),
                for (final d in widget.plan.days)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(_weekdayLabel(d.weekday),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: d.isRest ? scheme.outline : scheme.primary)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  d.isRest ? '休息日' : d.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (!d.isRest)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                children: [
                                  for (final ex in d.exercises)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('•  ${ex.name}',
                                              style: const TextStyle(fontSize: 13)),
                                          const Spacer(),
                                          Text(
                                            '${ex.sets}组×${ex.reps}'
                                            '${ex.weightKg != null ? ' · ${ex.weightKg!.toStringAsFixed(ex.weightKg! % 1 == 0 ? 0 : 1)}kg' : ''}',
                                            style: TextStyle(
                                                fontSize: 12, color: scheme.outline),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                          ),
                          if (d.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(d.note,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.outline,
                                      fontStyle: FontStyle.italic)),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(makeActive: false),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存不启用'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(makeActive: true),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('保存并设为当前'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _weekdayLabel(int wd) => const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][wd - 1];
}
