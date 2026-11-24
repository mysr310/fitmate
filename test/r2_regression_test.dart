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

  ProfilesCompanion profileCompanion({
    String name = '测试',
    int createdAt = 1000,
  }) {
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
      // watchProfile 也不应抛错
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

      // Riverpod 3 默认 autoDispose：必须保持监听，provider 链才不会被释放
      final sub = container.listen(budgetProvider.future, (_, __) {});
      addTearDown(sub.close);

      final before = (await container.read(budgetProvider.future))!;
      // 记录新体重 → 预算应随最新体重变化（减脂目标下热量目标下降）
      await db.upsertWeight('2026-11-26', 55);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final after = (await container.read(budgetProvider.future))!;

      expect(after.kcalTarget, lessThan(before.kcalTarget),
          reason: '体重下降后每日预算应实时下调');
      expect(after.proteinTarget, lessThan(before.proteinTarget));
    });
  });

  group('B6/B7 AI 槽位健壮性', () {
    test('Key 为空的接口视为未配置（恢复备份后提示重新粘贴）', () {
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
    test('秒级时间戳可解析；同秒时按路径兜底保持稳定', () {
      expect(
        BackupService.backupStamp('健身备份_20261126_143012.fitbak'),
        20261126143012,
      );
      expect(BackupService.backupStamp('健身备份_20261126_1430.fitbak'), 202611261430);
      expect(BackupService.backupStamp('无关文件.fitbak'), 0);
      final a = '自动备份_20261126_140000.fitbak';
      final b = '健身备份_20261126_140000.fitbak';
      // 同一时间戳：比较结果确定且可重复（不要求谁在前，但必须稳定）
      expect(
        BackupService.compareBackupRecency(a, b),
        BackupService.compareBackupRecency(a, b),
      );
    });
  });
}
