import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import 'workout_session_page.dart';

/// 某训练日详情：动作列表 + 编辑 + 开始训练
class PlanDayDetailPage extends ConsumerWidget {
  final int planId;
  final int dayId;

  const PlanDayDetailPage({required this.planId, required this.dayId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysAsync = ref.watch(planDaysProvider(planId));
    final exercisesAsync = ref.watch(exercisesOfDayProvider(dayId));
    final scheme = Theme.of(context).colorScheme;

    // R3-低12：区分加载/出错/已删除三种状态，不再无限转圈
    final dayAsyncResult = daysAsync.when(
      loading: () => null,
      error: (e, _) => null,
      data: (days) {
        return days.where((d) => d.id == dayId).firstOrNull;
      },
    );
    final day = dayAsyncResult;

    if (day == null) {
      if (daysAsync.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('训练日')),
          body: Center(child: Text('加载失败：${daysAsync.error}')),
        );
      }
      if (daysAsync.isLoading) {
        return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('训练日')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('该训练日已被删除或不存在'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${weekdayName(day.weekday)} · ${day.title.isEmpty ? '训练日' : day.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editDay(context, ref, day),
          ),
        ],
      ),
      body: exercisesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (exercises) => ListView(
          padding: const EdgeInsets.only(bottom: 96, top: 8),
          children: [
            if (day.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(day.note, style: TextStyle(color: scheme.outline, fontSize: 13)),
              ),
            for (final ex in exercises) _ExerciseTile(exercise: ex),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () => _addExercise(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('添加动作'),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutSessionPage(
              planId: planId,
              dayId: dayId,
              dayTitle: day.title.isEmpty ? weekdayName(day.weekday) : day.title,
            ),
          ),
        ),
        icon: const Icon(Icons.play_arrow),
        label: const Text('开始训练'),
      ),
    );
  }

  Future<void> _editDay(BuildContext context, WidgetRef ref, PlanDay day) async {
    final titleCtrl = TextEditingController(text: day.title);
    final noteCtrl = TextEditingController(text: day.note);
    bool isRest = day.isRest;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('编辑${weekdayName(day.weekday)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('休息日'),
                value: isRest,
                onChanged: (v) => setD(() => isRest = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (!isRest)
                TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: '训练主题（如：胸+三头）')),
              const SizedBox(height: 8),
              TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: '备注')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    titleCtrl.dispose();
    noteCtrl.dispose();
    if (ok == true) {
      await ref.read(databaseProvider).updatePlanDay(day.copyWith(
            title: isRest ? '休息日' : title,
            note: note,
            isRest: isRest,
          ));
    }
  }

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final result = await _exerciseDialog(context, null);
    if (result != null) {
      final existing = await ref.read(databaseProvider).getExercisesOfDay(dayId);
      // C1：取最大序号+1，删除中间动作后新动作不会与现有序号重复
      final nextIdx = existing.isEmpty
          ? 0
          : existing.map((e) => e.orderIdx).reduce((a, b) => a > b ? a : b) + 1;
      await ref.read(databaseProvider).addExercise(PlanExercisesCompanion.insert(
            dayId: dayId,
            name: result.name,
            sets: Value(result.sets),
            reps: Value(result.reps),
            weightKg: Value(result.weightKg),
            restSeconds: Value(result.restSeconds),
            note: Value(result.note),
            orderIdx: Value(nextIdx),
          ));
    }
  }
}

/// 弹出的动作编辑对话框返回值
class ExerciseFormResult {
  final String name;
  final int sets;
  final String reps;
  final double? weightKg;
  final int restSeconds;
  final String note;

  ExerciseFormResult({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.restSeconds,
    required this.note,
  });
}

Future<ExerciseFormResult?> _exerciseDialog(
    BuildContext context, PlanExercise? initial) async {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final setsCtrl = TextEditingController(text: (initial?.sets ?? 3).toString());
  final repsCtrl = TextEditingController(text: initial?.reps ?? '8-12');
  final weightCtrl =
      TextEditingController(text: initial?.weightKg == null ? '' : initial!.weightKg.toString());
  final restCtrl = TextEditingController(text: (initial?.restSeconds ?? 90).toString());
  final noteCtrl = TextEditingController(text: initial?.note ?? '');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial == null ? '添加动作' : '编辑动作'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '动作名称')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: setsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '组数'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: repsCtrl,
                        decoration: const InputDecoration(labelText: '次数/时长'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '负重kg（空=自重）'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: restCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '组间休息(秒)'))),
              ],
            ),
            const SizedBox(height: 8),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: '要点备注')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ),
  );

  final name = nameCtrl.text.trim();
  // B8：全部钳制到合法范围，防止负数/极端值炸掉训练页（List.generate RangeError）
  final sets = (int.tryParse(setsCtrl.text) ?? 3).clamp(1, 50);
  final reps = repsCtrl.text.trim();
  final rawWeight = double.tryParse(weightCtrl.text);
  final weight = (rawWeight == null || rawWeight <= 0) ? null : rawWeight.clamp(0.5, 500).toDouble();
  final rest = (int.tryParse(restCtrl.text) ?? 90).clamp(0, 600);
  final note = noteCtrl.text.trim();
  for (final c in [nameCtrl, setsCtrl, repsCtrl, weightCtrl, restCtrl, noteCtrl]) {
    c.dispose();
  }
  if (ok != true || name.isEmpty) return null;
  return ExerciseFormResult(
    name: name,
    sets: sets,
    reps: reps.isEmpty ? '8-12' : reps,
    weightKg: weight,
    restSeconds: rest,
    note: note,
  );
}

class _ExerciseTile extends ConsumerWidget {
  final PlanExercise exercise;

  const _ExerciseTile({required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
            '${exercise.orderIdx + 1}',
            style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${exercise.sets}组 × ${exercise.reps}'
          '${exercise.weightKg != null ? ' · ${fmtWeight(exercise.weightKg!)}kg' : ' · 自重'}'
          ' · 休息${exercise.restSeconds}s'
          '${exercise.note.isEmpty ? '' : '\n${exercise.note}'}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: exercise.note.isNotEmpty,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final db = ref.read(databaseProvider);
            if (v == 'edit') {
              final result = await _exerciseDialog(context, exercise);
              if (result != null) {
                await db.updateExercise(exercise.copyWith(
                  name: result.name,
                  sets: result.sets,
                  reps: result.reps,
                  weightKg: Value(result.weightKg),
                  restSeconds: result.restSeconds,
                  note: result.note,
                ));
              }
            } else if (v == 'delete') {
              await db.deleteExercise(exercise.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}
