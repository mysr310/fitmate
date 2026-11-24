import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 食物照片本地存储（库目录下按相对路径管理，便于打包备份）
class PhotoStore {
  PhotoStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  Future<Directory> _photosDir() async {
    final docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'food_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 保存照片，返回相对文件名（备份 zip 中使用相对路径）
  Future<String> save(Uint8List bytes) async {
    final dir = await _photosDir();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return 'food_photos/$name';
  }

  /// 相对路径 → 绝对路径（不存在则返回 null）
  Future<String?> resolve(String relPath) async {
    if (relPath.isEmpty) return null;
    final docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, relPath));
    return await f.exists() ? f.path : null;
  }

  /// 删除一张已保存的照片（事务回滚时清理用；文件不存在视为成功）
  Future<void> delete(String relPath) async {
    if (relPath.isEmpty) return;
    final docs = _baseDirOverride ?? await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, relPath));
    if (await f.exists()) await f.delete();
  }

  /// 列出所有照片相对路径
  Future<List<String>> listAll() async {
    final dir = await _photosDir();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => 'food_photos/${p.basename(f.path)}')
        .toList();
  }
}
