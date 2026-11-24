import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/database.dart';

/// 备份/恢复服务：.fitbak = zip(data.json + 照片)
/// 安全承诺：备份中的 AI 接口不包含 API Key（导出时置空，恢复后需重新粘贴 Key）
class BackupService {
  BackupService(this.db, {Directory? baseDir}) : _baseDirOverride = baseDir;

  final AppDatabase db;

  static const int version = 1;
  static const String manualPrefix = '健身备份_';
  static const String autoPrefix = '自动备份_';
  static const String ext = '.fitbak';
  static const int keepAutoCount = 7;

  Directory _docs = Directory.systemTemp;
  final Directory? _baseDirOverride;

  Future<Directory> get backupDir async {
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> createBackup({required bool auto}) async {
    final dir = await backupDir;
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);

    // C3：打包前回收没有饮食记录引用的照片，备份体积只随有效数据增长
    await _gcPhotos();

    // A5：所有表在同一事务里读取，保证跨表一致的快照
    final tables = await db.transaction(() async {
      return <String, List<dynamic>>{
        'profiles': await db.select(db.profiles).get(),
        'ai_configs': await db.select(db.aiConfigs).get(),
        'settings': await db.select(db.settings).get(),
        'workout_plans': await db.select(db.workoutPlans).get(),
        'plan_days': await db.select(db.planDays).get(),
        'plan_exercises': await db.select(db.planExercises).get(),
        'workout_logs': await db.select(db.workoutLogs).get(),
        'exercise_logs': await db.select(db.exerciseLogs).get(),
        'foods': await db.select(db.foods).get(),
        'food_entries': await db.select(db.foodEntries).get(),
        'weight_logs': await db.select(db.weightLogs).get(),
      };
    });
    final payload = {
      'app': 'fitmate',
      'version': version,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'tables': {
        for (final e in tables.entries)
          e.key: [
            for (final row in e.value)
              e.key == 'ai_configs' ? (row.toJson()..['apiKey'] = '') : row.toJson(),
          ],
      },
    };
    final jsonBytes = utf8.encode(const JsonEncoder.withIndent(' ').convert(payload));

    // 打包 zip
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('data.json', Uint8List.fromList(jsonBytes)));

