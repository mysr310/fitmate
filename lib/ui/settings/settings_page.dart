import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../providers.dart';
import '../onboarding/onboarding_page.dart';
import 'ai_config_page.dart';
import 'backup_page.dart';
import 'profile_edit_page.dart';

/// 我的页
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final slots = ref.watch(aiSlotServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 身体档案卡
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileEditPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        (profile?.name.isNotEmpty == true ? profile!.name : '我')
                            .characters
                            .first,
                        style: TextStyle(
                            fontSize: 22,
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?.name ?? '未设置',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            profile == null
                                ? '点击完善身体档案'
                                : [
                                    '${profile.sex == 'male' ? '男' : '女'} ${profile.age}岁',
                                    '${fmtWeight(profile.heightCm)}cm',
                                    '目标：${goalFrom(profile.goal).label}',
                                    activityFrom(profile.activityLevel).label.split('（').first,
                                  ].join(' · '),
                            style: TextStyle(fontSize: 12, color: scheme.outline),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _SectionTitle('设置'),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI 配置'),
            subtitle: Text(
              slots.anyReady ? '已配置 · 食物识别${slots.readyFor(AiSlotService.slotVision) ? '✓' : '✗'} 计划生成${slots.readyFor(AiSlotService.slotPlan) ? '✓' : '✗'}' : '未配置，点此设置接口与模型',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiConfigPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与电脑联动'),
            subtitle: const Text('微信一键备份到电脑 / 恢复 / 局域网传输', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupPage()),
            ),
          ),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _SectionTitle('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('使用说明'),
            subtitle: const Text('如何获得 API Key、导入计划等', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHelp(context),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('重新进行初始设置'),
            subtitle: const Text('修改基本信息也可在上方档案卡进入', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OnboardingPage()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('健身管家 v1.0 · 数据仅存本机，可通过备份迁移',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('如何获得 API Key', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              SizedBox(height: 6),
              Text('1. DeepSeek：打开 platform.deepseek.com → 注册 → API Keys → 创建并复制\n'
                  '2. 智谱 GLM：打开 bigmodel.cn → 注册 → API 密钥 → 复制\n'
                  '两者都有免费/赠送额度，复制后粘贴到「AI 配置」对应接口即可。\n\n'
                  '食物拍照识别建议用视觉模型（如 deepseek 的 vision 模型或 glm-4.6v）。\n'
                  '生成计划用文本模型（如 deepseek-chat 或 glm-4.6）。\n\n'),
              Text('数据与备份', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              SizedBox(height: 6),
              Text('所有数据保存在手机本地。「备份与电脑联动」可以把全部数据打包发送到电脑微信，'
                  '换手机时把备份文件发回手机，点开即可恢复。\n\n'),
              Text('使用建议', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              SizedBox(height: 6),
              Text('· 每天用「拍照识别」记录三餐，AI 会自动学习你的常吃食物\n'
                  '· 每周至少称一次体重，AI 生成计划时会参考趋势\n'
                  '· 训练时点「开始训练」逐组打卡，历史一目了然'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
