import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/ai/parsers.dart';

void main() {
  group('extractJson', () {
    test('直接 JSON', () {
      expect(extractJson('{"a":1}'), {'a': 1});
    });

    test('markdown 代码块包裹', () {
      final v = extractJson('```json\n{"items":[{"name":"米饭"}]}\n```');
      expect((v as Map)['items'].first['name'], '米饭');
    });

    test('前后有多余文字', () {
      final v = extractJson('好的，结果如下：\n{"kcal": 123} 请查收');
      expect((v as Map)['kcal'], 123);
    });

    test('字符串里包含括号不破坏配对', () {
      final v = extractJson('{"note":"热量(大卡) }{ 混乱"}');
      expect((v as Map)['note'], contains('混乱'));
    });

    test('顶层是数组', () {
      final v = extractJson('[{"name":"鸡蛋"}]');
      expect((v as List).length, 1);
    });

    test('非法输入抛异常', () {
      expect(() => extractJson('这里没有 JSON'), throwsFormatException);
      expect(() => extractJson('{"a": '), throwsFormatException);
    });
  });

  group('通用取值', () {
    test('千分位数字按完整数值解析', () {
      expect(asDouble('1,200 千卡'), 1200);
      expect(asDouble('-1,200'), -1200);
      expect(asDouble('约 200 克'), 200);
    });

    test('字符串本身仍支持普通数字', () {
      expect(asDouble('232'), 232);
      expect(asDouble(232), 232);
      expect(asDouble(null), isNull);
    });
  });

  group('parseFoodAi', () {
    test('标准字段', () {
      final r = parseFoodAi(
          '{"items":[{"name":"米饭","grams":200,"kcal":232,"protein_g":5.4,"fat_g":0.6,"carb_g":51.7,"confidence":0.9}],"summary":"一碗米饭"}');
      expect(r.items, hasLength(1));
      expect(r.items.first.name, '米饭');
      expect(r.items.first.grams, 200);
      expect(r.items.first.kcal, 232);
      expect(r.summary, '一碗米饭');
    });

    test('中文字段名与字符串数字也能解析', () {
      final r = parseFoodAi(
          '{"items":[{"食物":"煎蛋","克数":"两个(约120克)","热量":"180","蛋白质":"12","脂肪":"14","碳水":"2","置信度":"0.8"}]}');
      expect(r.items.first.name, '煎蛋');
      expect(r.items.first.grams, 120);
      expect(r.items.first.kcal, 180);
      expect(r.items.first.protein, 12);
    });

    test('items 直接是数组', () {
      final r = parseFoodAi('[{"name":"苹果","kcal":95}]');
      expect(r.items.first.kcal, 95);
    });

    test('置信度越界收敛', () {
      final r = parseFoodAi('{"items":[{"name":"x","kcal":1,"confidence":5}]}');
      expect(r.items.first.confidence, 1);
    });
  });

  group('parseWeeklyPlanAi', () {
    test('完整解析', () {
      final p = parseWeeklyPlanAi('''
{"plan_name":"新手增肌周计划","summary":"全身三分化",
 "days":[
  {"weekday":1,"title":"胸+三头","is_rest":false,"exercises":[{"name":"俯卧撑","sets":4,"reps":"8-12","rest_seconds":90}]},
  {"weekday":2,"is_rest":true,"exercises":[]},
  {"weekday":3,"title":"背+二头","is_rest":false,"exercises":[{"name":"引体向上","sets":4,"reps":"6-10","weight_kg":null}]},
  {"weekday":4,"is_rest":true,"exercises":[]},
  {"weekday":5,"title":"腿","is_rest":false,"exercises":[{"name":"深蹲","sets":5,"reps":"8","weight_kg":40}]},
  {"weekday":6,"title":"有氧","is_rest":false,"exercises":[{"name":"快走","sets":1,"reps":"30分钟","rest_seconds":0}]},
  {"weekday":7,"is_rest":true,"exercises":[]}
 ]}''');
      expect(p.planName, '新手增肌周计划');
      expect(p.days, hasLength(7));
      expect(p.days[0].exercises.first.name, '俯卧撑');
      expect(p.days[1].isRest, isTrue);
      expect(p.days[4].exercises.first.weightKg, 40);
    });

    test('缺失的星期自动补为休息日', () {
      final p = parseWeeklyPlanAi(
          '{"plan_name":"精简计划","days":[{"weekday":1,"title":"全身","is_rest":false,"exercises":[{"name":"深蹲","sets":3,"reps":"10"}]}]}');
      expect(p.days, hasLength(7));
      expect(p.days[0].exercises, isNotEmpty);
      for (var i = 1; i < 7; i++) {
        expect(p.days[i].isRest, isTrue);
      }
    });

    test('sets 越界收敛、reps 数字转字符串', () {
      final p = parseWeeklyPlanAi(
          '{"plan_name":"x","days":[{"weekday":1,"is_rest":false,"exercises":[{"name":"动作","sets":99,"reps":12}]}]}');
      expect(p.days[0].exercises.first.sets, 20);
      expect(p.days[0].exercises.first.reps, '12');
    });

    test('weekday 支持中文、数字字符串与英文星期', () {
      final p = parseWeeklyPlanAi('''
{"plan_name":"混合写法","days":[
 {"weekday":"周一","title":"胸"},
 {"weekday":"星期二","title":"背"},
 {"weekday":"Wed","title":"腿"},
 {"weekday":"4","title":"肩"}
]}''');
      expect(p.days[0].title, '胸');
      expect(p.days[1].title, '背');
      expect(p.days[2].title, '腿');
      expect(p.days[3].title, '肩');
    });
  });
}
