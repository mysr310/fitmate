import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import 'add_food_sheet.dart';
import 'food_library_page.dart';

/// 饮食页：四餐记录
class DietPage extends ConsumerWidget {
  const DietPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final entriesAsync = ref.watch(foodEntriesProvider(date));
    final budgetAsync = ref.watch(budgetProvider);
    final totals = ref.watch(intakeTotalsProvider(date));
    final budget = budgetAsync.value;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _DateTitle(date: date),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: '常吃食物库',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FoodLibraryPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 热量进度卡
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('今日摄入',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text.rich(TextSpan(
                        text: fmtKcal(totals.kcal),
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold, color: scheme.primary),
                        children: [
                          TextSpan(
                            text: budget == null ? '' : ' / 预算 ${fmtKcal(budget.kcalTarget)}',
                            style: TextStyle(fontSize: 13, color: scheme.outline),
                          ),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: budget == null || budget.kcalTarget <= 0
                        ? 0
                        : (totals.kcal / budget.kcalTarget).clamp(0.0, 1.0),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MacroChip(label: '蛋白质', value: totals.protein, target: budget?.proteinTarget),
                      _MacroChip(label: '脂肪', value: totals.fat, target: budget?.fatTarget),
                      _MacroChip(label: '碳水', value: totals.carb, target: budget?.carbTarget),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 四餐
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (entries) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 96, top: 4),
                  children: [
                    for (final meal in MealType.values)
                      _MealSection(
                        meal: meal,
                        date: date,
                        entries: entries.where((e) => e.mealType == meal.index).toList(),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddFoodSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('记录饮食'),
      ),
    );
  }
}

class _DateTitle extends ConsumerWidget {
  final String date;
  const _DateTitle({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = date == todayString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => ref.read(selectedDateProvider.notifier).shift(-1),
        ),
        Column(
          children: [
            Text(isToday ? '今天' : date, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(weekdayName(weekdayOf(date)), style: const TextStyle(fontSize: 11)),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: date == todayString()
              ? null
              : () => ref.read(selectedDateProvider.notifier).shift(1),
        ),
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final double? target;

  const _MacroChip({required this.label, required this.value, required this.target});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text('$label ${fmtKcal(value)}g${target != null ? '/${fmtKcal(target!)}g' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: target == null || target! <= 0 ? 0 : (value / target!).clamp(0.0, 1.0),
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final MealType meal;
  final String date;
  final List<FoodEntry> entries;

  const _MealSection({required this.meal, required this.date, required this.entries});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (s, e) => s + e.kcal);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(meal.label,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${fmtKcal(total)} 千卡',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '暂无记录，点右下角「记录饮食」添加',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
              ),
            )
          else
            for (final e in entries) _EntryTile(entry: e),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final FoodEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final srcIcon = switch (entry.source) {
      'ai_photo' => Icons.photo_camera_outlined,
      'ai_text' => Icons.chat_outlined,
      'library' => Icons.bookmark_outline,
      _ => Icons.edit_outlined,
    };
    return Dismissible(
      key: ValueKey('food_${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      // R3-低12：删除失败时返回 false，条目留在列表里（避免视觉移除与数据不一致）
      confirmDismiss: (_) async {
        try {
          await ref.read(databaseProvider).deleteFoodEntry(entry.id);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
          }
          return false;
        }
      },
      child: ListTile(
        leading: Icon(srcIcon, color: scheme.primary),
        title: Text(entry.name),
        subtitle: Text(
          '${entry.grams != null ? '${fmtKcal(entry.grams!)}g · ' : ''}'
          '蛋白质 ${fmtKcal(entry.proteinG)}g · 脂肪 ${fmtKcal(entry.fatG)}g · 碳水 ${fmtKcal(entry.carbG)}g',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text('${fmtKcal(entry.kcal)} 千卡',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
