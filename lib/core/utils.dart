import 'package:intl/intl.dart';

/// 餐次
enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeX on MealType {
  String get label => switch (this) {
        MealType.breakfast => '早餐',
        MealType.lunch => '午餐',
        MealType.dinner => '晚餐',
        MealType.snack => '加餐',
      };

  int get index0 => index;
}

MealType mealTypeFromIndex(int i) =>
    MealType.values.firstWhere((e) => e.index == i.clamp(0, 3), orElse: () => MealType.breakfast);

/// 目标类型
enum GoalType { cut, maintain, bulk }

extension GoalTypeX on GoalType {
  String get label => switch (this) {
        GoalType.cut => '减脂',
        GoalType.maintain => '保持',
        GoalType.bulk => '增肌',
      };
}

GoalType goalFrom(String? s) => GoalType.values
    .firstWhere((e) => e.name == s, orElse: () => GoalType.maintain);

/// 活动水平
enum ActivityLevel { sedentary, light, moderate, active, veryActive }

extension ActivityLevelX on ActivityLevel {
  String get label => switch (this) {
        ActivityLevel.sedentary => '久坐（很少运动）',
        ActivityLevel.light => '轻度（每周运动1-3次）',
        ActivityLevel.moderate => '中度（每周运动3-5次）',
        ActivityLevel.active => '高强度（每周运动6-7次）',
        ActivityLevel.veryActive => '极高（体力劳动/每天训练）',
      };

  double get factor => switch (this) {
        ActivityLevel.sedentary => 1.2,
        ActivityLevel.light => 1.375,
        ActivityLevel.moderate => 1.55,
        ActivityLevel.active => 1.725,
        ActivityLevel.veryActive => 1.9,
      };
}

ActivityLevel activityFrom(String? s) => ActivityLevel.values
    .firstWhere((e) => e.name == s, orElse: () => ActivityLevel.light);

/// 日期工具（内部统一用 yyyy-MM-dd 文本存储）
final DateFormat _dayFmt = DateFormat('yyyy-MM-dd');

String todayString([DateTime? now]) => _dayFmt.format(now ?? DateTime.now());

String fmtDate(DateTime d) => _dayFmt.format(d);

DateTime parseDate(String s) => DateTime.tryParse(s) ?? DateTime.now();

/// 周一=1 ... 周日=7
int weekdayOf(String date) => parseDate(date).weekday;

String weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][(weekday - 1).clamp(0, 6)];

/// 返回包含 [from]（含）之前/之后的 n 天日期文本列表（从旧到新）
List<String> lastNDays(int n, {DateTime? end}) {
  final e = (end ?? DateTime.now());
  final list = <String>[];
  for (var i = n - 1; i >= 0; i--) {
    list.add(fmtDate(e.subtract(Duration(days: i))));
  }
  return list;
}

String fmtKcal(num v) {
  if (v >= 1000) return v.toStringAsFixed(v.truncate() == v ? 0 : 1);
  return v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
}

String fmtWeight(num v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
