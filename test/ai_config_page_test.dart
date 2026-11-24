import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/providers.dart';
import 'package:fitmate/ui/settings/ai_config_page.dart';

/// 记录写入而不落库，便于断言「保存模型」到底写了什么
class _RecordingSettings extends SettingsController {
  _RecordingSettings(AppDatabase db) : super(db);

  final Map<String, String> writes = {};

  @override
  Future<void> set(String key, String value) async {
    writes[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    writes[key] = value.toString();
  }
}

void main() {
  late AppDatabase db;
  late _RecordingSettings settings;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    settings = _RecordingSettings(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('在模型名称输入框修改后点「保存模型」应保存输入值', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = AiConfig(
      id: 1,
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk-test',
      createdAt: 0,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiConfigsProvider.overrideWith((ref) => Stream.value([config])),
        settingsMapProvider.overrideWith((ref) => Stream.value({
              'slot_vision_profile_id': '1',
              'slot_vision_model': 'old-model',
            })),
        settingsControllerProvider.overrideWith((ref) => settings),
      ],
      child: const MaterialApp(home: AiConfigPage()),
    ));

    final modelField = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'old-model',
    );
    for (var i = 0; i < 10 && modelField.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(modelField, findsOneWidget);

    await tester.enterText(modelField, 'deepseek-vl-2');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '保存模型').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(settings.writes['slot_vision_model'], 'deepseek-vl-2',
        reason: '保存按钮必须取输入框内容，而不是设置里尚未更新的旧模型名');

    // 结束 SnackBar 计时器，避免测试结束时残留 Timer
    await tester.pump(const Duration(seconds: 5));
  });
}
