import 'dart:convert';

/// 从模型返回的文本中提取第一个 JSON 对象/数组（容忍 ```json 代码块、前后缀文字）
dynamic extractJson(String raw) {
  if (raw.isEmpty) throw const FormatException('内容为空');
  // 1) 去掉 ``` 围栏
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final m = fence.firstMatch(text);
  if (m != null) text = m.group(1)!.trim();

  // 2) 直接尝试
  try {
    return jsonDecode(text);
  } catch (_) {}

  // 3) 括号配对扫描（跳过字符串内部）
  final start = _firstOf(text, ['{', '[']);
  if (start < 0) throw const FormatException('未找到 JSON');
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{' || ch == '[') {
      depth++;
    } else if (ch == '}' || ch == ']') {
      depth--;
      if (depth == 0) {
        final candidate = text.substring(start, i + 1);
        return jsonDecode(candidate);
      }
    }
  }
  throw const FormatException('JSON 不完整');
}

int _firstOf(String s, List<String> chars) {
  for (var i = 0; i < s.length; i++) {
    if (chars.contains(s[i])) return i;
  }
  return -1;
}

// ---------- 通用取值 ----------

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    // 兼容 "1,200" 这类千分位写法，否则只会取到 "1"
    final cleaned = v.replaceAllMapped(
      RegExp(r'(\d),(\d{3})(?!\d)'),
      (m) => '${m[1]}${m[2]}',
    );
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(cleaned);
    if (m != null) return double.tryParse(m.group(0)!);
  }
  return null;
}

int asInt(dynamic v, [int fallback = 0]) => asDouble(v)?.round() ?? fallback;

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v.trim();
  return v.toString();
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (['true', '1', 'yes', '是'].contains(s)) return true;
    if (['false', '0', 'no', '否'].contains(s)) return false;
  }
  return fallback;
}

// ---------- 食物识别结果 ----------

class FoodItemGuess {
  final String name;
  final double? grams;
  final double kcal;
  final double protein;
  final double fat;
  final double carb;
  final double confidence; // 0-1

  FoodItemGuess({
    required this.name,
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carb,
    required this.confidence,
  });

  factory FoodItemGuess.fromJson(Map<String, dynamic> j) {
    return FoodItemGuess(
      name: asString(j['name'] ?? j['food'] ?? j['食物'], '未知食物'),
      grams: asDouble(j['grams'] ?? j['grams_g'] ?? j['weight_g'] ?? j['克数'] ?? j['分量']),
      kcal: asDouble(j['kcal'] ?? j['calories'] ?? j['热量'] ?? j['卡路里']) ?? 0,
      protein: asDouble(j['protein_g'] ?? j['protein'] ?? j['蛋白质']) ?? 0,
      fat: asDouble(j['fat_g'] ?? j['fat'] ?? j['脂肪']) ?? 0,
      carb: asDouble(j['carb_g'] ?? j['carbs'] ?? j['carbohydrate'] ?? j['碳水']) ?? 0,
      confidence: (asDouble(j['confidence'] ?? j['置信度']) ?? 0.7).clamp(0, 1),
    );
  }
}

class FoodAiResult {
  final List<FoodItemGuess> items;
  final String summary;

  FoodAiResult({required this.items, required this.summary});

  factory FoodAiResult.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'] ?? j['foods'] ?? j['食物列表'] ?? [];
    final items = <FoodItemGuess>[];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map) {
          final g = FoodItemGuess.fromJson(Map<String, dynamic>.from(it));
          // 全 0 且无名则跳过
          if (g.name.isNotEmpty && g.name != '未知食物' || g.kcal > 0) {
            items.add(g);
          }
        }
      }
    }
    return FoodAiResult(
      items: items,
      summary: asString(j['summary'] ?? j['总结'] ?? j['说明']),
    );
  }
}

FoodAiResult parseFoodAi(String raw) {
  final json = extractJson(raw);
  if (json is Map) return FoodAiResult.fromJson(Map<String, dynamic>.from(json));
  if (json is List) {
    return FoodAiResult.fromJson({'items': json});
  }
  throw const FormatException('食物识别结果格式不正确');
}

// ---------- 周计划 ----------

class PlanExerciseAi {
  final String name;
  final int sets;
  final String reps;
  final double? weightKg;
  final int restSeconds;
  final String note;
  final int orderIdx;

  PlanExerciseAi({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.restSeconds,
    required this.note,
    required this.orderIdx,
  });

