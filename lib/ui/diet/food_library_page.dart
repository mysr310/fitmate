import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 常吃食物库
class FoodLibraryPage extends ConsumerStatefulWidget {
  const FoodLibraryPage({super.key});

  @override
  ConsumerState<FoodLibraryPage> createState() => _FoodLibraryPageState();
}

class _FoodLibraryPageState extends ConsumerState<FoodLibraryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final foodsAsync = ref.watch(foodLibraryProvider);
    final foods = (foodsAsync.value ?? const <Food>[])
        .where((f) => _query.isEmpty || f.name.contains(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('常吃食物库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索食物',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: foods.isEmpty
                ? Center(
                    child: Text(
                      '还没有常用食物\n确认过的 AI 识别结果会自动存进来',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: foods.length,
                    itemBuilder: (context, i) {
                      final f = foods[i];
                      return ListTile(
                        leading: const Icon(Icons.lunch_dining_outlined),
                        title: Text(f.name),
                        subtitle: Text(
                          '每100g：${fmtKcal(f.kcal100)}千卡 · 蛋白${fmtKcal(f.protein100)}g · 脂肪${fmtKcal(f.fat100)}g · 碳水${fmtKcal(f.carb100)}g'
                          '${f.useCount > 0 ? ' · 已用${f.useCount}次' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            ref.read(databaseProvider).deleteFood(f.id);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
