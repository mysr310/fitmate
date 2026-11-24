import 'dart:async' show FutureOr;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'backup_service.dart';

/// 局域网备份传输（备用通道，不依赖微信）
/// A8：一次性令牌放行（放在二维码/网址里），上传限 100MB 且文件名唯一化
class LanTransferServer {
  HttpServer? _server;
  String? _token;
  final ValueNotifier<String?> uploadedFile = ValueNotifier<String?>(null);

  static const int maxUploadBytes = 100 * 1024 * 1024; // 100MB

  int? get port => _server?.port;
  String get token => _token ?? '';
  bool get running => _server != null;

  Future<String> start({required String backupDirPath}) async {
    await stop(); // A7：重复启动先关旧服务，避免端口泄漏
    _token = _randomToken();
    final dirPath = backupDirPath;
    final t = _token!;
    final router = Router()
      // R3-高2：首页同样必须带令牌——页面里内嵌着令牌与下载入口，
      // 无令牌返回 403，避免同 Wi-Fi 设备直接绕过
      ..get('/', (Request req) => _guard(req, () => _index(req, t)))
      ..get('/backup', (Request req) => _guard(req, () => _download(req, dirPath)))
      ..post('/upload', (Request req) => _guard(req, () => _upload(req, dirPath)));

    final server = await io.serve(router, InternetAddress.anyIPv4, 0);
    _server = server;
    uploadedFile.value = null;
    return server.port.toString();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  String _randomToken() {
    final rnd = Random.secure();
    return List.generate(6, (_) => '0123456789abcdef'[rnd.nextInt(16)]).join();
  }

  bool _authorized(Request req) => req.url.queryParameters['k'] == _token;

  /// 所有读写都必须带令牌（R3-高2：首页也受保护）
  Future<Response> _guard(Request req, FutureOr<Response> Function() action) async {
    if (!_authorized(req)) return Response(403, body: '令牌无效，请从手机显示的完整网址进入');
    return action();
  }

  static Future<List<String>> localIps() async {
    final ips = <String>[];
    final interfaces = await NetworkInterface.list();
    for (final itf in interfaces) {
      for (final addr in itf.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          ips.add(addr.address);
        }
      }
    }
    return ips;
  }

  String _pageWithToken(String token) => _pageTemplate.replaceAll('__TOKEN__', token);

  static const _pageTemplate = '''
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>健身管家 · 数据传输</title>
<style>
body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;max-width:640px;margin:0 auto;padding:24px;background:#f6f7f6;color:#222}
h2{margin:8px 0 4px}
.card{background:#fff;border-radius:16px;padding:20px;margin:16px 0;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.btn{display:inline-block;background:#2e7d32;color:#fff;border:none;border-radius:10px;padding:12px 22px;font-size:15px;cursor:pointer;text-decoration:none}
.btn.gray{background:#5f6b5f}
.drop{border:2px dashed #bbb;border-radius:12px;padding:28px;text-align:center;color:#666;cursor:pointer}
.drop.hover{border-color:#2e7d32;color:#2e7d32}
input[type=file]{display:none}
#msg{margin-top:10px;font-size:13px;color:#2e7d32;min-height:18px}
small{color:#888}
</style>
</head>
<body>
<h2>健身管家 · 电脑数据传输</h2>
<div class="card">
  <h3>📥 从手机下载备份</h3>
  <p><small>把手机里的最新备份保存到这台电脑</small></p>
  <a class="btn" href="/backup?k=__TOKEN__" download>下载最新备份文件</a>
</div>
<div class="card">
  <h3>📤 上传备份到手机</h3>
  <p><small>把电脑上保存的 .fitbak 备份传回手机，App 会弹窗提示恢复</small></p>
  <div class="drop" id="drop">拖入 .fitbak 备份文件，或点击选择</div>
  <input type="file" id="file" accept=".fitbak">
  <div id="msg"></div>
</div>
<script>
const TOKEN='__TOKEN__';
const drop=document.getElementById('drop'),file=document.getElementById('file'),msg=document.getElementById('msg');
drop.onclick=()=>file.click();
drop.ondragover=e=>{e.preventDefault();drop.classList.add('hover')};
drop.ondragleave=()=>drop.classList.remove('hover');
drop.ondrop=e=>{e.preventDefault();drop.classList.remove('hover');if(e.dataTransfer.files.length)upload(e.dataTransfer.files[0])};
file.onchange=()=>{if(file.files.length)upload(file.files[0])};
async function upload(f){
  msg.textContent='上传中…';
  try{
    const buf=await f.arrayBuffer();
    const r=await fetch('/upload?k='+TOKEN+'&name='+encodeURIComponent(f.name),{method:'POST',body:buf});
    if(r.ok){msg.textContent='✅ 上传成功，请在手机上确认恢复';}
    else{msg.textContent='❌ 上传失败：'+(await r.text());}
  }catch(e){msg.textContent='❌ 上传出错：'+e;}
}
</script>
</body>
</html>
''';

  Response _index(Request req, String token) => Response.ok(_pageWithToken(token),
      headers: {'Content-Type': 'text/html; charset=utf-8'});

  Future<Response> _download(Request req, String dirPath) async {
    final dir = Directory(dirPath);
    final fit = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.fitbak'))
        .toList()
      ..sort((a, b) => BackupService.compareBackupRecency(a.path, b.path));
    if (fit.isEmpty) {
      return Response(404, body: '还没有备份文件，请先在 App 里点「立即备份」');
    }
    final f = fit.first;
    final length = await f.length();
    // A8：流式发送，不再把整个文件读进内存
    return Response.ok(
      f.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': '$length',
        'Content-Disposition':
            'attachment; filename="${Uri.encodeComponent(p.basename(f.path))}"',
      },
    );
  }

  Future<Response> _upload(Request req, String dirPath) async {
    final name = req.url.queryParameters['name'] ?? 'uploaded.fitbak';
    final safe = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!safe.endsWith('.fitbak')) {
      return Response(400, body: '只接受 .fitbak 备份文件');
    }

    // A8 + R3-低12：流式接收——先写临时文件，边收边限大小；
    // 不再把整个文件累积在内存里（低内存设备 OOM 风险）
    final tmp = File(p.join(dirPath, '$safe.tmp'));
    final sink = tmp.openWrite();
    try {
      var total = 0;
      await for (final chunk in req.read()) {
        total += chunk.length;
        if (total > maxUploadBytes) {
          await sink.close();
          await tmp.delete();
          return Response(413, body: '文件超过 100MB 上限');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (total == 0) {
        await tmp.delete();
        return Response(400, body: '内容为空');
      }
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await tmp.exists()) await tmp.delete();
      return Response(500, body: '接收失败：$e');
    }

    // 文件名唯一化，不覆盖已有的自动/手动备份
    var file = File(p.join(dirPath, safe));
    var attempt = 0;
    while (await file.exists()) {
      attempt++;
      final stem = safe.substring(0, safe.length - BackupService.ext.length);
      file = File(p.join(dirPath, '$stem-upload$attempt${BackupService.ext}'));
    }
    await tmp.rename(file.path);
    uploadedFile.value = file.path;
    return Response.ok('ok');
  }
}
