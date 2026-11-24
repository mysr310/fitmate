import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_service.dart';
import 'plan_preview_page.dart';

/// AI 生成计划表单
class PlanGeneratePage extends ConsumerStatefulWidget {
  const PlanGeneratePage({super.key});

  @override
  ConsumerState<PlanGeneratePage> createState() => _PlanGeneratePageState();
}

class _PlanGeneratePageState extends ConsumerState<PlanGeneratePage> {
  String _level = '新手';
  int _days = 4;
  int _minutes = 60;
  final _equipmentCtrl = TextEditingController();
  final _prefCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _equipmentCtrl.dispose();
    _prefCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final plan = await ref.read(planAiServiceProvider).generate(PlanGenParams(
            daysPerWeek: _days,
            minutesPerSession: _minutes,
            levelLabel: _level,
            equipment: _equipmentCtrl.text.trim(),
            preference: _prefCtrl.text.trim(),
          ));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PlanPreviewPage(plan: plan)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 生成周计划')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('AI 会结合你的身体档案、近 7 天平均摄入热量和体重趋势来定制计划',
              style: TextStyle(fontSize: 13, color: scheme.outline)),
          const SizedBox(height: 20),
          const Text('训练水平', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '新手', label: Text('新手')),
              ButtonSegment(value: '有一定基础', label: Text('有基础')),
              ButtonSegment(value: '高级', label: Text('高级')),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 20),
          const Text('每周训练天数', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [2, 3, 4, 5, 6].map((d) {
              final sel = _days == d;
              return ChoiceChip(
                label: Text('$d 天'),
                selected: sel,
                onSelected: (_) => setState(() => _days = d),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text('每次训练时长', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [30, 45, 60, 90].map((m) {
              final sel = _minutes == m;
              return ChoiceChip(
                label: Text('$m 分钟'),
                selected: sel,
                onSelected: (_) => setState(() => _minutes = m),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _equipmentCtrl,
            decoration: const InputDecoration(
              labelText: '可用器材/场地',
              hintText: '如：只有哑铃和瑜伽垫 / 家附近有健身房',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _prefCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '其他要求（可选）',
              hintText: '如：想重点练腿；膝盖不好不能跑步；喜欢早上训练',
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'AI 正在制定计划…' : '生成计划'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }
}
