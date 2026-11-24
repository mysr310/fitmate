import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/ai/ai_service.dart';
import 'package:fitmate/ai/parsers.dart';
import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/providers.dart';
import 'package:fitmate/ui/diet/food_confirm_page.dart';
import 'package:fitmate/ui/workout/workout_session_page.dart';

/// 让 analyze* 一直挂起，模拟 AI 请求还没返回
class _DelayedFoodAi extends FoodAiService {
  _DelayedFoodAi(Ref ref, this.completer) : super(ref);

  final Completer<FoodAiResult> completer;

  @override
  Future<FoodAiResult> analyzePhoto(Uint8List bytes, {String mime = 'image/jpeg'}) =>
      completer.future;

  @override
  Future<FoodAiResult> analyzeText(String text) => completer.future;
}

/// 让动作列表查询一直挂起，模拟数据库读取较慢
class _SlowDatabase extends AppDatabase {
  _SlowDatabase(this.gate) : super(executor: NativeDatabase.memory());

  final Completer<List<PlanExercise>> gate;

  @override
  Future<List<PlanExercise>> getExercisesOfDay(int dayId) => gate.future;
}

void main() {
  testWidgets('AI 识别返回前退出页面不应 setState 崩溃', (tester) async {
    final completer = Completer<FoodAiResult>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        foodAiServiceProvider.overrideWith((ref) => _DelayedFoodAi(ref, completer)),
      ],
      child: const MaterialApp(home: FoodConfirmPage.fromText('一碗米饭')),
    ));
    await tester.pump();

    // 模拟用户返回：整棵树被替换，FoodConfirmPage 的 State 被 dispose
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);

    completer.complete(FoodAiResult(
      items: [
        FoodItemGuess(
          name: '米饭',
          grams: 200,
          kcal: 232,
          protein: 5.4,
          fat: 0.6,
          carb: 51.7,
          confidence: 0.9,
        ),
      ],
      summary: '一碗米饭',
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'await 之后必须先判断 mounted 再 setState');
  });

  testWidgets('训练动作加载完成前退出页面不应 setState 崩溃', (tester) async {
    final gate = Completer<List<PlanExercise>>();
    final db = _SlowDatabase(gate);
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
      ],
      child: const MaterialApp(
        home: WorkoutSessionPage(planId: 1, dayId: 1, dayTitle: '胸部'),
      ),
    ));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);

    gate.complete(const <PlanExercise>[]);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '_load 的 await 之后必须先判断 mounted');
  });
}
