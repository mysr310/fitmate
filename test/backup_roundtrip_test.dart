import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fitmate/core/utils.dart';
import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/services/backup_service.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fitbak_test');
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    tmp.delete(recursive: true);
  });

  Future<void> seed() async {
    // 种子数据
    await db.saveProfile(ProfilesCompanion.insert(
      name: const Value('小明'),
      sex: 'male',
      age: 25,
      heightCm: 172,
      weightKg: 66,
      activityLevel: ActivityLevel.light.name,
      goal: GoalType.cut.name,
      targetWeightKg: const Value(60),
      onboardingDone: const Value(true),
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
    await db.upsertWeight('2026-11-25', 65.5);
    await db.addFoodEntry(FoodEntriesCompanion.insert(
      date: '2026-11-25',
      mealType: 0,
      name: '米饭',
      grams: const Value(200),
      kcal: 232,
      proteinG: const Value(5.4),
      fatG: const Value(0.6),
      carbG: const Value(51.7),
      source: 'ai_photo',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
    await db.insertFullPlan(
      name: '测试计划',
      source: 'ai',
      note: '备注',
      makeActive: true,
      days: [
        PlanDaySpec(weekday: 1, title: '胸', exercises: [
          PlanExerciseSpec(name: '俯卧撑', sets: 4, reps: '8-12'),
        ]),
        PlanDaySpec(weekday: 2, isRest: true, title: '休息日'),
      ],
    );
    await db.addAiConfig(AiConfigsCompanion.insert(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-SECRET-KEY',
      createdAt: 0,
    ));
  }

  test('备份 → 覆盖恢复 数据完整、不含 API Key', () async {
    await seed();
    final svc0 = BackupService(db, baseDir: tmp);
    final file = await svc0.createBackup(auto: false);
    final raw = await file.readAsBytes();
    final rawStr = String.fromCharCodes(raw);
    expect(rawStr.contains('sk-SECRET-KEY'), isFalse, reason: 'API Key 不能进备份');

    final parsed = await svc0.parseBackup(raw);
    final db2 = AppDatabase(executor: NativeDatabase.memory());
    final svc2 = BackupService(db2, baseDir: tmp);
    final summary = await svc2.restore(
      payload: parsed.payload,
      photos: parsed.photos,
      overwrite: true,
    );
    expect(summary.counts['food_entries'], 1);
    expect(summary.counts['workout_plans'], 1);
    expect(summary.counts['weight_logs'], 1);
    expect(summary.counts['profiles'], 1);

    final entries = await db2.select(db2.foodEntries).get();
    expect(entries.single.name, '米饭');
    expect(entries.single.grams, 200);
    expect(entries.single.source, 'ai_photo');

    final weights = await db2.select(db2.weightLogs).get();
    expect(weights.single.weightKg, 65.5);
    expect(weights.single.date, '2026-11-25');

    final profile = await db2.getProfile();
    expect(profile!.name, '小明');
    expect(profile.targetWeightKg, 60);

    final plan = await db2.getActivePlan();
    expect(plan, isNotNull);
    expect(plan!.name, '测试计划');
    final days = await db2.getPlanDays(plan.id);
    expect(days, hasLength(2));
    final exs = await db2.getExercisesOfDay(days.first.id);
    expect(exs.single.name, '俯卧撑');

    // Key 被剥离 → 恢复出的接口 Key 为空
    final configs = await db2.getAiConfigs();
    expect(configs.single.name, 'DeepSeek');
    expect(configs.single.apiKey, '');

    await db2.close();
  });

  test('备份 → 合并恢复：不覆盖现有档案，追加饮食记录', () async {
    await seed();
    final svc0 = BackupService(db, baseDir: tmp);
    final file = await svc0.createBackup(auto: false);
    final parsed = await svc0.parseBackup(await file.readAsBytes());

    final db2 = AppDatabase(executor: NativeDatabase.memory());
    // 目标库已有自己的档案和一条记录
    await db2.saveProfile(ProfilesCompanion.insert(
      sex: 'female',
      age: 30,
      heightCm: 160,
      weightKg: 50,
      activityLevel: ActivityLevel.light.name,
      goal: GoalType.maintain.name,
      onboardingDone: const Value(true),
      createdAt: 1,
    ));
    await db2.addFoodEntry(FoodEntriesCompanion.insert(
      date: '2026-11-24',
      mealType: 2,
      name: '本地已有的一餐',
      kcal: 100,
      source: 'manual',
      createdAt: 1,
    ));

    final svc2 = BackupService(db2, baseDir: tmp);
    final summary = await svc2.restore(
      payload: parsed.payload,
      photos: parsed.photos,
      overwrite: false,
    );
    expect(summary.counts['profiles'], isNull, reason: '已有档案时合并不应恢复档案');

    final entries = await db2.select(db2.foodEntries).get();
    expect(entries, hasLength(2));
    final names = entries.map((e) => e.name).toSet();
    expect(names, containsAll(['米饭', '本地已有的一餐']));

    final profile = await db2.getProfile();
    expect(profile!.name, '健身者'); // 默认名，未被覆盖

    // 合并的计划不应激活
    final active = await db2.getActivePlan();
    expect(active, isNull);

    await db2.close();
  });

  test('损坏的备份文件被拒绝', () async {
    await seed();
    final svc = BackupService(db, baseDir: tmp);
    expect(
      () => svc.parseBackup([1, 2, 3, 4]),
      throwsException,
    );
  });

  test('恢复照片写入应用目录，而不是临时目录', () async {
    // 不调用 backupDir，模拟「导入备份恢复」的调用顺序
    final svc = BackupService(db, baseDir: tmp);
    final summary = await svc.restore(
      payload: <String, dynamic>{
        'app': 'fitmate',
        'version': BackupService.version,
        'created_at': 0,
        'tables': <String, dynamic>{},
      },
      photos: {
        'meal.jpg': [1, 2, 3],
      },
      overwrite: true,
    );
    expect(summary.photos, 1);
    final restored = File(p.join(tmp.path, 'food_photos', 'meal.jpg'));
    expect(await restored.exists(), isTrue, reason: '照片应恢复到 documents/food_photos');
    expect(await restored.readAsBytes(), [1, 2, 3]);
  });

  test('合并恢复不会用备份里同 id 的食物覆盖本地食物', () async {
    final localId = await db.addFood(FoodsCompanion.insert(
      name: '苹果',
      kcal100: 52,
      protein100: const Value(0.3),
    ));
    expect(localId, 1, reason: '本地第一条食物 id 为 1');

    final payload = <String, dynamic>{
      'tables': <String, dynamic>{
        'foods': [
          {
            'id': 1,
            'name': '米饭',
            'kcal100': 116.0,
            'protein100': 2.6,
            'fat100': 0.3,
            'carb100': 25.9,
            'servingGrams': 200.0,
            'servingDesc': '一碗',
            'useCount': 3,
            'lastUsedAt': 0,
          }
        ],
      },
    };
    await BackupService(db, baseDir: tmp).restore(
      payload: payload,
      photos: const {},
      overwrite: false,
    );

    final foods = await db.select(db.foods).get();
    expect(foods.map((f) => f.name), containsAll(['苹果', '米饭']));
    final apple = foods.firstWhere((f) => f.name == '苹果');
    expect(apple.kcal100, 52, reason: '本地食物不能被备份中的同 id 行替换');
  });

  test('latestBackup 按文件名时间取最新，不受「自动/手动」前缀影响', () async {
    final svc = BackupService(db, baseDir: tmp);
    final dir = await svc.backupDir;
    final older = File(p.join(dir.path, '自动备份_20261126_1300.fitbak'));
    final newer = File(p.join(dir.path, '健身备份_20261126_1400.fitbak'));
    await older.writeAsString('old');
    await newer.writeAsString('new');

    final latest = await svc.latestBackup();
    expect(latest?.path, newer.path, reason: '最新备份应按文件名中的时间戳判断');
  });
}
