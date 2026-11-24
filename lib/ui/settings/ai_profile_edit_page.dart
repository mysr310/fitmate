import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../providers.dart';

/// 接口档案编辑（新增/修改）
class AiProfileEditPage extends ConsumerStatefulWidget {
  final AiConfig? existing;

  const AiProfileEditPage({this.existing, super.key});

  @override
  ConsumerState<AiProfileEditPage> createState() => _AiProfileEditPageState();
}

class _AiProfileEditPageState extends ConsumerState<AiProfileEditPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.existing?.apiKey ?? '');

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _applyPreset(String name, String baseUrl) {
    setState(() {
      _name.text = name;
      _baseUrl.text = baseUrl;
    });
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return; // R3-低11
    final name = _name.text.trim();
    final baseUrl = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final apiKey = _apiKey.text.trim();
    if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称、接口地址、API Key 都不能为空')));
      return;
    }
    _saving = true;
    if (mounted) setState(() {});
    try {
      final db = ref.read(databaseProvider);
      if (widget.existing == null) {
        await db.addAiConfig(AiConfigsCompanion.insert(
          name: name,
          baseUrl: baseUrl,
          apiKey: apiKey,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ));
      } else {
        await db.updateAiConfig(widget.existing!.copyWith(
          name: name,
          baseUrl: baseUrl,
          apiKey: apiKey,
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加接口' : '编辑接口'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('快速预设（点选自动填地址）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('DeepSeek', 'https://api.deepseek.com'),
              _presetChip('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4'),
              _presetChip('OpenAI', 'https://api.openai.com/v1'),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称（如：DeepSeek）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '接口地址（baseUrl，不带 /chat/completions）',
              helperText: '示例：https://api.deepseek.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              helperText: '只存在你手机里，不会上传，也不会随备份泄露（备份文件不含 Key）',
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：DeepSeek 的 Key 在 platform.deepseek.com 获取；'
            '智谱在 bigmodel.cn → API 密钥。任何「OpenAI 兼容」的中转服务'
            '只要填对应 baseUrl 和 Key 也能用。',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, String baseUrl) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _applyPreset(label, baseUrl),
    );
  }
}
