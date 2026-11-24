import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/core/utils.dart';
import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/services/calorie_budget.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  FoodEntriesCompanion entry({
    String date = '2026-11-25',
    int meal = 1,
    String name = '米饭',
    double kcal = 232,
    double protein = 5.4,
    double fat = 0.6,
    double carb = 51.7,
    String source = 'ai_photo',
  }) {
    return FoodEntriesCompanion.insert(
      date: date,
      mealType: meal,
      name: name,
      kcal: kcal,
      proteinG: Value(protein),
      fatG: Value(fat),
      carbG: Value(carb),
      grams: const Value(200),
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  test('插入饮食记录 → 当日流式查询可见、按餐次排序', () async {
    await db.addFoodEntry(entry(meal: 1, name: '米饭'));
    await db.addFoodEntry(entry(meal: 0, name: '煎蛋', kcal: 180));

    final entries = await db.watchFoodEntries('2026-11-25').first;
    expect(entries, hasLength(2));
    // 按餐次排序：早餐(0)在前
    expect(entries.first.mealType, 0);
    expect(entries.first.name, '煎蛋');
  });

  test('删除饮食记录生效', () async {
    final id = await db.addFoodEntry(entry());
    expect(await db.watchFoodEntries('2026-11-25').first, hasLength(1));
    await db.deleteFoodEntry(id);
    expect(await db.watchFoodEntries('2026-11-25').first, isEmpty);
  });

  test('多日汇总：IntakeTotals 累计正确', () async {
    await db.addFoodEntry(entry(kcal: 232, protein: 5.4, fat: 0.6, carb: 51.7));
    await db.addFoodEntry(entry(name: '牛奶', kcal: 150, protein: 8, fat: 5, carb: 12));

    final rows = await db.getFoodEntriesRange(['2026-11-25']);
    final totals = IntakeTotals.fromEntries(rows);
    expect(totals.kcal, closeTo(382, 0.01));
    expect(totals.protein, closeTo(13.4, 0.01));
    expect(totals.fat, closeTo(5.6, 0.01));
    expect(totals.carb, closeTo(63.7, 0.01));
  });

  test('7 天热量均值（AI 计划上下文的数据源）', () async {
    final dates = lastNDays(7);
    // 只有 3 天有记录
    await db.addFoodEntry(entry(date: dates[0], kcal: 2000));
    await db.addFoodEntry(entry(date: dates[2], kcal: 1800));
    await db.addFoodEntry(entry(date: dates[6], kcal: 2200));

    final all = await db.getFoodEntriesRange(dates);
    expect(all, hasLength(3));
    final total = all.fold<double>(0, (s, e) => s + e.kcal);
    final avg = total / 7;
    expect(avg, closeTo(6000 / 7, 0.01));
  });

  test('体重 upsert：同日覆盖', () async {
    await db.upsertWeight('2026-11-25', 65);
    await db.upsertWeight('2026-11-25', 64.2);
    final logs = await db.select(db.weightLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.weightKg, 64.2);
  });

  test('计划保存与激活切换', () async {
    final id1 = await db.insertFullPlan(
      name: '计划A',
      source: 'ai',
      note: '',
      makeActive: true,
      days: [PlanDaySpec(weekday: 1, title: '胸', exercises: [PlanExerciseSpec(name: '俯卧撑')])],
    );
    final id2 = await db.insertFullPlan(
      name: '计划B',
      source: 'manual',
      note: '',
      makeActive: true,
      days: [PlanDaySpec(weekday: 2, title: '背', exercises: [PlanExerciseSpec(name: '划船')])],
    );

    var active = await db.getActivePlan();
    expect(active!.id, id2, reason: '后插入且设为当前的应胜出');

    await db.setActivePlan(id1);
    active = await db.getActivePlan();
    expect(active!.id, id1);

    // 删除计划级联
    await db.deletePlan(id2);
    final daysOfDeleted = await db.getPlanDays(id2);
    expect(daysOfDeleted, isEmpty);
  });

  test('训练打卡：日志与动作明细一起写入', () async {
    final logId = await db.insertWorkoutLog(
      log: WorkoutLogsCompanion.insert(
        date: '2026-11-25',
        dayTitle: Value('胸'),
        startedAt: 1000,
        completedAt: const Value(2400),
        feeling: Value('刚好'),
      ),
      exercises: [
        ExerciseLogsCompanion.insert(
          workoutLogId: 0,
          name: '俯卧撑',
          doneSets: const Value(4),
          doneReps: const Value('10'),
          done: const Value(true),
          orderIdx: const Value(0),
        ),
      ],
    );
    final exs = await db.getExercisesOfLog(logId);
    expect(exs.single.name, '俯卧撑');
    expect(exs.single.doneSets, 4);
    expect(exs.single.doneWeightKg, isNull);
  });
}
