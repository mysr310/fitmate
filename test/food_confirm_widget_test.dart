import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/data/db/database.dart';
import 'package:fitmate/providers.dart';
import 'package:fitmate/ui/diet/food_confirm_page.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FoodConfirmPage.manual(fixedDate: '2026-11-26')),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('手动保存：写入指定日期 + 食物库按每100g入账（A3/B4）', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.widgetWithText(TextField, '食物名称'), '米饭');
    await tester.enterText(find.widgetWithText(TextField, '克数'), '100');
    await tester.enterText(find.widgetWithText(TextField, '热量(千卡)'), '116');
    await tester.enterText(find.widgetWithText(TextField, '蛋白质(g)'), '2.6');
    await tester.enterText(find.widgetWithText(TextField, '脂肪(g)'), '0.3');
    await tester.enterText(find.widgetWithText(TextField, '碳水(g)'), '25.9');
    await tester.pump();

    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();

    // B4：固定日期写入，而不是 provider 里可能过期的 selectedDate
    final entries = await db.select(db.foodEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.date, '2026-11-26');
    expect(entries.single.name, '米饭');
    expect(entries.single.kcal, 116);

    // A3：有克数时按每 100g 换算入库，useCount 从 1 起
    final foods = await db.select(db.foods).get();
    expect(foods, hasLength(1));
    expect(foods.single.kcal100, closeTo(116, 0.01));
    expect(foods.single.useCount, 1);
  });

  testWidgets('无效条目（无名称/零热量）不写入', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.widgetWithText(TextField, '热量(千卡)'), '0');
    await tester.pump();

    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();

    expect(await db.select(db.foodEntries).get(), isEmpty);
    expect(await db.select(db.foods).get(), isEmpty);
  });
}
