import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// ==================== 表定义 ====================

/// 身体档案（单行，onboarding 创建）
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant('健身者'))();
  TextColumn get sex => text().withLength(min: 1, max: 10)(); // male / female
  IntColumn get age => integer()();
  RealColumn get heightCm => real()();
  RealColumn get weightKg => real()(); // 最近已知体重（冗余，用于 AI 上下文）
  TextColumn get activityLevel => text()(); // ActivityLevel.name
  TextColumn get goal => text()(); // GoalType.name
  RealColumn get targetWeightKg => real().nullable()();
  RealColumn get proteinPerKg => real().withDefault(const Constant(1.8))();
  TextColumn get equipmentNote => text().withDefault(const Constant(''))(); // 器材说明
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()(); // epoch seconds
}

/// AI 接口档案（OpenAI 兼容）
class AiConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()(); // 例: https://api.deepseek.com
  TextColumn get apiKey => text()();
  IntColumn get createdAt => integer()();
}

/// 键值设置
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 周训练计划
class WorkoutPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get source => text()(); // ai / manual
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
}

/// 计划中的某一天（weekday: 1=周一 ... 7=周日）
class PlanDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId => integer().references(WorkoutPlans, #id)();
  IntColumn get weekday => integer()();
  BoolColumn get isRest => boolean().withDefault(const Constant(false))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 训练日中的动作
class PlanExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get dayId => integer().references(PlanDays, #id)();
  IntColumn get orderIdx => integer().withDefault(const Constant(0))();
  TextColumn get name => text()();
  IntColumn get sets => integer().withDefault(const Constant(3))();
  TextColumn get reps => text().withDefault(const Constant('8-12'))(); // 次数或时长描述
  RealColumn get weightKg => real().nullable()();
  IntColumn get restSeconds => integer().withDefault(const Constant(90))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 一次训练记录
class WorkoutLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get planId => integer().nullable()();
  TextColumn get dayTitle => text().withDefault(const Constant(''))();
  IntColumn get startedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get feeling => text().withDefault(const Constant(''))(); // 轻/刚好/累
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 训练中每个动作的完成记录
class ExerciseLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutLogId => integer().references(WorkoutLogs, #id)();
  IntColumn get orderIdx => integer().withDefault(const Constant(0))();
  TextColumn get name => text()();
  IntColumn get plannedSets => integer().withDefault(const Constant(0))();
  TextColumn get plannedReps => text().withDefault(const Constant(''))();
  RealColumn get plannedWeightKg => real().nullable()();
  IntColumn get doneSets => integer().withDefault(const Constant(0))();
  TextColumn get doneReps => text().withDefault(const Constant(''))();
  RealColumn get doneWeightKg => real().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 常吃食物库（每 100g 营养）
class Foods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get kcal100 => real()();
  RealColumn get protein100 => real().withDefault(const Constant(0))();
  RealColumn get fat100 => real().withDefault(const Constant(0))();
  RealColumn get carb100 => real().withDefault(const Constant(0))();
  RealColumn get servingGrams => real().nullable()(); // 常用一份的克数
  TextColumn get servingDesc => text().withDefault(const Constant(''))(); // 如 "1碗(200g)"
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  IntColumn get lastUsedAt => integer().withDefault(const Constant(0))();
}

/// 饮食记录
class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get mealType => integer()(); // 0早 1午 2晚 3加餐
  TextColumn get name => text()();
  RealColumn get grams => real().nullable()();
  RealColumn get kcal => real()();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();
  RealColumn get carbG => real().withDefault(const Constant(0))();
  TextColumn get source => text()(); // ai_photo / ai_text / library / manual
  TextColumn get photoPath => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
}

/// 体重记录（一天一条，重复记录覆盖）
class WeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text().unique()();
  RealColumn get weightKg => real()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 本地备份记录
class Backups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get kind => text().withDefault(const Constant('manual'))(); // auto / manual
  IntColumn get createdAt => integer()();
}

/// ==================== 数据库 ====================

