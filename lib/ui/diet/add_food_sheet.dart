import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'food_confirm_page.dart';
import 'food_text_page.dart';

/// 添加饮食的入口面板
/// [fixedDate] 非空时（如从"今日"页进入），记账日期固定为该日，忽略饮食页选中日期
Future<void> showAddFoodSheet(BuildContext context, {String? fixedDate}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('记录这一餐', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('拍照识别'),
            subtitle: const Text('AI 识别食物并估算热量'),
            onTap: () async {
              Navigator.pop(ctx);
              final picker = ImagePicker();
              try {
                final x = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1600,
                  imageQuality: 85,
                );
                if (x != null && context.mounted) {
                  final bytes = await x.readAsBytes();
                  if (!context.mounted) return; // R4-N10
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodConfirmPage.fromAi(
                        photoBytes: bytes,
                        photoPath: x.path,
                        fixedDate: fixedDate,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('拍照失败：$e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('从相册选图'),
            onTap: () async {
              Navigator.pop(ctx);
              final picker = ImagePicker();
              try {
                final x = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1600,
                  imageQuality: 85,
                );
                if (x != null && context.mounted) {
                  final bytes = await x.readAsBytes();
                  if (!context.mounted) return; // R4-N10
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodConfirmPage.fromAi(
                        photoBytes: bytes,
                        photoPath: x.path,
                        fixedDate: fixedDate,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: const Text('文字描述'),
            subtitle: const Text('如「一碗米饭 + 两个煎蛋」'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FoodTextPage(fixedDate: fixedDate),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('手动录入'),
            subtitle: const Text('自己填名称与营养'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FoodConfirmPage.manual(fixedDate: fixedDate),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
