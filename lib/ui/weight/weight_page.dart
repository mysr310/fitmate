import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 体重页：记录 + 趋势图 + 目标
class WeightPage extends ConsumerWidget {
  const WeightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(weightLogsProvider);
    final profile = ref.watch(profileProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('体重'),
        actions: [
          IconButton(
            tooltip: '设置目标体重',
            icon: const Icon(Icons.flag_outlined),
            onPressed: profile == null ? null : () => _editTarget(context, ref, profile),
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (logsRaw) {
          final logs = logsRaw.reversed.toList(); // 旧 → 新
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monitor_weight_outlined, size: 64, color: scheme.outline),
                  const SizedBox(height: 12),
                  const Text('还没有体重记录'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _record(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('记录今天体重'),
                  ),
                ],
              ),
            );
          }
          final current = logs.last;
          final first = logs.first;
          final diff = current.weightKg - first.weightKg;
          final target = profile?.targetWeightKg;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // 统计卡
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _Stat(label: '当前', value: '${fmtWeight(current.weightKg)}kg'),
                          _Stat(
                              label: '起始',
                              value: '${fmtWeight(first.weightKg)}kg'),
                          _Stat(
                              label: '目标',
                              value: target == null ? '未设置' : '${fmtWeight(target)}kg'),
                          _Stat(
                              label: '累计变化',
                              value: '${diff >= 0 ? '+' : ''}${fmtWeight(diff)}kg',
                              color: diff == 0
                                  ? null
                                  : (diff < 0 ? Colors.green : Colors.orange),
                          ),
                        ],
                      ),
                      if (target != null) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _targetProgress(first.weightKg, current.weightKg, target)
                              .clamp(0.0, 1.0),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 趋势图
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('趋势', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: _TrendChart(logs: logs),
                      ),
                    ],
                  ),
                ),
              ),
              // 记录按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: FilledButton.icon(
                  onPressed: () => _record(context, ref, current.weightKg),
                  icon: const Icon(Icons.add),
                  label: Text(current.date == todayString() ? '更新今天的体重' : '记录今天的体重'),
                ),
              ),
              // 近期记录
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('近期记录', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              for (final log in logs.reversed.take(14))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.chevron_right),
                  title: Text('${log.date} ${weekdayName(weekdayOf(log.date))}',
                      style: const TextStyle(fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${fmtWeight(log.weightKg)}kg',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            // C2：删除加异常兜底，失败时提示而不是静默
                            try {
                              await ref.read(databaseProvider).customStatement(
                                    'DELETE FROM weight_logs WHERE id = ?',
                                    [log.id],
                                  );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('删除失败：$e')));
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _targetProgress(double start, double current, double target) {
    final total = target - start;
    if (total.abs() < 0.01) return 1;
    return (current - start) / total;
  }

  Future<void> _record(BuildContext context, WidgetRef ref, double? current) =>
      showWeightRecordDialog(context, ref, current);

  Future<void> _editTarget(BuildContext context, WidgetRef ref, Profile profile) async {
    final ctrl = TextEditingController(
        text: profile.targetWeightKg == null ? '' : fmtWeight(profile.targetWeightKg!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目标体重'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '目标体重（kg，留空则取消目标）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    final v = double.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok == true) {
      await ref.read(databaseProvider).saveProfile(ProfilesCompanion(
            targetWeightKg: Value(v),
          ));
    }
  }
}

/// 记录体重对话框（今日页与体重页共用）
Future<void> showWeightRecordDialog(BuildContext context, WidgetRef ref, double? current) async {
  final ctrl = TextEditingController(text: current == null ? '' : fmtWeight(current));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('记录体重'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '体重（kg）'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
      ],
    ),
  );
  final v = double.tryParse(ctrl.text);
  ctrl.dispose();
  if (ok == true && v != null && v > 20 && v < 300) {
    await ref.read(databaseProvider).upsertWeight(todayString(), v);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已记录：${fmtWeight(v)}kg')));
    }
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<WeightLog> logs;

  const _TrendChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 最多展示最近 90 条
    final shown = logs.length > 90 ? logs.sublist(logs.length - 90) : logs;
    final values = shown.map((l) => l.weightKg).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(0.3, 5.0);

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: _yInterval(maxY - minY),
          getDrawingHorizontalLine: (v) =>
              FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(0),
                style: TextStyle(fontSize: 10, color: scheme.outline),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: shown.length > 2,
              reservedSize: 22,
              interval: (shown.length / 4).ceilToDouble().clamp(1, 45),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                // 首尾与分段显示日期
                final d = shown[i].date;
                final md = d.substring(5);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(md, style: TextStyle(fontSize: 9, color: scheme.outline)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${shown[s.x.toInt()].date}\n${fmtWeight(s.y)}kg',
                      TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < shown.length; i++) FlSpot(i.toDouble(), shown[i].weightKg),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: scheme.primary,
            dotData: FlDotData(
              show: shown.length <= 40,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: scheme.primary,
                strokeColor: Colors.white,
                strokeWidth: 1,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  double _yInterval(double range) {
    if (range <= 2) return 0.5;
    if (range <= 6) return 1;
    return (range / 5).ceilToDouble();
  }
}
