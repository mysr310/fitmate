import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_service.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import 'ai_profile_edit_page.dart';

/// AI 配置页：接口档案 + 模型槽位
class AiConfigPage extends ConsumerWidget {
  const AiConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(aiConfigsProvider);
    final slots = ref.watch(aiSlotServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 配置')),
      body: configsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (configs) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _Header('接口档案（任选一家或多家）'),
            if (configs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text('还没有接口，点下方「添加接口」，选个预设粘贴 API Key 即可',
                    style: TextStyle(fontSize: 13)),
              ),
            for (final c in configs)
              Card(
                child: ListTile(
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.baseUrl, style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '编辑',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AiProfileEditPage(existing: c),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除接口'),
                              content: Text('删除「${c.name}」？使用它的模型槽位将失效。'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('删除')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ref.read(databaseProvider).deleteAiConfig(c.id);
                            // B7：清理引用该接口的模型槽位，避免下拉框 value 悬空断言
                            await clearSlotReferencesFor(
                                ref.read(databaseProvider), c.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AiProfileEditPage()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('添加接口'),
              ),
            ),
            const SizedBox(height: 8),
            const _Header('模型槽位'),
            _SlotCard(
              slotKey: AiSlotService.slotVision,
              title: '拍照识别食物',
              desc: '需要一个支持图片输入的视觉模型',
              configs: configs,
              slots: slots,
              modelHint: const {
                'DeepSeek': 'deepseek-chat-vision（或官网当前视觉模型名）',
                '智谱 GLM': 'glm-4.6v / glm-4.5v',
                'OpenAI': 'gpt-4o / gpt-4o-mini',
              },
            ),
            _SlotCard(
              slotKey: AiSlotService.slotPlan,
              title: '生成训练计划',
              desc: '普通文本模型即可',
              configs: configs,
              slots: slots,
              modelHint: const {
                'DeepSeek': 'deepseek-chat',
                '智谱 GLM': 'glm-4.6 / glm-4.5',
                'OpenAI': 'gpt-4o / gpt-4o-mini',
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _SlotCard extends ConsumerStatefulWidget {
  final String slotKey;
  final String title;
  final String desc;
  final List<AiConfig> configs;
  final AiSlotService slots;
  final Map<String, String> modelHint;

  const _SlotCard({
    required this.slotKey,
    required this.title,
    required this.desc,
    required this.configs,
    required this.slots,
    required this.modelHint,
  });

  @override
  ConsumerState<_SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends ConsumerState<_SlotCard> {
  bool _testing = false;
  String? _testResult;
  late final TextEditingController _modelCtrl;
  late String _syncedModel;

  int? get _profileId =>
      int.tryParse(widget.slots.settings['slot_${widget.slotKey}_profile_id'] ?? '');

  String get _storedModel => widget.slots.settings['slot_${widget.slotKey}_model'] ?? '';

  @override
  void initState() {
    super.initState();
    _syncedModel = _storedModel;
    _modelCtrl = TextEditingController(text: _syncedModel);
  }

  @override
  void didUpdateWidget(covariant _SlotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stored = _storedModel;
    if (stored == _syncedModel) return;
    if (_modelCtrl.text.trim() == stored) {
      _syncedModel = stored; // 自己刚保存成功，无需改动输入框
    } else if (_modelCtrl.text.trim() == _syncedModel) {
      _syncedModel = stored; // 用户未编辑时跟随设置（异步加载/其它页面修改）
      _modelCtrl.text = stored;
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = widget.slots.readyFor(widget.slotKey);
    final hints = widget.modelHint.entries
        .map((e) => '${e.key}：${e.value}')
        .join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ready
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ready ? '已配置' : '未配置',
                    style: TextStyle(
                        fontSize: 11,
                        color: ready ? scheme.onPrimaryContainer : scheme.outline),
                  ),
                ),
              ],
            ),
            Text(widget.desc, style: TextStyle(fontSize: 12, color: scheme.outline)),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              // B7：value 必须仍存在于 items，否则 Dropdown 断言崩溃
              value: widget.configs.any((c) => c.id == _profileId) ? _profileId : null,
              decoration: const InputDecoration(labelText: '使用哪个接口', isDense: true),
              items: [
                for (final c in widget.configs)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) async {
                await ref.read(settingsControllerProvider).setInt(
                      'slot_${widget.slotKey}_profile_id',
                      v ?? 0,
                    );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtrl,
              decoration: InputDecoration(
                labelText: '模型名称',
                isDense: true,
                helperText: hints,
                helperMaxLines: 3,
              ),
              onSubmitted: (v) async {
                await ref
                    .read(settingsControllerProvider)
                    .set('slot_${widget.slotKey}_model', v.trim());
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    // 用输入框里的内容保存，而不是设置里尚未更新的旧值
                    final model = _modelCtrl.text.trim();
                    await ref
                        .read(settingsControllerProvider)
                        .set('slot_${widget.slotKey}_model', model);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已保存')));
                  },
                  child: const Text('保存模型'),
                ),
              ],
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                      fontSize: 12,
                      color: _testResult!.startsWith('✓')
                          ? Colors.green
                          : Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _test() async {
    final endpoint = widget.slots.endpointFor(widget.slotKey);
    final model = _modelCtrl.text.trim();
    if (endpoint == null) {
      setState(() => _testResult = '✗ 请先选择接口');
      return;
    }
    if (model.isEmpty) {
      setState(() => _testResult = '✗ 请填写模型名称');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final client = ref.read(aiClientProvider);
      final reply = await client.ping(endpoint, model);
      if (!mounted) return; // 请求期间页面可能已被关闭
      setState(() => _testResult = '✓ 连接成功，模型回复：${reply.length > 40 ? reply.substring(0, 40) : reply}');
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '✗ ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '✗ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}
