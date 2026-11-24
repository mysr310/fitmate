import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_service.dart';
import '../../ai/parsers.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 可编辑的识别结果条目
class _EditableItem {
  final TextEditingController name;
  final TextEditingController grams;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController fat;
  final TextEditingController carb;
  double confidence;

  _EditableItem({
    required String name,
    double? grams,
    required double kcal,
    required double protein,
    required double fat,
    required double carb,
    required this.confidence,
  })  : name = TextEditingController(text: name),
        grams = TextEditingController(text: grams == null ? '' : _fmt(grams)),
        kcal = TextEditingController(text: _fmt(kcal)),
        protein = TextEditingController(text: _fmt(protein)),
        fat = TextEditingController(text: _fmt(fat)),
        carb = TextEditingController(text: _fmt(carb));

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void dispose() {
    name.dispose();
    grams.dispose();
    kcal.dispose();
    protein.dispose();
    fat.dispose();
    carb.dispose();
  }

  bool get isValid => name.text.trim().isNotEmpty;

  double get kcalValue => double.tryParse(kcal.text) ?? 0;
  double? get gramsValue => double.tryParse(grams.text);
}

/// 保存用的不可变快照（A2：任何 await 之前先固化表单内容，
/// 避免保存过程中用户编辑/删除/退出导致读到已 dispose 的 Controller）
class _SavedItem {
  final String name;
  final double? grams;
  final double kcal;
  final double protein;
  final double fat;
  final double carb;

  const _SavedItem({
    required this.name,
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carb,
  });
}

/// AI 识别结果确认页 / 手动录入页
class FoodConfirmPage extends ConsumerStatefulWidget {
  final Uint8List? photoBytes;
  final String? photoPath;
  final String? textInput;
  final bool manual;

  /// 显式记账日期；从「今日」页进入时传当天，
  /// 避免沿用饮食页留下的历史选中日期把记录写到过去（B4）
  final String? fixedDate;

  const FoodConfirmPage.fromAi({
    required this.photoBytes,
    this.photoPath,
    this.fixedDate,
    super.key,
  })  : textInput = null,
        manual = false;

  const FoodConfirmPage.fromText(String text, {this.fixedDate, super.key})
      : textInput = text,
        photoBytes = null,
        photoPath = null,
        manual = false;

  const FoodConfirmPage.manual({this.fixedDate, super.key})
      : textInput = null,
        photoBytes = null,
        photoPath = null,
        manual = true;

  @override
  ConsumerState<FoodConfirmPage> createState() => _FoodConfirmPageState();
}

