import '../core/utils.dart';

/// 每日热量预算（Mifflin-St Jeor）
class DailyBudget {
  final double bmr;
  final double tdee;
  final double kcalTarget;
  final double proteinTarget;
  final double fatTarget;
  final double carbTarget;

  const DailyBudget({
    required this.bmr,
    required this.tdee,
    required this.kcalTarget,
    required this.proteinTarget,
    required this.fatTarget,
    required this.carbTarget,
  });

  static DailyBudget compute({
    required String sex,
    required int age,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activity,
    required GoalType goal,
    double proteinPerKg = 1.8,
  }) {
    final male = sex == 'male';
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);
    final tdee = bmr * activity.factor;
    final kcalTarget = switch (goal) {
      GoalType.cut => tdee * 0.85,
      GoalType.maintain => tdee,
      GoalType.bulk => tdee * 1.10,
    };
    // 先应用 1200 千卡保底，再据此推导脂肪/碳水目标：
    // 否则三大营养素供能之和会与展示的热量目标对不上。
    final target = kcalTarget < 1200 ? 1200.0 : kcalTarget;
    final proteinTarget = weightKg * proteinPerKg;
    final fatTarget = target * 0.25 / 9;
    final carbTarget = (target - proteinTarget * 4 - fatTarget * 9) / 4;
    return DailyBudget(
      bmr: bmr,
      tdee: tdee,
      kcalTarget: target,
      proteinTarget: proteinTarget,
      fatTarget: fatTarget,
      carbTarget: carbTarget < 0 ? 0 : carbTarget,
    );
  }
}

/// 当日摄入汇总
class IntakeTotals {
  final double kcal;
  final double protein;
  final double fat;
  final double carb;

  const IntakeTotals({
    this.kcal = 0,
    this.protein = 0,
    this.fat = 0,
    this.carb = 0,
  });

  factory IntakeTotals.fromEntries(Iterable<dynamic> entries) {
    double k = 0, p = 0, f = 0, c = 0;
    for (final e in entries) {
      k += e.kcal as num;
      p += e.proteinG as num;
      f += e.fatG as num;
      c += e.carbG as num;
    }
    return IntakeTotals(kcal: k, protein: p, fat: f, carb: c);
  }
}