    // 照片
    final photoDir = Directory(p.join(_docs.path, 'food_photos'));
    if (await photoDir.exists()) {
      for (final f in photoDir.listSync().whereType<File>()) {
        final bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile.bytes('food_photos/${p.basename(f.path)}', bytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);

    // A6：独占命名——同名文件已存在时追加序号重试，绝不覆盖旧备份
    var file = File(p.join(dir.path, '${auto ? autoPrefix : manualPrefix}$stamp$ext'));
    var attempt = 0;
    while (await file.exists()) {
      attempt++;
      file = File(p.join(dir.path, '${auto ? autoPrefix : manualPrefix}$stamp-$attempt$ext'));
    }

    // A5：先写临时文件再原子改名，防止分享/导入读到半成品
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(zipBytes, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);

    // 记录
    await db.addBackup(BackupsCompanion.insert(
      path: file.path,
      sizeBytes: Value(await file.length()),
      kind: Value(auto ? 'auto' : 'manual'),
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    ));

    if (auto) await _rollAutoBackups(dir);
    return file;
  }

  /// C3：删除 food_photos 下不再被任何饮食记录引用的照片
  Future<void> _gcPhotos() async {
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(_docs.path, 'food_photos'));
    if (!await photoDir.exists()) return;
    final rows = await db.select(db.foodEntries).get();
    final referenced = {for (final r in rows) if (r.photoPath.isNotEmpty) p.basename(r.photoPath)};
    for (final f in photoDir.listSync().whereType<File>()) {
      if (!referenced.contains(p.basename(f.path))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _rollAutoBackups(Directory dir) async {
    final autos = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(autoPrefix))
        .toList()
      ..sort((a, b) => BackupService.compareBackupRecency(a.path, b.path));
    for (var i = keepAutoCount; i < autos.length; i++) {
      final victim = autos[i];
      try {
        await victim.delete();
        // A6：同步清理数据库记录，避免备份历史出现幽灵条目
        await (db.delete(db.backups)..where((b) => b.path.equals(victim.path))).go();
      } catch (_) {}
    }
  }

  /// 最新备份文件（无则 null）。
  /// 文件名形如 `健身备份_20261126_1400.fitbak`：按文件名里的时间戳排序，
  /// 不能按整条路径排序——"自动备份_"/"健身备份_" 前缀会把新旧顺序打乱。
  Future<File?> latestBackup() async {
    final dir = await backupDir;
    final fit = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith(ext))
        .toList()
      ..sort((a, b) => compareBackupRecency(a.path, b.path));
    return fit.isEmpty ? null : fit.first;
  }

  /// 从备份文件名解析 `yyyyMMdd_HHmm` 时间戳（解析不到返回 0）
  static int backupStamp(String fileName) {
    final m = RegExp(r'(\d{8})_(\d{4,6})').firstMatch(p.basename(fileName));
    if (m == null) return 0;
    return int.tryParse('${m.group(1)}${m.group(2)}') ?? 0;
  }

  /// 备份新旧比较（新的排前面）；时间戳相同再按路径兜底
  static int compareBackupRecency(String pathA, String pathB) {
    final byStamp = backupStamp(pathB).compareTo(backupStamp(pathA));
    if (byStamp != 0) return byStamp;
    return pathB.compareTo(pathA);
  }

  /// 校验并解析备份
  Future<({Map<String, dynamic> payload, Map<String, List<int>> photos})> parseBackup(
      List<int> bytes) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
    } catch (_) {
      throw Exception('文件不是有效的备份包（应为 .fitbak）');
    }
    Map<String, List<int>> photos = {};
    Map<String, dynamic>? payload;
    for (final f in archive.files) {
      if (f.name == 'data.json') {
        final content = utf8.decode(f.content);
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } else if (f.name.startsWith('food_photos/')) {
        photos[f.name.substring('food_photos/'.length)] = List<int>.from(f.content);
      }
    }
    if (payload == null) throw Exception('备份包缺少数据文件');
    if (payload['app'] != 'fitmate') throw Exception('这不是健身管家的备份文件');
    if (payload['version'] != version) {
      throw Exception('备份版本不兼容（v${payload['version']}，当前 v$version）');
    }
    final tables = payload['tables'];
    if (tables is! Map<String, dynamic>) throw Exception('备份数据损坏');
    return (payload: payload, photos: photos);
  }

  /// 恢复。overwrite=清空后写入 / merge=合并
  Future<RestoreSummary> restore({
    required Map<String, dynamic> payload,
    required Map<String, List<int>> photos,
    required bool overwrite,
  }) async {
    final tables = payload['tables'] as Map<String, dynamic>;

    // A4：先写照片再提交数据库——照片写失败时数据库保持原状，
    // 不会出现"提示失败但数据已恢复"的半成功状态。
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(_docs.path, 'food_photos'));
    if (overwrite && await photoDir.exists()) {
      // 覆盖恢复时清空旧照片：旧文件已无引用，留着只会让备份体积越滚越大
      for (final f in photoDir.listSync().whereType<File>()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    if (photos.isNotEmpty) {
      if (!await photoDir.exists()) await photoDir.create(recursive: true);
      for (final e in photos.entries) {
        final safeName = p.basename(e.key);
        if (safeName.isEmpty) continue;
        final f = File(p.join(photoDir.path, safeName));
        await f.writeAsBytes(e.value, flush: true);
      }
    }

    final counts = await db.transaction(() async {
      final counts = <String, int>{};

      if (overwrite) {
        await db.delete(db.exerciseLogs).go();
        await db.delete(db.workoutLogs).go();
        await db.delete(db.planExercises).go();
        await db.delete(db.planDays).go();
        await db.delete(db.workoutPlans).go();
        await db.delete(db.foodEntries).go();
        await db.delete(db.foods).go();
        await db.delete(db.weightLogs).go();
        await db.delete(db.profiles).go();
        await db.delete(db.aiConfigs).go();
        await db.delete(db.settings).go();
      }

      // B10：档案最多恢复一条（多条会让 watchProfile 断言失败），
      // 取 createdAt 最新的一条。
      final profiles = _listOf(tables['profiles'])
          .cast<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => ((b['createdAt'] as num?) ?? 0).compareTo((a['createdAt'] as num?) ?? 0));
      if (profiles.isNotEmpty &&
          (overwrite || (await db.select(db.profiles).get()).isEmpty)) {
        final j = profiles.first;
        final p0 = Profile.fromJson(Map<String, dynamic>.from(j));
        await db.into(db.profiles).insert(p0, mode: InsertMode.insertOrReplace);
        counts['profiles'] = 1;
      }

      // AI 接口（导出时 Key 已置空）
      final ai = _listOf(tables['ai_configs']);
      for (final j in ai) {
        await db.into(db.aiConfigs).insert(
              AiConfig.fromJson(Map<String, dynamic>.from(j)),
              mode: overwrite ? InsertMode.insertOrReplace : InsertMode.insertOrIgnore,
            );
      }
      counts['ai_configs'] = ai.length;

      final settings = _listOf(tables['settings']);
      for (final j in settings) {
        final s = Setting.fromJson(Map<String, dynamic>.from(j));
        // B10：合并模式不导入模型槽位配置——备份里的接口 id 与本地可能
        // 指向不同的服务，沿用本地的槽位选择更安全
        if (!overwrite && s.key.startsWith('slot_')) continue;
        await db.into(db.settings).insert(s,
            mode: overwrite ? InsertMode.insertOrReplace : InsertMode.insertOrIgnore);
      }
      counts['settings'] = settings.length;

      // 食物库（按名称替换/新增）
      final foods = _listOf(tables['foods']);
      for (final j in foods) {
        final f = Food.fromJson(Map<String, dynamic>.from(j));
        final existing = await db.findFoodByName(f.name);
        if (overwrite) {
          await db.into(db.foods).insert(f, mode: InsertMode.insertOrReplace);
        } else if (existing == null) {
          // 合并：不能沿用备份里的主键，否则会覆盖本地同 id 的另一条食物
          await db.into(db.foods).insert(FoodsCompanion.insert(
                name: f.name,
                kcal100: f.kcal100,
                protein100: Value(f.protein100),
                fat100: Value(f.fat100),
                carb100: Value(f.carb100),
                servingGrams: Value(f.servingGrams),
                servingDesc: Value(f.servingDesc),
                useCount: Value(f.useCount),
                lastUsedAt: Value(f.lastUsedAt),
              ));
        }
      }
      counts['foods'] = foods.length;

      // 体重（按日期 upsert；日期格式非法的行直接跳过，B10）
      final dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      final weights = _listOf(tables['weight_logs']);
      var weightCount = 0;
      for (final j in weights) {
        final w = WeightLog.fromJson(Map<String, dynamic>.from(j));
        if (!dateRe.hasMatch(w.date)) continue;
        if (overwrite) {
          await db.into(db.weightLogs).insert(w, mode: InsertMode.insertOrReplace);
        } else {
          await db.upsertWeight(w.date, w.weightKg, note: w.note);
        }
        weightCount++;
      }
      counts['weight_logs'] = weightCount;

      // 计划（merge 时重生成 id，导入为未启用状态）
      final plans = _listOf(tables['workout_plans']);
      final days = _listOf(tables['plan_days']);
      final exs = _listOf(tables['plan_exercises']);
      for (final pj in plans) {
        final plan = WorkoutPlan.fromJson(Map<String, dynamic>.from(pj));
        final planDays = days.where((d) => d['planId'] == plan.id).toList();
        final newId = await db.into(db.workoutPlans).insert(
              WorkoutPlansCompanion.insert(
                name: plan.name,
                source: plan.source,
                note: Value(plan.note),
                createdAt: plan.createdAt,
                isActive: Value(overwrite ? plan.isActive : false),
              ),
            );
        for (final dj in planDays) {
          final day = PlanDay.fromJson(Map<String, dynamic>.from(dj));
          final newDayId = await db.into(db.planDays).insert(
                PlanDaysCompanion.insert(
                  planId: newId,
                  weekday: day.weekday,
                  isRest: Value(day.isRest),
                  title: Value(day.title),
                  note: Value(day.note),
                ),
              );
          for (final ej in exs.where((e) => e['dayId'] == day.id)) {
            final ex = PlanExercise.fromJson(Map<String, dynamic>.from(ej));
            // B10：动作参数钳制到合法范围，防止恢复后训练页 RangeError
            await db.into(db.planExercises).insert(
                  PlanExercisesCompanion.insert(
                    dayId: newDayId,
                    name: ex.name,
                    sets: Value(ex.sets.clamp(1, 50)),
                    reps: Value(ex.reps),
                    weightKg: Value(ex.weightKg != null && ex.weightKg! > 0 ? ex.weightKg : null),
                    restSeconds: Value(ex.restSeconds.clamp(0, 600)),
                    note: Value(ex.note),
                    orderIdx: Value(ex.orderIdx),
                  ),
                );
          }
        }
      }
      counts['workout_plans'] = plans.length;

      // 饮食记录（append）
      final entries = _listOf(tables['food_entries']);
      for (final j in entries) {
        final e = FoodEntry.fromJson(Map<String, dynamic>.from(j));
        await db.into(db.foodEntries).insert(FoodEntriesCompanion.insert(
              date: e.date,
              mealType: e.mealType,
              name: e.name,
              grams: Value(e.grams),
              kcal: e.kcal,
              proteinG: Value(e.proteinG),
              fatG: Value(e.fatG),
              carbG: Value(e.carbG),
              source: e.source,
              photoPath: Value(e.photoPath),
              createdAt: e.createdAt,
            ));
      }
      counts['food_entries'] = entries.length;

      // 训练日志（append，重生成 id）
      final logs = _listOf(tables['workout_logs']);
      final exLogs = _listOf(tables['exercise_logs']);
      for (final lj in logs) {
        final l = WorkoutLog.fromJson(Map<String, dynamic>.from(lj));
        final newLogId = await db.into(db.workoutLogs).insert(
              WorkoutLogsCompanion.insert(
                date: l.date,
                dayTitle: Value(l.dayTitle),
                startedAt: l.startedAt,
                completedAt: Value(l.completedAt),
                feeling: Value(l.feeling),
                note: Value(l.note),
                planId: const Value(null),
              ),
            );
        for (final ej in exLogs.where((e) => e['workoutLogId'] == l.id)) {
          final el = ExerciseLog.fromJson(Map<String, dynamic>.from(ej));
          await db.into(db.exerciseLogs).insert(
                ExerciseLogsCompanion.insert(
                  workoutLogId: newLogId,
                  name: el.name,
                  plannedSets: Value(el.plannedSets),
                  plannedReps: Value(el.plannedReps),
                  plannedWeightKg: Value(el.plannedWeightKg),
                  doneSets: Value(el.doneSets),
                  doneReps: Value(el.doneReps),
                  doneWeightKg: Value(el.doneWeightKg),
                  done: Value(el.done),
                  note: Value(el.note),
                  orderIdx: Value(el.orderIdx),
                ),
              );
        }
      }
      counts['workout_logs'] = logs.length;

      // B10：激活计划只保留一份（多个激活会让 watchActivePlan 断言失败）
      final actives = await (db.select(db.workoutPlans)
            ..where((p) => p.isActive.equals(true))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .get();
      for (var i = 1; i < actives.length; i++) {
        await (db.update(db.workoutPlans)..where((p) => p.id.equals(actives[i].id)))
            .write(const WorkoutPlansCompanion(isActive: Value(false)));
      }
      return counts;
    });

    // 照片已在事务开始前写入（A4），这里直接返回
    return RestoreSummary(counts: counts, photos: photos.length);
  }

  List<dynamic> _listOf(dynamic v) => v is List ? v : const [];
}

class RestoreSummary {
  final Map<String, int> counts;
  final int photos;

  const RestoreSummary({required this.counts, required this.photos});

  @override
  String toString() {
    final buf = StringBuffer();
    if ((counts['food_entries'] ?? 0) > 0) buf.write('饮食 ${counts['food_entries']} 条 ');
    if ((counts['workout_plans'] ?? 0) > 0) buf.write('计划 ${counts['workout_plans']} 份 ');
    if ((counts['workout_logs'] ?? 0) > 0) buf.write('训练 ${counts['workout_logs']} 次 ');
    if ((counts['weight_logs'] ?? 0) > 0) buf.write('体重 ${counts['weight_logs']} 条 ');
    if ((counts['foods'] ?? 0) > 0) buf.write('食物库 ${counts['foods']} 项 ');
    if ((counts['ai_configs'] ?? 0) > 0) buf.write('AI接口 ${counts['ai_configs']} 个 ');
    if (photos > 0) buf.write('照片 $photos 张');
    return buf.toString().isEmpty ? '无数据' : buf.toString().trim();
  }
}

