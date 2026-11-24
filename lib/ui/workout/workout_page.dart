import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import 'plan_day_detail_page.dart';
import 'plan_generate_page.dart';
import 'plan_history_page.dart';

/// 训练页：当前周计划视图
class WorkoutPage extends ConsumerWidget {
  const WorkoutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练'),
        actions: [
          IconButton(
            tooltip: '历史记录',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlanHistoryPage()),
            ),
          ),
          IconButton(
            tooltip: '计划管理',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showPlanManager(context, ref),
          ),
        ],
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (plan) {
          if (plan == null) {
            return _EmptyPlan(onGenerate: () => _goGenerate(context));
          }
          return _WeekView(plan: plan);
        },
      ),
      floatingActionButton: planAsync.value != null
          ? FloatingActionButton.extended(
              onPressed: () => _goGenerate(context),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI 生成新计划'),
            )
          : null,
    );
  }

  void _goGenerate(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanGeneratePage()));
  }

  void _showPlanManager(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref2, _) {
        final plansAsync = ref2.watch(allPlansProvider);
        final plans = plansAsync.value ?? const <WorkoutPlan>[];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('计划管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (plans.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('还没有计划，先让 AI 生成一份吧'),
                )
              else
                ...plans.map((p) => ListTile(
                      leading: Icon(
                        p.isActive ? Icons.check_circle : Icons.circle_outlined,
                        color: p.isActive ? Theme.of(ctx).colorScheme.primary : null,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        '${p.source == 'ai' ? 'AI 生成' : '手动创建'} · ${fmtDate(DateTime.fromMillisecondsSinceEpoch(p.createdAt * 1000))}',
                      ),
                      onTap: () async {
                        await ref2.read(databaseProvider).setActivePlan(p.id);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dctx) => AlertDialog(
                              title: const Text('删除计划'),
                              content: Text('确定删除「${p.name}」？该操作不可恢复。'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dctx, false),
                                    child: const Text('取消')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: const Text('删除')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ref2.read(databaseProvider).deletePlan(p.id);
                          }
                        },
                      ),
                    )),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('AI 生成新计划'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _goGenerate(ctx);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  final VoidCallback onGenerate;

  const _EmptyPlan({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            const Text('还没有训练计划',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'AI 会根据你的身体数据、近期热量摄入和体重趋势\n生成适合你的一周计划',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI 生成我的第一份计划'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekView extends ConsumerWidget {
  final WorkoutPlan plan;

  const _WeekView({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysAsync = ref.watch(planDaysProvider(plan.id));
    final todayWeekday = DateTime.now().weekday;
    final scheme = Theme.of(context).colorScheme;

    return daysAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (days) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 96, top: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (plan.source == 'ai')
                    Chip(
                      label: const Text('AI'),
                      labelStyle: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: scheme.primaryContainer,
                    ),
                ],
              ),
            ),
            if (plan.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(plan.note,
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              ),
            const SizedBox(height: 4),
            for (final day in days) _DayCard(
              day: day,
              isToday: day.weekday == todayWeekday,
            ),
          ],
        );
      },
    );
  }
}

class _DayCard extends ConsumerWidget {
  final PlanDay day;
  final bool isToday;

  const _DayCard({required this.day, required this.isToday});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final exercisesAsync = ref.watch(exercisesOfDayProvider(day.id));

    return Card(
      color: isToday ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: day.isRest
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanDayDetailPage(planId: day.planId, dayId: day.id),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: day.isRest
                      ? scheme.surfaceContainerHighest
                      : (isToday ? scheme.primary : scheme.primaryContainer),
                ),
                child: Text(
                  weekdayName(day.weekday).substring(1),
                  style: TextStyle(
                    color: day.isRest
                        ? scheme.outline
                        : (isToday ? scheme.onPrimary : scheme.onPrimaryContainer),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.isRest ? '休息日' : (day.title.isEmpty ? '训练日' : day.title),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: day.isRest ? scheme.outline : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    exercisesAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                      data: (ex) => Text(
                        day.isRest
                            ? (day.note.isEmpty ? '好好恢复，为下一次训练储能' : day.note)
                            : '${ex.length} 个动作 · ${ex.fold<int>(0, (s, e) => s + e.sets)} 组',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              if (isToday && !day.isRest)
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlanDayDetailPage(planId: day.planId, dayId: day.id),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('去训练'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else if (!day.isRest)
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
