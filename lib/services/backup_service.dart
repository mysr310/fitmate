import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// R3-高6：服务级互斥——备份与恢复（含照片 GC）串行执行。
  /// Future 链实现跨入口互斥；错误不会阻塞后续操作。
  Future<dynamic> _opLock = Future.value();

  Future<T> _withLock<T>(Future<T> Function() action) {
    final task = _opLock.then((_) => action());
    _opLock = task.then((_) {}, onError: (_) {});
    return task;
  }

  /// R3-中8：每天首次启动自动做一份本地滚动备份（文档承诺的兜底）。
  /// 整个方法包在 try/catch 里，失败静默（明天再试）。
  Future<void> maybeAutoBackup() async {
    await _withLock(() async {
      try {
        final now = DateTime.now();
        final todayStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final last = await db.getSetting('last_auto_backup_date');
        if (last == todayStr) return;
        await _createBackupInner(auto: true);
        await db.setSetting('last_auto_backup_date', todayStr);
      } catch (_) {}
    });
  }

  /// R4-N7：应用启动时清理历史崩溃残留的暂存目录
  Future<void> cleanupStaging() async {
    try {
      _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
      final staging = Directory(p.join(_docs.path, 'food_photos_staging'));
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    } catch (_) {
      // path_provider 在 Web 冒烟环境会抛 MissingPluginException，静默即可
    }
  }

  Future<Directory> get backupDir async {
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> createBackup({required bool auto}) =>
      _withLock(() => _createBackupInner(auto: auto));

  Future<File> _createBackupInner({required bool auto}) async {
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

    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('data.json', Uint8List.fromList(jsonBytes)));

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

    await db.addBackup(BackupsCompanion.insert(
      path: file.path,
      sizeBytes: Value(await file.length()),
      kind: Value(auto ? 'auto' : 'manual'),
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    ));

    if (auto) await _rollAutoBackups(dir);
    return file;
  }

  /// C3：删除 food_photos 下不再被任何饮食记录引用的照片。
  /// R4-N10：最近 1 小时内新写入的文件跳过，避免与照片保存产生窄竞态。
  Future<void> _gcPhotos() async {
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(_docs.path, 'food_photos'));
    if (!await photoDir.exists()) return;
    final rows = await db.select(db.foodEntries).get();
    final referenced = {for (final r in rows) if (r.photoPath.isNotEmpty) p.basename(r.photoPath)};
    final grace = DateTime.now().subtract(const Duration(hours: 1));
    for (final f in photoDir.listSync().whereType<File>()) {
      final modified = await f.lastModified();
      if (modified.isAfter(grace)) continue;
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
        // R4-N10：只数已完成的 .fitbak，排除崩溃残留的 .tmp 半成品
        .where((f) => p.basename(f.path).startsWith(autoPrefix))
        .where((f) => p.basename(f.path).endsWith(ext))
        .toList()
      ..sort((a, b) => BackupService.compareBackupRecency(a.path, b.path));
    for (var i = keepAutoCount; i < autos.length; i++) {
      final victim = autos[i];
      try {
        await victim.delete();
        await (db.delete(db.backups)..where((b) => b.path.equals(victim.path))).go();
      } catch (_) {}
    }
  }

  /// 最新备份文件（无则 null）。
  /// 按文件名里的时间戳排序，不能按整条路径排序——
  /// "自动备份_"/"健身备份_" 前缀会把新旧顺序打乱。
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

  /// 从备份文件名解析时间戳，统一归一化为 14 位（yyyyMMddHHmmss）。
  /// 4 位时间（HHmm）补 00 秒；5 位非法返回 0；
  /// 边界防贪：后面跟更多数字时不匹配（R4-N10）。
  static int backupStamp(String fileName) {
    final m = RegExp(r'(\d{8})_(\d{4,6})(?!\d)').firstMatch(p.basename(fileName));
    if (m == null) return 0;
    final date = m.group(1)!;
    var time = m.group(2)!;
    if (time.length == 5) return 0;
    if (time.length == 4) time = '${time}00';
    return int.tryParse('$date$time') ?? 0;
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
    _validateTables(tables);
    return (payload: payload, photos: photos);
  }

  /// R3-高1：必需表集合校验——任何一张表缺失/不是 List/行不是 Map 都直接拒绝。
  /// 没有这道闸，一个损坏或伪造的备份会在"覆盖恢复"里把整个数据库清空。
  static const List<String> _requiredTables = [
    'profiles',
    'ai_configs',
    'settings',
    'workout_plans',
    'plan_days',
    'plan_exercises',
    'workout_logs',
    'exercise_logs',
    'foods',
    'food_entries',
    'weight_logs',
  ];

  void _validateTables(Map<String, dynamic> tables) {
    for (final name in _requiredTables) {
      final v = tables[name];
      if (v is! List) {
        throw Exception('备份数据损坏：表 "$name" 缺失或格式不正确');
      }
      for (final row in v) {
        if (row is! Map) {
          throw Exception('备份数据损坏：表 "$name" 中存在非对象行');
        }
      }
    }
  }

  /// 恢复。overwrite=清空后写入 / merge=合并
  Future<RestoreSummary> restore({
    required Map<String, dynamic> payload,
    required Map<String, List<int>> photos,
    required bool overwrite,
  }) =>
      _withLock(() => _restoreInner(
            payload: payload,
            photos: photos,
            overwrite: overwrite,
          ));

  Future<RestoreSummary> _restoreInner({
    required Map<String, dynamic> payload,
    required Map<String, List<int>> photos,
    required bool overwrite,
  }) async {
    final tables = payload['tables'] as Map<String, dynamic>;

    // 照片先写进暂存目录，数据库提交成功后再换入正式目录；
    // 任何失败都清理暂存并保留旧照片（R3-高6 / R4-N6）。
    _docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(_docs.path, 'food_photos'));
    final staging = Directory(p.join(_docs.path, 'food_photos_staging'));
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    if (photos.isNotEmpty) {
      await staging.create(recursive: true);
      for (final e in photos.entries) {
        final safeName = p.basename(e.key);
        if (safeName.isEmpty) continue;
        final f = File(p.join(staging.path, safeName));
        await f.writeAsBytes(e.value, flush: true);
      }
    }

    // ---------- 第一阶段：数据库事务（失败 = 一切保持原状） ----------
    final Map<String, int> counts;
    try {
      counts = await db.transaction(() async {
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

        // 档案最多恢复一条（多条会让 watchProfile 断言失败），取最新
        final profiles = _listOf(tables['profiles'])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) =>
              ((b['createdAt'] as num?) ?? 0).compareTo((a['createdAt'] as num?) ?? 0));
        if (profiles.isNotEmpty &&
            (overwrite || (await db.select(db.profiles).get()).isEmpty)) {
          final p0 = Profile.fromJson(Map<String, dynamic>.from(profiles.first));
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

        // 食物库（按名称替换/新增；备份内同名行去重，R3-低12）
        final foods = _listOf(tables['foods']);
        final seenFoodNames = <String>{};
        for (final j in foods) {
          final f = Food.fromJson(Map<String, dynamic>.from(j));
          if (!seenFoodNames.add(f.name)) continue;
          final existing = await db.findFoodByName(f.name);
          if (overwrite) {
            if (existing == null) {
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
            } else {
              // 用本地行 id 更新，避免备份 id 与本地行冲突形成同名多行
              await (db.update(db.foods)..where((x) => x.id.equals(existing.id))).write(
                FoodsCompanion(
                  name: Value(f.name),
                  kcal100: Value(f.kcal100),
                  protein100: Value(f.protein100),
                  fat100: Value(f.fat100),
                  carb100: Value(f.carb100),
                  servingGrams: Value(f.servingGrams),
                  servingDesc: Value(f.servingDesc),
                  useCount: Value(f.useCount),
                  lastUsedAt: Value(f.lastUsedAt),
                ),
              );
            }
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
                    weekday: day.weekday.clamp(1, 7),
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
                      weightKg:
                          Value(ex.weightKg != null && ex.weightKg! > 0 ? ex.weightKg : null),
                      restSeconds: Value(ex.restSeconds.clamp(0, 600)),
                      note: Value(ex.note),
                      orderIdx: Value(ex.orderIdx),
                    ),
                  );
            }
          }
        }
        counts['workout_plans'] = plans.length;

        // 饮食记录（append；日期格式非法的行跳过，R4-N10）
        final entries = _listOf(tables['food_entries']);
        var entryCount = 0;
        for (final j in entries) {
          final e = FoodEntry.fromJson(Map<String, dynamic>.from(j));
          if (!dateRe.hasMatch(e.date)) continue;
          await db.into(db.foodEntries).insert(FoodEntriesCompanion.insert(
                date: e.date,
                mealType: e.mealType.clamp(0, 3),
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
          entryCount++;
        }
        counts['food_entries'] = entryCount;

        // 训练日志（append，重生成 id；日期非法跳过，R4-N10）
        final logs = _listOf(tables['workout_logs']);
        final exLogs = _listOf(tables['exercise_logs']);
        for (final lj in logs) {
          final l = WorkoutLog.fromJson(Map<String, dynamic>.from(lj));
          if (!dateRe.hasMatch(l.date)) continue;
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
    } catch (e) {
      // DB 恢复失败：清理暂存目录，正式照片目录保持原状
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }

    // ---------- 第二阶段：照片换入（DB 已提交；采用可回滚交换，R4-N6） ----------
    try {
      if (overwrite) {
        // 覆盖恢复：旧目录改名 → 新目录换入 → 删旧；任一步失败可整体回滚
        final oldDir = Directory(p.join(_docs.path, 'food_photos_old'));
        if (await oldDir.exists()) {
          await oldDir.delete(recursive: true);
        }
        if (await photoDir.exists()) {
          await photoDir.rename(oldDir.path);
        }
        try {
          if (await staging.exists()) {
            await staging.rename(photoDir.path);
          }
          if (await oldDir.exists()) {
            await oldDir.delete(recursive: true);
          }
        } catch (_) {
          // 回滚：把旧目录换回
          if (await oldDir.exists() && !await photoDir.exists()) {
            await oldDir.rename(photoDir.path);
          }
          rethrow;
        }
      } else if (photos.isNotEmpty) {
        // N1 合并恢复：绝不清空本机照片目录，只把备份照片并入；
        // 文件名冲突时生成唯一名，本机原有照片不受影响
        if (!await photoDir.exists()) await photoDir.create(recursive: true);
        for (final e in photos.entries) {
          final safeName = p.basename(e.key);
          if (safeName.isEmpty) continue;
          final src = File(p.join(staging.path, safeName));
          var dst = File(p.join(photoDir.path, safeName));
          var attempt = 0;
          while (await dst.exists()) {
            attempt++;
            final dot = safeName.lastIndexOf('.');
            final stem = dot <= 0 ? safeName : safeName.substring(0, dot);
            dst = File(p.join(photoDir.path, '${stem}-r$attempt.jpg'));
          }
          await src.rename(dst.path);
        }
      }
      return RestoreSummary(counts: counts, photos: photos.length);
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
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
