import 'package:flutter/material.dart';

import 'food_confirm_page.dart';

/// 文字描述识别页
class FoodTextPage extends StatefulWidget {
  final String? fixedDate;

  const FoodTextPage({this.fixedDate, super.key});

  @override
  State<FoodTextPage> createState() => _FoodTextPageState();
}

class _FoodTextPageState extends State<FoodTextPage> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先描述你吃了什么')));
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FoodConfirmPage.fromText(text, fixedDate: widget.fixedDate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文字描述这一餐')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '吃了什么？（分量描述越清楚，估算越准）',
                hintText: '例如：一碗米饭（约200g）、两个煎蛋、一份炒青菜、一杯无糖豆浆',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _go,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AI 估算营养'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '提示：常见分量词（碗、个、杯、份）AI 都能理解；'
              '不确定时可以粗略描述，之后在确认页手动修正。',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
