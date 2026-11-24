import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/core/utils.dart';
import 'package:fitmate/services/calorie_budget.dart';

void main() {
  group('DailyBudget.compute (Mifflin-St Jeor)', () {
    test('男性减脂', () {
      // BMR = 10*65 + 6.25*170 - 5*25 + 5 = 1592.5
      final b = DailyBudget.compute(
        sex: 'male',
        age: 25,
        heightCm: 170,
        weightKg: 65,
        activity: ActivityLevel.sedentary,
        goal: GoalType.cut,
      );
      expect(b.bmr, closeTo(1592.5, 0.5));
      expect(b.tdee, closeTo(1592.5 * 1.2, 0.5));
      expect(b.kcalTarget, closeTo(1592.5 * 1.2 * 0.85, 0.5));
      expect(b.proteinTarget, closeTo(65 * 1.8, 0.01));
      expect(b.proteinTarget + b.fatTarget * 9 / 4 + b.carbTarget, closeTo(b.kcalTarget / 4 * 4 / 4, 1.5),
          reason: '三大营养素供能应约等于热量目标');
    });

    test('女性保持', () {
      // BMR = 10*55 + 6.25*162 - 5*30 - 161 = 1251.5
      final b = DailyBudget.compute(
        sex: 'female',
        age: 30,
        heightCm: 162,
        weightKg: 55,
        activity: ActivityLevel.moderate,
        goal: GoalType.maintain,
      );
      expect(b.bmr, closeTo(1251.5, 0.5));
      expect(b.kcalTarget, closeTo(1251.5 * 1.55, 0.5));
    });

    test('增肌上浮 10%', () {
      final b = DailyBudget.compute(
        sex: 'male',
        age: 28,
        heightCm: 180,
        weightKg: 75,
        activity: ActivityLevel.active,
        goal: GoalType.bulk,
      );
      expect(b.kcalTarget, closeTo(b.tdee * 1.10, 0.5));
      expect(b.kcalTarget, greaterThan(b.tdee));
    });

    test('热量目标不低于 1200 保底', () {
      final b = DailyBudget.compute(
        sex: 'female',
        age: 70,
        heightCm: 150,
        weightKg: 40,
        activity: ActivityLevel.sedentary,
        goal: GoalType.cut,
      );
      expect(b.kcalTarget, greaterThanOrEqualTo(1200));
    });

    test('触发 1200 千卡保底时，三大营养素仍与热量目标自洽', () {
      final b = DailyBudget.compute(
        sex: 'female',
        age: 70,
        heightCm: 150,
        weightKg: 40,
        activity: ActivityLevel.sedentary,
        goal: GoalType.cut,
        proteinPerKg: 1.8,
      );
      expect(b.kcalTarget, 1200);
      final fromMacros = b.proteinTarget * 4 + b.fatTarget * 9 + b.carbTarget * 4;
      expect(fromMacros, closeTo(b.kcalTarget, 1),
          reason: '保底后脂肪/碳水必须按 1200 千卡重新推导，否则页面上的目标互相矛盾');
    });
  });

  group('日期工具', () {
    test('lastNDays 从旧到新且含今天', () {
      final days = lastNDays(3, end: DateTime(2026, 11, 25));
      expect(days, ['2026-11-23', '2026-11-24', '2026-11-25']);
    });

    test('weekdayName', () {
      expect(weekdayName(1), '周一');
      expect(weekdayName(7), '周日');
    });
  });
}
