// 本地静态服务器：用于冒烟测试 build/web 产物（dart run tool/serve_web.dart [port]）
import 'dart:io';

final Map<String, String> _mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.webp': 'image/webp',
  '.db': 'application/octet-stream',
};

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8123 : 8123;
  final root = Directory('build/web');
  if (!await root.exists()) {
    stderr.writeln('先执行 flutter build web 生成 build/web');
    exit(1);
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('serving build/web at http://localhost:$port');
  await for (final req in server) {
    _handle(req, root);
  }
}

Future<void> _handle(HttpRequest req, Directory root) async {
  final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
  final file = File('${root.path}${path.replaceAll('/', Platform.pathSeparator)}');
  if (await file.exists()) {
    final ext = file.path.contains('.') ? file.path.substring(file.path.lastIndexOf('.')) : '';
    req.response.headers.set('Content-Type', _mime[ext] ?? 'application/octet-stream');
    await req.response.addStream(file.openRead());
  } else {
    // SPA 回退
    final index = File('${root.path}${Platform.pathSeparator}index.html');
    if (await index.exists()) {
      req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
      await req.response.addStream(index.openRead());
    } else {
      req.response.statusCode = 404;
    }
  }
  await req.response.close();
}
