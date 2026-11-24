import 'dart:html' as html;
import 'dart:typed_data' show ByteBuffer;

import 'package:flutter/services.dart' show FontLoader;

/// Web 预览的中文字体加载（字体文件位于 web/fonts/，只进 web 构建，不进 APK）

void setDebugTitle(String s) => html.document.title = s;

Future<void> loadWebCjkFont() async {
  Future<bool> one(String file) async {
    try {
      final resp = await html.HttpRequest.request(
        'fonts/$file',
        responseType: 'arraybuffer',
      );
      final data = (resp.response as ByteBuffer).asByteData();
      await (FontLoader('AppCJK')..addFont(Future.value(data))).load();
      return true;
    } catch (e) {
      // 诊断：把失败原因写进标题（开发期可见，不影响功能）
      html.document.title = '字体加载失败: $e';
      return false;
    }
  }

  if (!await one('NotoSansSC-Regular.otf')) return;
  final bold = await one('NotoSansSC-Bold.otf');
  if (bold) html.document.title = '健身管家';
}