@DriftDatabase(tables: [
  Profiles,
  AiConfigs,
  Settings,
  WorkoutPlans,
  PlanDays,
  PlanExercises,
  WorkoutLogs,
  ExerciseLogs,
  Foods,
  FoodEntries,
  WeightLogs,
  Backups,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
      : super(
          executor ??
              driftDatabase(
                name: 'fitmate',
                web: DriftWebOptions(
                  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                  driftWorker: Uri.parse('drift_worker.js'),
                ),
              ),
        );

  @override
  int get schemaVersion => 1;

  // ---------- 设置 ----------
  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(Setting(key: key, value: value));

  Future<int> getSettingInt(String key, int fallback) async {
    final v = await getSetting(key);
    return int.tryParse(v ?? '') ?? fallback;
  }

  Future<void> setSettingInt(String key, int value) => setSetting(key, '$value');

  // ---------- 身体档案 ----------
  // 取"最新一条"而不是 watchSingleOrNull：万一历史数据/异常备份造成多行，
  // 单行断言会让 App 直接进入错误页（B1 防御）。
  Stream<Profile?> watchProfile() =>
      (select(profiles)..where((p) => p.onboardingDone.equals(true))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
            ..limit(1))
          .watchSingleOrNull();

  Future<Profile?> getProfile() async {
    final list = await (select(profiles)..where((p) => p.onboardingDone.equals(true))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
          ..limit(1))
        .get();
    return list.isEmpty ? null : list.first;
  }

  /// 事务内"查-插"保证原子性：并发双击建档只会产生一行（B1）
  Future<int> saveProfile(ProfilesCompanion c) {
    return transaction(() async {
      final existing = await getProfile();
      if (existing == null) {
        return into(profiles).insert(c);
      }
      await (update(profiles)..where((p) => p.id.equals(existing.id))).write(c);
      return existing.id;
    });
  }

  // ---------- AI 档案 ----------
  Stream<List<AiConfig>> watchAiConfigs() => select(aiConfigs).watch();
  Future<List<AiConfig>> getAiConfigs() => select(aiConfigs).get();

  Future<AiConfig?> getAiConfig(int id) =>
      (select(aiConfigs)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> addAiConfig(AiConfigsCompanion c) => into(aiConfigs).insert(c);

  Future<bool> updateAiConfig(AiConfig c) => update(aiConfigs).replace(c);

  Future<int> deleteAiConfig(int id) =>
      (delete(aiConfigs)..where((c) => c.id.equals(id))).go();

  // ---------- 饮食 ----------
  Stream<List<FoodEntry>> watchFoodEntries(String date) =>
      (select(foodEntries)..where((e) => e.date.equals(date))
            ..orderBy([(e) => OrderingTerm(expression: e.mealType), (e) => OrderingTerm(expression: e.createdAt)]))
          .watch();

  Stream<List<FoodEntry>> watchFoodEntriesRange(List<String> dates) =>
      (select(foodEntries)..where((e) => e.date.isIn(dates))).watch();

  Future<List<FoodEntry>> getFoodEntriesRange(List<String> dates) =>
      (select(foodEntries)..where((e) => e.date.isIn(dates))).get();

  Future<int> addFoodEntry(FoodEntriesCompanion c) => into(foodEntries).insert(c);

  Future<bool> updateFoodEntry(FoodEntry e) => update(foodEntries).replace(e);

  Future<int> deleteFoodEntry(int id) =>
      (delete(foodEntries)..where((e) => e.id.equals(id))).go();

  // ---------- 食物库 ----------
  Stream<List<Food>> watchFoods({String? query}) {
    final sel = select(foods);
    if (query != null && query.trim().isNotEmpty) {
      sel.where((f) => f.name.like('%${query.trim()}%'));
    }
    sel.orderBy([
      (f) => OrderingTerm.desc(f.useCount),
      (f) => OrderingTerm.desc(f.lastUsedAt),
    ]);
    return sel.watch();
  }

  Future<List<Food>> searchFoods(String query) {
    return (select(foods)..where((f) => f.name.like('%${query.trim()}%'))
          ..orderBy([(f) => OrderingTerm.desc(f.useCount)]))
        .get();
  }

  Future<Food?> findFoodByName(String name) =>
      (select(foods)..where((f) => f.name.equals(name))).getSingleOrNull();

  Future<bool> upsertFood(Food f) => update(foods).replace(f);

  Future<int> addFood(FoodsCompanion c) => into(foods).insert(c);

  Future<int> deleteFood(int id) => (delete(foods)..where((f) => f.id.equals(id))).go();

  Future<void> touchFood(int id) async {
    await customStatement(
      'UPDATE foods SET use_count = use_count + 1, last_used_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, id],
    );
  }

  // ---------- 训练计划 ----------
  Stream<WorkoutPlan?> watchActivePlan() =>
      (select(workoutPlans)..where((p) => p.isActive.equals(true))).watchSingleOrNull();

  Future<WorkoutPlan?> getActivePlan() async {
    final list = await (select(workoutPlans)..where((p) => p.isActive.equals(true))).get();
    return list.isEmpty ? null : list.first;
  }

  Stream<List<PlanDay>> watchPlanDays(int planId) =>
      (select(planDays)..where((d) => d.planId.equals(planId))
            ..orderBy([(d) => OrderingTerm(expression: d.weekday)]))
          .watch();

  Future<List<PlanDay>> getPlanDays(int planId) =>
      (select(planDays)..where((d) => d.planId.equals(planId))
            ..orderBy([(d) => OrderingTerm(expression: d.weekday)]))
          .get();

  Stream<List<PlanExercise>> watchExercisesOfDay(int dayId) =>
      (select(planExercises)..where((e) => e.dayId.equals(dayId))
            ..orderBy([(e) => OrderingTerm(expression: e.orderIdx)]))
          .watch();

  Future<List<PlanExercise>> getExercisesOfDay(int dayId) =>
      (select(planExercises)..where((e) => e.dayId.equals(dayId))
            ..orderBy([(e) => OrderingTerm(expression: e.orderIdx)]))
          .get();

  Stream<List<WorkoutPlan>> watchAllPlans() =>
      (select(workoutPlans)..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).watch();

  /// 插入整份计划（含天与动作），并可选设为当前
  Future<int> insertFullPlan({
    required String name,
    required String source,
    required String note,
    required bool makeActive,
    required List<PlanDaySpec> days,
  }) async {
    return transaction(() async {
      final planId = await into(workoutPlans).insert(
        WorkoutPlansCompanion.insert(
          name: name,
          source: source,
          note: Value(note),
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          isActive: Value(makeActive),
        ),
      );
      if (makeActive) {
        await update(workoutPlans).write(const WorkoutPlansCompanion(isActive: Value(false)));
        await (update(workoutPlans)..where((p) => p.id.equals(planId)))
            .write(const WorkoutPlansCompanion(isActive: Value(true)));
      }
      for (final day in days) {
        final dayId = await into(planDays).insert(
          PlanDaysCompanion.insert(
            planId: planId,
            weekday: day.weekday,
            isRest: Value(day.isRest),
            title: Value(day.title),
            note: Value(day.note),
          ),
        );
        for (final ex in day.exercises) {
          await into(planExercises).insert(
            PlanExercisesCompanion.insert(
              dayId: dayId,
              name: ex.name,
              sets: Value(ex.sets),
              reps: Value(ex.reps),
              weightKg: Value(ex.weightKg),
              restSeconds: Value(ex.restSeconds),
              note: Value(ex.note),
              orderIdx: Value(ex.orderIdx),
            ),
          );
        }
      }
      return planId;
    });
  }

  Future<void> setActivePlan(int planId) => transaction(() async {
        // 目标不存在时保持现状（不要先把所有计划清成未激活，C4）
        final target = await (select(workoutPlans)..where((p) => p.id.equals(planId)))
            .getSingleOrNull();
        if (target == null) return;
        await update(workoutPlans).write(const WorkoutPlansCompanion(isActive: Value(false)));
        await (update(workoutPlans)..where((p) => p.id.equals(planId)))
            .write(const WorkoutPlansCompanion(isActive: Value(true)));
      });

  Future<int> deletePlan(int planId) => transaction(() async {
        final days = await (select(planDays)..where((d) => d.planId.equals(planId))).get();
        for (final d in days) {
          await (delete(planExercises)..where((e) => e.dayId.equals(d.id))).go();
        }
        await (delete(planDays)..where((d) => d.planId.equals(planId))).go();
        return (delete(workoutPlans)..where((p) => p.id.equals(planId))).go();
      });

  Future<bool> updatePlanDay(PlanDay day) => update(planDays).replace(day);

  Future<int> deletePlanDay(int dayId) => transaction(() async {
        await (delete(planExercises)..where((e) => e.dayId.equals(dayId))).go();
        return (delete(planDays)..where((d) => d.id.equals(dayId))).go();
      });

  Future<int> addExercise(PlanExercisesCompanion c) => into(planExercises).insert(c);

  Future<bool> updateExercise(PlanExercise e) => update(planExercises).replace(e);

  Future<int> deleteExercise(int id) =>
      (delete(planExercises)..where((e) => e.id.equals(id))).go();

  // ---------- 训练记录 ----------
  Future<int> insertWorkoutLog({
    required WorkoutLogsCompanion log,
    required List<ExerciseLogsCompanion> exercises,
  }) async {
    return transaction(() async {
      final logId = await into(workoutLogs).insert(log);
      for (final ex in exercises) {
        await into(exerciseLogs).insert(ex.copyWith(workoutLogId: Value(logId)));
      }
      return logId;
    });
  }

  Stream<List<WorkoutLog>> watchWorkoutLogs({int limit = 60}) =>
      (select(workoutLogs)..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
            ..limit(limit))
          .watch();

  Stream<List<ExerciseLog>> watchExercisesOfLog(int workoutLogId) =>
      (select(exerciseLogs)..where((e) => e.workoutLogId.equals(workoutLogId))
            ..orderBy([(e) => OrderingTerm(expression: e.orderIdx)]))
          .watch();

  Future<List<ExerciseLog>> getExercisesOfLog(int workoutLogId) =>
      (select(exerciseLogs)..where((e) => e.workoutLogId.equals(workoutLogId))
            ..orderBy([(e) => OrderingTerm(expression: e.orderIdx)]))
          .get();

  Future<int> deleteWorkoutLog(int id) => transaction(() async {
        await (delete(exerciseLogs)..where((e) => e.workoutLogId.equals(id))).go();
        return (delete(workoutLogs)..where((l) => l.id.equals(id))).go();
      });

  // ---------- 体重 ----------
  Stream<List<WeightLog>> watchWeightLogs({int limitDays = 365}) =>
      (select(weightLogs)..orderBy([(w) => OrderingTerm.desc(w.date)])
            ..limit(limitDays))
          .watch();

  Future<void> upsertWeight(String date, double kg, {String note = ''}) =>
      into(weightLogs).insert(
        WeightLogsCompanion.insert(date: date, weightKg: kg, note: Value(note)),
        onConflict: DoUpdate(
          (_) => WeightLogsCompanion.insert(date: date, weightKg: kg, note: Value(note)),
          target: [weightLogs.date],
        ),
      );

  Future<double?> latestWeight() async {
    final row = await (select(weightLogs)
          ..orderBy([(w) => OrderingTerm.desc(w.date)])
          ..limit(1))
        .getSingleOrNull();
    return row?.weightKg;
  }

  // ---------- 备份记录 ----------
  Stream<List<Backup>> watchBackups() =>
      (select(backups)..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).watch();

  Future<int> addBackup(BackupsCompanion c) => into(backups).insert(c);

  Future<List<Backup>> getBackups() => select(backups).get();

  Future<int> deleteBackupRecord(int id) =>
      (delete(backups)..where((b) => b.id.equals(id))).go();
}

/// 计划插入用的中间结构（服务层 → 数据库）
class PlanDaySpec {
  final int weekday;
  final bool isRest;
  final String title;
  final String note;
  final List<PlanExerciseSpec> exercises;

  PlanDaySpec({
    required this.weekday,
    this.isRest = false,
    this.title = '',
    this.note = '',
    List<PlanExerciseSpec>? exercises,
  }) : exercises = exercises ?? [];
}

class PlanExerciseSpec {
  final String name;
  final int sets;
  final String reps;
  final double? weightKg;
  final int restSeconds;
  final String note;
  final int orderIdx;

  PlanExerciseSpec({
    required this.name,
    this.sets = 3,
    this.reps = '8-12',
    this.weightKg,
    this.restSeconds = 90,
    this.note = '',
    this.orderIdx = 0,
  });
}
