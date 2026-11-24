import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai/ai_client.dart';
import 'data/db/database.dart';
import 'services/backup_service.dart';
import 'services/calorie_budget.dart';
import 'services/photo_store.dart';
import 'core/utils.dart';

/// 全局数据库
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------- 身体档案 ----------

final profileProvider = StreamProvider<Profile?>(
  (ref) => ref.watch(databaseProvider).watchProfile(),
);

/// 热量预算（依赖档案 + 最新体重；体重记录变化时自动重算）
final budgetProvider = FutureProvider<DailyBudget?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  // watch 体重流：每次记录/覆盖体重后预算随之刷新（B5）
  final logs = await ref.watch(weightLogsProvider.future);
  final latest = logs.isEmpty ? null : logs.first.weightKg;
  return DailyBudget.compute(
    sex: profile.sex,
    age: profile.age,
    heightCm: profile.heightCm,
    weightKg: latest ?? profile.weightKg,
    activity: activityFrom(profile.activityLevel),
    goal: goalFrom(profile.goal),
    proteinPerKg: profile.proteinPerKg,
  );
});

// ---------- 设置 ----------

final settingsMapProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.settings).watch().map(
        (rows) => {for (final r in rows) r.key: r.value},
      );
});

class SettingsController {
  SettingsController(this._db);
  final AppDatabase _db;

  Future<void> set(String key, String value) => _db.setSetting(key, value);
  Future<void> setInt(String key, int value) => _db.setSettingInt(key, value);
}

final settingsControllerProvider =
    Provider<SettingsController>((ref) => SettingsController(ref.watch(databaseProvider)));

// ---------- AI 槽位 ----------

class AiSlotService {
  AiSlotService(this.configs, this.settings);

  final List<AiConfig> configs;
  final Map<String, String> settings;

  static const slotVision = 'vision';
  static const slotPlan = 'plan';

  AiEndpoint? endpointFor(String slot) {
    final id = int.tryParse(settings['slot_${slot}_profile_id'] ?? '');
    if (id == null) return null;
    for (final c in configs) {
      if (c.id == id) {
        return AiEndpoint(name: c.name, baseUrl: c.baseUrl, apiKey: c.apiKey);
      }
    }
    return null;
  }

  String? modelFor(String slot) {
    final m = settings['slot_${slot}_model'];
    return (m == null || m.isEmpty) ? null : m;
  }

  /// 槽位是否配置完整（接口存在、Key 非空、模型名非空）
  /// Key 为空时视为未配置——恢复备份后 Key 被剥离，必须提示用户重新填写（B6）
  bool readyFor(String slot) {
    final endpoint = endpointFor(slot);
    if (endpoint == null) return false;
    if (endpoint.apiKey.trim().isEmpty) return false;
    return modelFor(slot) != null;
  }

  bool get anyReady => readyFor(slotVision) || readyFor(slotPlan);
}

/// 删除 AI 接口档案时，清理引用它的模型槽位设置（B7）
Future<void> clearSlotReferencesFor(AppDatabase db, int configId) async {
  for (final slot in const [AiSlotService.slotVision, AiSlotService.slotPlan]) {
    final key = 'slot_${slot}_profile_id';
    final raw = await db.getSetting(key);
    if (raw != null && int.tryParse(raw) == configId) {
      await db.setSetting(key, '');
      await db.setSetting('slot_${slot}_model', '');
    }
  }
}

final aiSlotServiceProvider = Provider<AiSlotService>((ref) {
  final configs = ref.watch(aiConfigsProvider).value ?? const [];
  final settings = ref.watch(settingsMapProvider).value ?? const {};
  return AiSlotService(List.of(configs), Map.of(settings));
});

final aiConfigsProvider = StreamProvider<List<AiConfig>>(
  (ref) => ref.watch(databaseProvider).watchAiConfigs(),
);

// ---------- 日期 ----------

/// 主导航页索引（供跨页跳转）
class RootTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void go(int i) => state = i.clamp(0, 4);
}