  factory PlanExerciseAi.fromJson(Map<String, dynamic> j, int idx) {
    final w = asDouble(j['weight_kg'] ?? j['weightKg'] ?? j['weight'] ?? j['重量']);
    return PlanExerciseAi(
      name: asString(j['name'] ?? j['exercise'] ?? j['动作'], '动作'),
      sets: (asDouble(j['sets'] ?? j['组数'])?.round() ?? 3).clamp(1, 20),
      reps: _repsToString(j['reps'] ?? j['reps_target'] ?? j['次数'] ?? j['时长']),
      weightKg: w != null && w <= 0 ? null : w,
      restSeconds: (asDouble(j['rest_seconds'] ?? j['rest'] ?? j['休息'])?.round() ?? 90)
          .clamp(0, 600),
      note: asString(j['note'] ?? j['备注'] ?? j['tips']),
      orderIdx: idx,
    );
  }

  static String _repsToString(dynamic v) {
    if (v == null) return '8-12';
    if (v is num) return v.round().toString();
    final s = v.toString().trim();
    return s.isEmpty ? '8-12' : s;
  }
}

/// 解析星期：容忍 1-7 数字、"周一/星期一/礼拜天"、英文缩写
int _weekdayFrom(dynamic v) {
  final n = asDouble(v)?.round();
  if (n != null) return n < 1 ? 1 : (n > 7 ? 7 : n);
  final s = asString(v).toLowerCase();
  if (s.isNotEmpty) {
    const zh = ['一', '二', '三', '四', '五', '六', '日', '天'];
    for (var i = 0; i < zh.length; i++) {
      if (s.contains('周${zh[i]}') ||
          s.contains('星期${zh[i]}') ||
          s.contains('礼拜${zh[i]}')) {
        return i == 7 ? 7 : i + 1;
      }
    }
    const en = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    for (var i = 0; i < en.length; i++) {
      if (s.startsWith(en[i])) return i + 1;
    }
  }
  return 1;
}

class PlanDayAi {
  final int weekday;
  final bool isRest;
  final String title;
  final String note;
  final List<PlanExerciseAi> exercises;

  PlanDayAi({
    required this.weekday,
    required this.isRest,
    required this.title,
    required this.note,
    required this.exercises,
  });

  factory PlanDayAi.fromJson(Map<String, dynamic> j) {
    final rawEx = j['exercises'] ?? j['actions'] ?? j['动作'] ?? [];
    final ex = <PlanExerciseAi>[];
    if (rawEx is List) {
      var idx = 0;
      for (final e in rawEx) {
        if (e is Map) ex.add(PlanExerciseAi.fromJson(Map<String, dynamic>.from(e), idx++));
      }
    }
    return PlanDayAi(
      weekday: _weekdayFrom(j['weekday'] ?? j['day'] ?? j['周几']),
      isRest: asBool(j['is_rest'] ?? j['isRest'] ?? j['休息日'], ex.isEmpty),
      title: asString(j['title'] ?? j['name'] ?? j['标题']),
      note: asString(j['note'] ?? j['备注']),
      exercises: ex,
    );
  }
}

class WeeklyPlanAi {
  final String planName;
  final List<PlanDayAi> days;
  final String summary;

  WeeklyPlanAi(this.planName, this.days, this.summary);

  factory WeeklyPlanAi.fromJson(Map<String, dynamic> j) {
    final rawDays = j['days'] ?? j['schedule'] ?? j['计划'] ?? [];
    final days = <PlanDayAi>[];
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is Map) days.add(PlanDayAi.fromJson(Map<String, dynamic>.from(d)));
      }
    }
    // 补全缺失的星期（最多 7 天，重复的取第一个）
    final byWeekday = <int, PlanDayAi>{};
    for (final d in days) {
      byWeekday.putIfAbsent(d.weekday, () => d);
    }
    final complete = List<PlanDayAi>.generate(7, (i) {
      final wd = i + 1;
      return byWeekday[wd] ??
          PlanDayAi(weekday: wd, isRest: true, title: '休息日', note: '', exercises: []);
    });
    return WeeklyPlanAi(
      asString(j['plan_name'] ?? j['name'] ?? j['planName'], 'AI 计划'),
      complete,
      asString(j['summary'] ?? j['说明'] ?? j['notes']),
    );
  }
}

WeeklyPlanAi parseWeeklyPlanAi(String raw) {
  final json = extractJson(raw);
  if (json is Map) return WeeklyPlanAi.fromJson(Map<String, dynamic>.from(json));
  throw const FormatException('周计划格式不正确');
}