class _FoodConfirmPageState extends ConsumerState<FoodConfirmPage> {
  bool _loading = false;
  String? _error;
  String? _summary;
  List<_EditableItem> _items = [];
  MealType _meal = MealType.breakfast;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _meal = _defaultMeal();
    if (widget.manual) {
      _items = [_emptyItem()];
    } else {
      _analyze();
    }
  }

  _EditableItem _emptyItem() => _EditableItem(
        name: '',
        kcal: 0,
        protein: 0,
        fat: 0,
        carb: 0,
        confidence: 1,
      );

  MealType _defaultMeal() {
    final h = DateTime.now().hour;
    if (h < 10) return MealType.breakfast;
    if (h < 15) return MealType.lunch;
    if (h < 21) return MealType.dinner;
    return MealType.snack;
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(foodAiServiceProvider);
      final FoodAiResult result;
      if (widget.photoBytes != null) {
        result = await svc.analyzePhoto(widget.photoBytes!);
      } else {
        result = await svc.analyzeText(widget.textInput ?? '');
      }
      if (!mounted) return; // 请求期间页面可能已被关闭
      final previous = _items;
      setState(() {
        _summary = result.summary;
        _items = result.items
            .map((e) => _EditableItem(
                  name: e.name,
                  grams: e.grams,
                  kcal: e.kcal,
                  protein: e.protein,
                  fat: e.fat,
                  carb: e.carb,
                  confidence: e.confidence,
                ))
            .toList();
        if (_items.isEmpty) {
          _error = 'AI 没有识别到食物，请换一张更清晰的照片，或改用文字描述。';
          _items = [_emptyItem()];
        }
        _loading = false;
      });
      _disposeItems(previous);
    } catch (e) {
      if (!mounted) return;
      final previous = _items;
      setState(() {
        _error = '$e';
        _items = [_emptyItem()];
        _loading = false;
      });
      _disposeItems(previous);
    }
  }

  /// 释放被替换掉的旧条目（含 6 个 TextEditingController）。
  /// 放到帧末执行：这一帧里旧 TextField 还没卸载，提前 dispose 会被它继续使用。
  void _disposeItems(List<_EditableItem> items) {
    if (items.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in items) {
        i.dispose();
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return; // R3-低11：setState 生效前的连点窗口
    final validItems = _items.where((i) => i.isValid && i.kcalValue > 0).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少填写一条有效记录（名称 + 热量）')));
      return;
    }
    // A2：在任何 await 之前固化快照 + 餐次，保存期间表单输入/删除不再影响写入
    final snapshot = [
      for (final it in validItems)
        _SavedItem(
          name: it.name.text.trim(),
          grams: it.gramsValue,
          kcal: it.kcalValue,
          protein: double.tryParse(it.protein.text) ?? 0,
          fat: double.tryParse(it.fat.text) ?? 0,
          carb: double.tryParse(it.carb.text) ?? 0,
        ),
    ];
    final mealIndex = _meal.index;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final String date = widget.fixedDate ?? ref.read(selectedDateProvider);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      String? relPath;
      if (widget.photoBytes != null) {
        relPath = await ref.read(photoStoreProvider).save(widget.photoBytes!);
      }

      final source = widget.photoBytes != null
          ? 'ai_photo'
          : widget.textInput != null
              ? 'ai_text'
              : 'manual';

      try {
        // 事务保证多条记录要么全部写入、要么全部不写（避免中途失败留半条）
        await db.transaction(() async {
          for (final item in snapshot) {
            await db.addFoodEntry(FoodEntriesCompanion.insert(
              date: date,
              mealType: mealIndex,
              name: item.name,
              grams: Value(item.grams),
              kcal: item.kcal,
              proteinG: Value(item.protein),
              fatG: Value(item.fat),
              carbG: Value(item.carb),
              source: source,
              photoPath: Value(relPath ?? ''),
              createdAt: now,
            ));

            // 常吃食物库更新
            await _upsertLibrary(db, item.name, item.grams, item.kcal,
                item.protein, item.fat, item.carb, now);
          }
        });
      } catch (_) {
        // 事务回滚时清理已写入的照片，避免孤儿文件（A2）
        if (relPath != null) {
          try {
            await ref.read(photoStoreProvider).delete(relPath);
          } catch (_) {}
        }
        rethrow;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已记录 ${snapshot.length} 条饮食')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 常吃食物库更新策略（A3，防止营养数据被单次记录污染）：
  /// - 有克数：换算每 100g 营养，更新/新建（新建 useCount 从 1 起）；
  /// - 无克数：只累计使用次数，不改写任何营养字段；库里没有该食物时
  ///   干脆不入库——把"整份热量"塞进"每100g"字段会污染后续估算与备份。
  Future<void> _upsertLibrary(AppDatabase db, String name, double? grams,
      double kcal, double protein, double fat, double carb, int now) async {
    final existing = await db.findFoodByName(name);
    final hasGrams = grams != null && grams > 0;
    if (existing == null) {
      if (!hasGrams) return;
      await db.addFood(FoodsCompanion.insert(
        name: name,
        kcal100: kcal / grams * 100,
        protein100: Value(protein / grams * 100),
        fat100: Value(fat / grams * 100),
        carb100: Value(carb / grams * 100),
        servingGrams: Value(grams),
        servingDesc: Value('一份约${fmtKcal(grams)}g'),
        useCount: const Value(1),
        lastUsedAt: Value(now),
      ));
      return;
    }
    if (hasGrams) {
      await db.upsertFood(existing.copyWith(
        kcal100: kcal / grams * 100,
        protein100: protein / grams * 100,
        fat100: fat / grams * 100,
        carb100: carb / grams * 100,
        servingGrams: Value(grams),
        servingDesc: '一份约${fmtKcal(grams)}g',
        useCount: existing.useCount + 1,
        lastUsedAt: now,
      ));
    } else {
      await db.upsertFood(existing.copyWith(
        useCount: existing.useCount + 1,
        lastUsedAt: now,
      ));
    }
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalKcal = _items.fold<double>(0, (s, i) => s + i.kcalValue);

    return PopScope(
      canPop: !_saving, // A2：保存进行中阻止返回，防止事务读到已 dispose 的 Controller
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.manual ? '手动录入' : '确认识别结果'),
        actions: [
          if (!widget.manual && !_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新识别',
              onPressed: _saving ? null : _analyze,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI 正在分析，请稍候…'),
                ],
              ),
            )
          : IgnorePointer(
              ignoring: _saving, // A2：保存期间锁定条目编辑/删除/添加
              child: ListView(
              padding: const EdgeInsets.only(bottom: 120, left: 12, right: 12, top: 8),
              children: [
                if (widget.photoBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      widget.photoBytes!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (_summary != null && _summary!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('AI 说明：$_summary',
                        style: TextStyle(fontSize: 12, color: scheme.outline)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: scheme.error, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13))),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                for (var i = 0; i < _items.length; i++) _itemCard(i),
                TextButton.icon(
                  onPressed: () => setState(() => _items.add(_emptyItem())),
                  icon: const Icon(Icons.add),
                  label: const Text('再添加一项食物'),
                ),
              ],
            ),
            ),
      bottomSheet: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                ignoring: _saving, // A2：保存期间锁定餐次切换
                child: SegmentedButton<MealType>(
                  segments: MealType.values
                      .map((m) => ButtonSegment(value: m, label: Text(m.label)))
                      .toList(),
                  selected: {_meal},
                  onSelectionChanged: (s) => setState(() => _meal = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('合计 ${fmtKcal(totalKcal)} 千卡',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('保存记录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _itemCard(int index) {
    final it = _items[index];
    final lowConf = it.confidence < 0.55 && !widget.manual;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: it.name,
                    decoration: const InputDecoration(labelText: '食物名称'),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    if (lowConf)
                      Tooltip(
                        message: 'AI 对此项不太确定，请核对',
                        child: Icon(Icons.help_outline, size: 18,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() {
                        it.dispose();
                        _items.removeAt(index);
                      }),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _numField(it.grams, '克数'),
                _numField(it.kcal, '热量(千卡)'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _numField(it.protein, '蛋白质(g)'),
                _numField(it.fat, '脂肪(g)'),
                _numField(it.carb, '碳水(g)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      ),
    );
  }
}
