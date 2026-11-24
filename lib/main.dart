import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils.dart';
import 'data/db/database.dart';
import 'services/web_font_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await loadWebCjkFont();
    // 冒烟测试后门：?autofill=1 直接以默认档案建档
    if (Uri.base.queryParameters.containsKey('autofill')) {
      try {
        await _bootstrapDemoProfile();
      } catch (e) {
        setDebugTitle('建档失败: $e');
      }
    }
  }
  runApp(const ProviderScope(child: FitMateApp()));
}

Future<void> _bootstrapDemoProfile() async {
  final db = AppDatabase();
  try {
    await db.saveProfile(ProfilesCompanion.insert(
      name: const Value('测试用户'),
      sex: 'male',
      age: 25,
      heightCm: 172,
      weightKg: 65,
      activityLevel: ActivityLevel.light.name,
      goal: GoalType.cut.name,
      targetWeightKg: const Value(60),
      onboardingDone: const Value(true),
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
    await db.upsertWeight(todayString(), 65);
  } finally {
    await db.close();
  }
}
