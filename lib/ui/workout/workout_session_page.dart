import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 训练打卡执行页
class WorkoutSessionPage extends ConsumerStatefulWidget {
  final int planId;
  final int dayId;
  final String dayTitle;

  const WorkoutSessionPage({
    required this.planId,
    required this.dayId,
    required this.dayTitle,
    super.key,
  });

  @override
  ConsumerState<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _SetState {
  bool done = false;
  String reps;
  double? weight;
  _SetState({required this.reps, this.weight});
}

class _ExerciseState {
  final PlanExercise plan;
  List<_SetState> sets;
  bool done;

  _ExerciseState(this.plan)
      : sets = List.generate(
          plan.sets,
          (_) => _SetState(reps: plan.reps, weight: plan.weightKg),
        ),
        done = false;

  int get doneCount => sets.where((s) => s.done).length;
  double get totalWeight =>
      sets.where((s) => s.done).fold<double>(0, (sum, s) => sum + (s.weight ?? 0));
}

class _WorkoutSessionPageState extends ConsumerState<WorkoutSessionPage> {
  List<_ExerciseState>? _items;
  Timer? _timer;
  DateTime? _startedAt;
  String _feeling = '刚好';
  bool _saving = false; // B9：防止「结束训练」重复提交

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final plan = await ref.read(databaseProvider).getExercisesOfDay(widget.dayId);
    if (!mounted) return; // 加载期间页面可能已被关闭
    setState(() => _items = plan.map(_ExerciseState.new).toList());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    if (_startedAt == null) return '00:00';
    final d = DateTime.now().difference(_startedAt!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  int get _totalExercises => _items?.length ?? 0;
  int get _doneExercises => _items?.where((i) => i.done).length ?? 0;
  double get _totalVolume =>
      _items?.fold<double>(0, (s, i) => s + i.totalWeight) ?? 0;

  Future<void> _finish() async {
    if (_items == null || _saving) return; // B9：保存锁防止重复写入
    final anyDone = _items!.any((i) => i.doneCount > 0);
    if (!anyDone) {
      final quit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('没有记录任何动作'),
          content: const Text('要结束并丢弃这次训练吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续训练')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('丢弃')),
          ],
        ),
      );
      if (quit == true && mounted) Navigator.pop(context);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('结束训练'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('完成 $_doneExercises/$_totalExercises 个动作'),
              const SizedBox(height: 16),
              const Text('训练感受'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: ['轻', '刚好', '累'].map((f) {
                  return ChoiceChip(
                    label: Text(f),
                    selected: _feeling == f,
                    onSelected: (_) => setD(() => _feeling = f),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('返回')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存记录')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    _saving = true;
    try {
      final db = ref.read(databaseProvider);
      final startedAtSec = _startedAt!.millisecondsSinceEpoch ~/ 1000;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // B9：日期取开始训练那天（跨午夜结束时仍归入当天），与 startedAt 保持一致
      await db.insertWorkoutLog(
        log: WorkoutLogsCompanion.insert(
          date: fmtDate(_startedAt!),
          planId: Value(widget.planId),
          dayTitle: Value(widget.dayTitle),
          startedAt: startedAtSec,
          completedAt: Value(now),
          feeling: Value(_feeling),
        ),
        exercises: [
          for (final item in _items!)
            if (item.doneCount > 0 || item.done)
              ExerciseLogsCompanion.insert(
                workoutLogId: 0,
                name: item.plan.name,
                plannedSets: Value(item.plan.sets),
                plannedReps: Value(item.plan.reps),
                plannedWeightKg: Value(item.plan.weightKg),
                doneSets: Value(item.doneCount),
                doneReps: Value(item.sets
                    .where((s) => s.done)
                    .map((s) => s.reps)
                    .toSet()
                    .join('/')),
                doneWeightKg: Value(
                    item.doneCount == 0 ? null : (item.totalWeight / item.doneCount)),
                done: Value(item.done),
                note: Value(''),
                orderIdx: Value(item.plan.orderIdx),
              ),
        ],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('训练已记录！总负重 ${_totalVolume.toStringAsFixed(0)}kg'),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('保存失败：$e'),
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dayTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('⏱ $_elapsed',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 100, top: 4),
              children: [
                LinearProgressIndicator(
                  value: _totalExercises == 0 ? 0 : _doneExercises / _totalExercises,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                for (final item in items)
                  _ExerciseCard(
                    item: item,
                    onChanged: () {
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _finish,
        icon: const Icon(Icons.flag),
        label: const Text('结束训练'),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final _ExerciseState item;
  final VoidCallback onChanged;

  const _ExerciseCard({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.plan.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      color: item.done ? scheme.outline : null,
                    ),
                  ),
                ),
                Checkbox(
                  value: item.done,
                  onChanged: (v) {
                    item.done = v ?? false;
                    onChanged();
                  },
                ),
              ],
            ),
            Text(
              '计划：${item.plan.sets}组×${item.plan.reps}'
              '${item.plan.weightKg != null ? ' · ${fmtWeight(item.plan.weightKg!)}kg' : ' · 自重'}'
              ' · 休息${item.plan.restSeconds}s'
              '${item.plan.note.isEmpty ? '' : '\n${item.plan.note}'}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < item.sets.length; i++) _setChip(context, i),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('完成 ${item.doneCount}/${item.sets.length} 组'
                    '${item.totalWeight > 0 ? ' · ${item.totalVolumeText}' : ''}',
                    style: TextStyle(fontSize: 12, color: scheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    item.sets.add(_SetState(reps: item.plan.reps, weight: item.plan.weightKg));
                    onChanged();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('加一组'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _setChip(BuildContext context, int index) {
    final set = item.sets[index];
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: () async {
        // 长按编辑该组的实际次数与重量
        final repsCtrl = TextEditingController(text: set.reps);
        final weightCtrl =
            TextEditingController(text: set.weight == null ? '' : set.weight.toString());
        try {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('第 ${index + 1} 组记录'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: repsCtrl,
                      decoration: const InputDecoration(labelText: '次数/时长')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '重量 kg')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
              ],
            ),
          );
          if (ok == true) {
            set.reps = repsCtrl.text.trim().isEmpty ? set.reps : repsCtrl.text.trim();
            set.weight = double.tryParse(weightCtrl.text);
            onChanged();
          }
        } finally {
          // 对话框关闭后释放临时输入框控制器
          repsCtrl.dispose();
          weightCtrl.dispose();
        }
      },
      child: FilterChip(
        selected: set.done,
        label: Text(
          '${index + 1}组',
          style: TextStyle(
            fontSize: 12,
            color: set.done ? scheme.onPrimary : null,
          ),
        ),
        showCheckmark: false,
        avatar: set.weight != null
            ? Text('${fmtWeight(set.weight!)}kg',
                style: const TextStyle(fontSize: 10))
            : null,
        onSelected: (v) {
          set.done = v;
          onChanged();
        },
      ),
    );
  }
}

extension on _ExerciseState {
  String get totalVolumeText => '总负重${totalWeight.toStringAsFixed(0)}kg';
}
