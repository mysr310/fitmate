import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../diet/add_food_sheet.dart';
import '../weight/weight_page.dart' show showWeightRecordDialog;

/// 今日页：聚合
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(uiRefreshProvider); // R4-N3：跨午夜恢复时强制重建
    final budgetAsync = ref.watch(budgetProvider);
    final totals = ref.watch(intakeTotalsProvider(todayString()));
    final profile = ref.watch(profileProvider).value;
    final weightLogs = ref.watch(weightLogsProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final budget = budgetAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('今日概览', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('${todayString()} ${weekdayName(weekdayOf(todayString()))}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 热量环卡
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CalorieRing(
                      eaten: totals.kcal,
                      target: budget?.kcalTarget ?? 0,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budget == null ? '完善身体档案后显示预算' : '每日预算 ${fmtKcal(budget.kcalTarget)} 千卡',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        _MacroRow(label: '蛋白质', value: totals.protein, target: budget?.proteinTarget),
                        _MacroRow(label: '脂肪', value: totals.fat, target: budget?.fatTarget),
                        _MacroRow(label: '碳水', value: totals.carb, target: budget?.carbTarget),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            ref.read(rootTabProvider.notifier).go(1);
                            // B4：从今日页记账固定写今天，不沿用饮食页的历史选中日期
                            showAddFoodSheet(context, fixedDate: todayString());
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('记录饮食'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 今日训练卡
          _TodayWorkoutCard(
            onJumpWorkout: () => ref.read(rootTabProvider.notifier).go(2),
          ),
          // 体重卡
          Card(
            child: ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: Text(
                weightLogs == null || weightLogs.isEmpty
                    ? '记录今天体重'
                    : '最新体重 ${fmtWeight(weightLogs.first.weightKg)}kg'
                        '${profile?.targetWeightKg != null ? ' · 目标 ${fmtWeight(profile!.targetWeightKg!)}kg' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                weightLogs == null || weightLogs.isEmpty
                    ? '记录体重，追踪趋势'
                    : weightLogs.first.date == todayString()
                        ? '今天已记录 ✓'
                        : '今天还没记录，点这里称一称',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final current = weightLogs?.firstOrNull?.weightKg;
                await showWeightRecordDialog(context, ref, current);
              },
            ),
          ),
          // AI 摘要卡（未配置提醒）
          if (!(ref.watch(aiSlotServiceProvider).anyReady))
            Card(
              color: scheme.tertiaryContainer.withValues(alpha: 0.4),
              child: ListTile(
                leading: Icon(Icons.auto_awesome, color: scheme.tertiary),
                title: const Text('还没配置 AI 接口',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('配置后可用：拍照识别卡路里、AI 生成训练计划',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref.read(rootTabProvider.notifier).go(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final double? target;

  const _MacroRow({required this.label, required this.value, required this.target});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: target == null || target! <= 0 ? 0 : (value / target!).clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              '${fmtKcal(value)}${target != null ? '/${fmtKcal(target!)}g' : ''}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayWorkoutCard extends ConsumerWidget {
  final VoidCallback onJumpWorkout;

  const _TodayWorkoutCard({required this.onJumpWorkout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(activePlanProvider);
    final scheme = Theme.of(context).colorScheme;
    final plan = planAsync.value;
    final todayWeekday = DateTime.now().weekday;

    return planAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (_) {
        if (plan == null) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.fitness_center, color: scheme.primary),
              title: const Text('还没有训练计划',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('去「训练」页让 AI 生成一份周计划',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: onJumpWorkout,
            ),
          );
        }
        final days = ref.watch(planDaysProvider(plan.id)).value ?? const <PlanDay>[];
        final today = days.where((d) => d.weekday == todayWeekday).firstOrNull;
        if (today == null) {
          return Card(
            child: ListTile(
              title: Text('当前计划：${plan.name}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: onJumpWorkout,
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: Icon(
              today.isRest ? Icons.self_improvement : Icons.fitness_center,
              color: today.isRest ? scheme.outline : scheme.primary,
            ),
            title: Text(
              today.isRest ? '今天休息日' : '今天：${today.title.isEmpty ? '训练日' : today.title}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              today.isRest
                  ? '好好恢复，明天见'
                  : '${plan.name} · 点开始训练打卡',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onJumpWorkout,
          ),
        );
      },
    );
  }
}

/// 热量圆环
class CalorieRing extends StatelessWidget {
  final double eaten;
  final double target;

  const CalorieRing({required this.eaten, required this.target, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = target <= 0 ? 0.0 : (eaten / target).clamp(0.0, 1.0);
    final over = target > 0 && eaten > target;
    final remain = (target - eaten);

    return CustomPaint(
      painter: _RingPainter(
        progress: progress,
        trackColor: scheme.surfaceContainerHighest,
        progressColor: over ? scheme.error : scheme.primary,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fmtKcal(eaten),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: over ? scheme.error : scheme.primary,
              ),
            ),
            Text(
              target <= 0 ? '千卡' : (remain >= 0 ? '剩 ${fmtKcal(remain)} 千卡' : '超出 ${fmtKcal(-remain)} 千卡'),
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    final sweep = 2 * 3.141592653589793 * progress;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.141592653589793 / 2,
        sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}
