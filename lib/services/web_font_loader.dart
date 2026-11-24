import 'web_font_loader_stub.dart'
    if (dart.library.html) 'web_font_loader_web.dart' as impl;

export 'web_font_loader_stub.dart' if (dart.library.html) 'web_font_loader_web.dart';

/// 加载 Web 端中文字体（其他平台为空实现）
Future<void> loadWebCjkFont() => impl.loadWebCjkFont();
