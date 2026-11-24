import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../providers.dart';

/// 首次使用问卷（身体档案）
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _nameCtrl = TextEditingController(text: '健身者');
  String _sex = 'male';
  int _age = 25;
  double _height = 170;
  double _weight = 65;
  ActivityLevel _activity = ActivityLevel.light;
  GoalType _goal = GoalType.cut;
  final _targetCtrl = TextEditingController();
  int _step = 0;

  @override
  void initState() {
    super.initState();
    // Web 冒烟测试后门：?autofill=1 直接用默认档案建档
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kIsWeb && Uri.base.queryParameters.containsKey('autofill')) {
        await _finish();
        return;
      }
      // R3-中9：从"重新进行初始设置"进入时，用现有档案回填表单，
      // 不让默认值悄悄覆盖用户的真实数据
      final profile = ref.read(profileProvider).value;
      if (profile != null && mounted) {
        setState(() {
          _nameCtrl.text = profile.name;
          _sex = profile.sex;
          _age = profile.age;
          _height = profile.heightCm;
          _activity = activityFrom(profile.activityLevel);
          _goal = goalFrom(profile.goal);
          if (profile.targetWeightKg != null) _targetCtrl.text = fmtWeight(profile.targetWeightKg!);
        });
        // 体重用最新一次记录（档案里的 weightKg 是建档冗余值）
        final db = ref.read(databaseProvider);
        final latest = await db.latestWeight();
        if (latest != null && mounted) {
          setState(() => _weight = latest);
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return; // 防双击：并发建档会产生多行档案导致 App 加载失败（B1）
    _finishing = true;
    try {
      final db = ref.read(databaseProvider);
      final target = double.tryParse(_targetCtrl.text.trim());
      await db.saveProfile(ProfilesCompanion.insert(
        name: Value(_nameCtrl.text.trim().isEmpty ? '健身者' : _nameCtrl.text.trim()),
        sex: _sex,
        age: _age,
        heightCm: _height,
        weightKg: _weight,
        activityLevel: _activity.name,
        goal: _goal.name,
        targetWeightKg: Value(target),
        onboardingDone: const Value(true),
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));
      // R3-中9：今天已有体重记录时不再用表单值覆盖（保护真实称重数据）
      final existing = await db.getWeightOn(todayString());
      if (existing == null) {
        await db.upsertWeight(todayString(), _weight, note: '初始体重');
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context); // 重新初始化场景：保存后返回
      }
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_step == 0 ? '欢迎使用' : '身体档案')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () async {
          if (_step < 2) {
            setState(() => _step++);
          } else {
            await _finish();
          }
        },
        onStepCancel: () => setState(() => _step = (_step - 1).clamp(0, 2)),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: _finishing ? null : details.onStepContinue,
                child: Text(_step == 2 ? '开始使用' : '下一步'),
              ),
              if (_step > 0) const SizedBox(width: 12),
              if (_step > 0)
                TextButton(onPressed: details.onStepCancel, child: const Text('上一步')),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('基本信息'),
            isActive: _step >= 0,
            content: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: '昵称'),
                ),
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
                _NumField(
                  label: '年龄（岁）',
                  initial: _age,
                  min: 10,
                  max: 100,
                  onChanged: (v) => _age = v.round(),
                ),
                const SizedBox(height: 12),
                _NumField(
                  label: '身高（cm）',
                  initial: _height,
                  min: 120,
                  max: 230,
                  onChanged: (v) => _height = v.toDouble(),
                ),
                const SizedBox(height: 12),
                _NumField(
                  label: '当前体重（kg）',
                  initial: _weight,
                  min: 30,
                  max: 200,
                  decimal: true,
                  onChanged: (v) => _weight = v.toDouble(),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('运动与目标'),
            isActive: _step >= 1,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('日常活动水平'),
                const SizedBox(height: 8),
                ...ActivityLevel.values.map(
                  (a) => RadioListTile<ActivityLevel>(
                    title: Text(a.label),
                    value: a,
                    groupValue: _activity,
                    onChanged: (v) => setState(() => _activity = v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const Divider(height: 24),
                const Text('健身目标'),
                const SizedBox(height: 8),
                SegmentedButton<GoalType>(
                  segments: GoalType.values
                      .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                      .toList(),
                  selected: {_goal},
                  onSelectionChanged: (s) => setState(() => _goal = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _goal == GoalType.cut ? '目标体重（kg，可选）' : '目标体重（kg，可选）',
                    hintText: '不填则不追踪目标体重',
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('就绪'),
            isActive: _step >= 2,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('完成后你将获得：'),
                const SizedBox(height: 8),
                const ListTile(
                  leading: Icon(Icons.local_fire_department, color: Colors.deepOrange),
                  title: Text('每日热量与营养预算'),
                  subtitle: Text('拍照识别食物即可自动记账'),
                ),
                const ListTile(
                  leading: Icon(Icons.fitness_center, color: Colors.green),
                  title: Text('AI 一周训练计划'),
                  subtitle: Text('根据你的身体数据与近期状态生成'),
                ),
                const ListTile(
                  leading: Icon(Icons.backup, color: Colors.blue),
                  title: Text('电脑备份互通'),
                  subtitle: Text('微信传文件即可备份/恢复全部数据'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatefulWidget {
  final String label;
  final num initial;
  final num min;
  final num max;
  final bool decimal;
  final void Function(num) onChanged;

  const _NumField({
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimal = false,
  });

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial.toString());

  @override
  void didUpdateWidget(covariant _NumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // R4-N4：档案回填后同步显示值；用户已在输入框手动改过则不打扰
    if (widget.initial.toString() != oldWidget.initial.toString() &&
        _ctrl.text != widget.initial.toString()) {
      _ctrl.text = widget.initial.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String s) {
    final v = double.tryParse(s);
    if (v == null) return;
    final clamped = v.clamp(widget.min.toDouble(), widget.max.toDouble()).toDouble();
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: _changed,
          ),
        ),
        SizedBox(
          width: 100,
          child: Column(
            children: [
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () {
                    final v = (double.tryParse(_ctrl.text) ?? widget.min.toDouble()) + (widget.decimal ? 0.5 : 1);
                    final c = v.clamp(widget.min.toDouble(), widget.max.toDouble()).toDouble();
                    setState(() => _ctrl.text = widget.decimal ? c.toString() : c.round().toString());
                    widget.onChanged(c);
                  },
                  child: const Icon(Icons.add, size: 18),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () {
                    final v = (double.tryParse(_ctrl.text) ?? widget.max.toDouble()) - (widget.decimal ? 0.5 : 1);
                    final c = v.clamp(widget.min.toDouble(), widget.max.toDouble()).toDouble();
                    setState(() => _ctrl.text = widget.decimal ? c.toString() : c.round().toString());
                    widget.onChanged(c);
                  },
                  child: const Icon(Icons.remove, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