final rootTabProvider = NotifierProvider<RootTabNotifier, int>(() => RootTabNotifier());

class SelectedDateNotifier extends Notifier<String> {
  @override
  String build() => todayString();

  void select(String date) => state = date;
  void goToday() => state = todayString();
  void shift(int days) {
    final d = parseDate(state).add(Duration(days: days));
    state = fmtDate(d);
  }
}

final selectedDateProvider =
    NotifierProvider<SelectedDateNotifier, String>(() => SelectedDateNotifier());

// ---------- 饮食 ----------

final foodEntriesProvider =
    StreamProvider.family<List<FoodEntry>, String>((ref, date) {
  return ref.watch(databaseProvider).watchFoodEntries(date);
});

final intakeTotalsProvider =
    Provider.family<IntakeTotals, String>((ref, date) {
  final entries = ref.watch(foodEntriesProvider(date)).value ?? const [];
  double k = 0, p = 0, f = 0, c = 0;
  for (final e in entries) {
    k += e.kcal;
    p += e.proteinG;
    f += e.fatG;
    c += e.carbG;
  }
  return IntakeTotals(kcal: k, protein: p, fat: f, carb: c);
});

final foodLibraryProvider = StreamProvider<List<Food>>((ref) {
  return ref.watch(databaseProvider).watchFoods();
});

// 近 7 天平均摄入改为在 PlanAiService 内每次现算（B2：缓存的 family provider
// 会导致 AI 计划长期使用首次/空数据，且跨日不更新）。

// ---------- 训练计划 ----------

final activePlanProvider = StreamProvider<WorkoutPlan?>(
  (ref) => ref.watch(databaseProvider).watchActivePlan(),
);

final planDaysProvider =
    StreamProvider.family<List<PlanDay>, int>((ref, planId) {
  return ref.watch(databaseProvider).watchPlanDays(planId);
});

final exercisesOfDayProvider =
    StreamProvider.family<List<PlanExercise>, int>((ref, dayId) {
  return ref.watch(databaseProvider).watchExercisesOfDay(dayId);
});

final allPlansProvider = StreamProvider<List<WorkoutPlan>>(
  (ref) => ref.watch(databaseProvider).watchAllPlans(),
);

final workoutLogsProvider = StreamProvider<List<WorkoutLog>>(
  (ref) => ref.watch(databaseProvider).watchWorkoutLogs(),
);

final exercisesOfLogProvider =
    StreamProvider.family<List<ExerciseLog>, int>((ref, logId) {
  return ref.watch(databaseProvider).watchExercisesOfLog(logId);
});

// ---------- 体重 ----------

final weightLogsProvider = StreamProvider<List<WeightLog>>(
  (ref) => ref.watch(databaseProvider).watchWeightLogs(),
);

/// 体重趋势描述（用于 AI 上下文）
final weightTrendProvider = FutureProvider<String>((ref) async {
  final logs = await ref.watch(weightLogsProvider.future);
  if (logs.isEmpty) return '暂无体重记录';
  final sorted = logs.toList()..sort((a, b) => a.date.compareTo(b.date));
  final first = sorted.first, last = sorted.last;
  final diff = last.weightKg - first.weightKg;
  if (sorted.length == 1 || diff.abs() < 0.3) {
    return '基本稳定，当前 ${last.weightKg.toStringAsFixed(1)}kg';
  }
  return '${first.date} ${first.weightKg.toStringAsFixed(1)}kg → ${last.date} ${last.weightKg.toStringAsFixed(1)}kg，'
      '${diff > 0 ? '上升' : '下降'} ${diff.abs().toStringAsFixed(1)}kg';
});

// ---------- 备份记录 ----------

final backupsProvider = StreamProvider<List<Backup>>(
  (ref) => ref.watch(databaseProvider).watchBackups(),
);

// ---------- 照片存储 ----------

final photoStoreProvider = Provider<PhotoStore>((ref) => PhotoStore());

// ---------- 备份服务 ----------

final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));
