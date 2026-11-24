import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../services/calorie_budget.dart';

/// 身体档案编辑
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();
  String _sex = 'male';
  ActivityLevel _activity = ActivityLevel.light;
  GoalType _goal = GoalType.cut;
  bool _loaded = false;
  bool _saving = false;

  void _fill(Profile p) {
    _nameCtrl.text = p.name;
    _ageCtrl.text = '${p.age}';
    _heightCtrl.text = fmtWeight(p.heightCm);
    _targetCtrl.text = p.targetWeightKg == null ? '' : fmtWeight(p.targetWeightKg!);
    _proteinCtrl.text = p.proteinPerKg.toStringAsFixed(1);
    _equipmentCtrl.text = p.equipmentNote;
    _sex = p.sex;
    _activity = activityFrom(p.activityLevel);
    _goal = goalFrom(p.goal);
    _loaded = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _targetCtrl.dispose();
    _proteinCtrl.dispose();
    _equipmentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await db.saveProfile(ProfilesCompanion(
        name: Value(_nameCtrl.text.trim().isEmpty ? '健身者' : _nameCtrl.text.trim()),
        sex: Value(_sex),
        age: Value(int.tryParse(_ageCtrl.text.trim()) ?? 25),
        heightCm: Value(double.tryParse(_heightCtrl.text.trim()) ?? 170),
        activityLevel: Value(_activity.name),
        goal: Value(_goal.name),
        targetWeightKg: Value(double.tryParse(_targetCtrl.text.trim())),
        proteinPerKg:
            Value(double.tryParse(_proteinCtrl.text.trim()) ?? 1.8),
        equipmentNote: Value(_equipmentCtrl.text.trim()),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (profile != null && !_loaded) {
      _fill(profile);
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('身体档案')),
      body: profile == null
          ? const Center(child: Text('尚未建档'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '昵称')),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'male', label: Text('男')),
                    ButtonSegment(value: 'female', label: Text('女')),
                  ],
                  selected: {_sex},
                  onSelectionChanged: (s) => setState(() => _sex = s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '年龄（岁）'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '身高（cm）'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '目标体重（kg，可留空）'),
                ),
                const SizedBox(height: 16),
                const Text('日常活动水平', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ...ActivityLevel.values.map(
                  (a) => RadioListTile<ActivityLevel>(
                    dense: true,
                    title: Text(a.label, style: const TextStyle(fontSize: 14)),
                    value: a,
                    groupValue: _activity,
                    onChanged: (v) => setState(() => _activity = v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const Divider(height: 24),
                const Text('健身目标', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<GoalType>(
                  segments: GoalType.values
                      .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                      .toList(),
                  selected: {_goal},
                  onSelectionChanged: (s) => setState(() => _goal = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _proteinCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '每公斤体重蛋白质目标（g/kg）',
                    helperText: '增肌建议 1.6-2.2，减脂 1.5-2.0',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _equipmentCtrl,
                  decoration: const InputDecoration(
                    labelText: '可用器材/场地',
                    helperText: '会作为 AI 生成计划的参考',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _budgetPreview(),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ],
            ),
    );
  }

  String _budgetPreview() {
    final age = int.tryParse(_ageCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    final weight = ref.watch(weightLogsProvider).value?.firstOrNull?.weightKg;
    if (age == null || h == null || weight == null) {
      return '填写后自动计算每日热量预算（体重取最新一次记录）';
    }
    final b = DailyBudget.compute(
      sex: _sex,
      age: age,
      heightCm: h,
      weightKg: weight,
      activity: _activity,
      goal: _goal,
      proteinPerKg: double.tryParse(_proteinCtrl.text.trim()) ?? 1.8,
    );
    return '按当前设置：BMR ${b.bmr.toStringAsFixed(0)} 千卡 → 每日预算 ${b.kcalTarget.toStringAsFixed(0)} 千卡，'
        '蛋白质目标 ${b.proteinTarget.toStringAsFixed(0)}g';
  }
}
