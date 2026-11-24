import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/core/utils.dart';
import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/providers.dart';
import 'package:fitmate/services/backup_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ProfilesCompanion profileCompanion({String name = '测试', int createdAt = 1000}) {
    return ProfilesCompanion.insert(
      name: Value(name),
      sex: 'male',
      age: 25,
      heightCm: 172,
      weightKg: 65,
      activityLevel: ActivityLevel.light.name,
      goal: GoalType.cut.name,
      onboardingDone: const Value(true),
      createdAt: createdAt,
    );
  }

  group('B1 建档并发', () {
    test('并发 saveProfile 只产生一行档案', () async {
      await Future.wait([
        db.saveProfile(profileCompanion(name: '第一次', createdAt: 1)),
        db.saveProfile(profileCompanion(name: '第二次', createdAt: 2)),
      ]);
      final rows = await db.select(db.profiles).get();
      expect(rows, hasLength(1), reason: '双击建档不能产生两行，否则 watchProfile 断言失败');
      final watched = await db.watchProfile().first;
      expect(watched, isNotNull);
    });

    test('watchProfile/getProfile 对多行历史数据取最新且不抛错', () async {
      await db.into(db.profiles).insert(profileCompanion(name: '旧', createdAt: 1));
      await db.into(db.profiles).insert(profileCompanion(name: '新', createdAt: 9999));
      final p = await db.getProfile();
      expect(p!.name, '新');
      final watched = await db.watchProfile().first;
      expect(watched!.name, '新');
    });
  });

  group('B5 预算随体重刷新', () {
    test('记录新体重后 budgetProvider 重算', () async {
      await db.saveProfile(profileCompanion());
      await db.upsertWeight('2026-11-26', 65);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(budgetProvider.future, (_, __) {});
      addTearDown(sub.close);

      final before = (await container.read(budgetProvider.future))!;
      await db.upsertWeight('2026-11-26', 55);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final after = (await container.read(budgetProvider.future))!;

      expect(after.kcalTarget, lessThan(before.kcalTarget),
          reason: '体重下降后每日预算应实时下调');
      expect(after.proteinTarget, lessThan(before.proteinTarget));
    });
  });

  group('B6/B7 AI 槽位健壮性', () {
    test('Key 为空的接口视为未配置', () {
      final emptyKey = AiConfig(
          id: 1, name: 'DS', baseUrl: 'https://api.deepseek.com', apiKey: '', createdAt: 0);
      final okKey = AiConfig(
          id: 2, name: 'DS2', baseUrl: 'https://api.deepseek.com', apiKey: 'sk-1', createdAt: 0);
      final slots = AiSlotService([emptyKey, okKey], {
        'slot_vision_profile_id': '1',
        'slot_vision_model': 'deepseek-chat',
      });
      expect(slots.readyFor(AiSlotService.slotVision), isFalse,
          reason: 'Key 被备份剥离后应显示未配置而不是让调用 401');
      final ok = AiSlotService([emptyKey, okKey], {
        'slot_vision_profile_id': '2',
        'slot_vision_model': 'deepseek-chat',
      });
      expect(ok.readyFor(AiSlotService.slotVision), isTrue);
    });

    test('clearSlotReferencesFor 清理指向被删接口的槽位', () async {
      await db.setSettingInt('slot_vision_profile_id', 7);
      await db.setSetting('slot_vision_model', 'glm-4.6v');
      await db.setSettingInt('slot_plan_profile_id', 8);
      await db.setSetting('slot_plan_model', 'deepseek-chat');

      await clearSlotReferencesFor(db, 7);

      expect(await db.getSetting('slot_vision_profile_id'), '');
      expect(await db.getSetting('slot_vision_model'), '');
      expect(await db.getSetting('slot_plan_profile_id'), '8',
          reason: '只清理被删除接口对应的槽位');
      expect(await db.getSetting('slot_plan_model'), 'deepseek-chat');
    });
  });

  group('A6 备份文件排序', () {
    test('时间戳统一归一化为 14 位，4 位与 6 位混排顺序正确', () {
      expect(BackupService.backupStamp('健身备份_20261126_143012.fitbak'), 20261126143012);
      expect(BackupService.backupStamp('健身备份_20261126_1430.fitbak'), 20261126143000);
      expect(BackupService.backupStamp('无关文件.fitbak'), 0);
      expect(BackupService.backupStamp('健身备份_20261126_14301.fitbak'), 0, reason: '5 位时间不合法');

      // 修复前：14 位的 14:00:12 会错误压过 12 位的 14:30
      final newer = '健身备份_20261126_1430.fitbak'; // 14:30
      final older = '自动备份_20261126_140012.fitbak'; // 14:00:12
      expect(BackupService.compareBackupRecency(older, newer) > 0, isTrue,
          reason: '14:30 的分钟级备份应排在 14:00:12 之前');

      final a = '自动备份_20261126_140000.fitbak';
      final b = '健身备份_20261126_140000.fitbak';
      // 同秒时按路径兜底：'健'(U+5065) < '自'(U+81EA)，b 排前即返回负值；
      // 断言具体方向而非自比较（R4-N10）
      expect(BackupService.compareBackupRecency(a, b), lessThan(0));
      expect(BackupService.compareBackupRecency(b, a), greaterThan(0));
    });
  });

  group('R3-高1 空/缺表备份拒绝', () {
    test('缺一张必需表的备份被拒绝，数据库保持原样', () async {
      await db.upsertWeight('2026-11-26', 65);
      final svc = BackupService(db, baseDir: Directory.systemTemp);
      final file = await svc.createBackup(auto: false);
      final parsed = await svc.parseBackup(await file.readAsBytes());
      final tables = Map<String, dynamic>.from(parsed.payload['tables'] as Map);
      tables.remove('foods');

      final bad = await _repackWithTables(tables);
      await expectLater(
        svc.parseBackup(bad),
        throwsException,
      );

      final weights = await db.select(db.weightLogs).get();
      expect(weights, hasLength(1));
      expect(weights.single.weightKg, 65);
    });

    test('空 tables 同样被拒绝', () async {
      final svc = BackupService(db, baseDir: Directory.systemTemp);
      final bad = await _repackWithTables(const {});
      await expectLater(svc.parseBackup(bad), throwsException);
    });
  });

  group('R3-中7 体重删除刷新流', () {
    test('删除后 watchWeightLogs 流立即反映', () async {
      await db.upsertWeight('2026-11-26', 65);
      final rows = await db.select(db.weightLogs).get();

      await (db.delete(db.weightLogs)..where((w) => w.id.equals(rows.single.id))).go();
      final logs = await db.watchWeightLogs().firstWhere((l) => l.isEmpty).timeout(
            const Duration(seconds: 5),
          );
      expect(logs, isEmpty);
    });
  });
}

Future<List<int>> _repackWithTables(Map<String, dynamic> tables) async {
  final archive = Archive();
  final jsonBytes = utf8.encode(jsonEncode({
    'app': 'fitmate',
    'version': 1,
    'created_at': 0,
    'tables': tables,
  }));
  archive.addFile(ArchiveFile.bytes('data.json', Uint8List.fromList(jsonBytes)));
  return ZipEncoder().encode(archive);
}
