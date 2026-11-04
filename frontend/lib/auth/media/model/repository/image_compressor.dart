import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// 업로드 전 사진을 압축하고 JPEG 로 다시 인코딩한다(설계 §7.4).
abstract interface class ImageCompressor {
  Future<File> compressToJpeg(File source);

  /// 다 쓴(올린) 압축본을 지운다. 압축이 원본을 그대로 돌려줬으면 원본은 건드리지 않는다.
  Future<void> discard(File compressed);

  /// 폰에 남은 압축본을 전부 지운다 — 로그아웃 · 탈퇴 때.
  Future<void> discardAll();
}

/// `flutter_image_compress` 로 [ImageCompressor] 를 구현한다.
/// [_directory] 는 압축본을 두는 곳(앱 임시 폴더)이다 — 시험은 임시 폴더를 넘긴다.
class FlutterImageCompressor implements ImageCompressor {
  FlutterImageCompressor([this._directory = getTemporaryDirectory]);

  final Future<Directory> Function() _directory;

  /// 압축본 이름 앞머리. 학생증 시절 이름 그대로 둔다 — 바꾸면 이미 폰에 남은 압축본을 [discardAll] 이 못 찾는다.
  static const _filePrefix = 'student-id-';

  @override
  Future<File> compressToJpeg(File source) async {
    final targetDir = await _directory();
    final targetPath = '${targetDir.path}/$_filePrefix${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      quality: 85,
      format: CompressFormat.jpeg,
    );
    return result == null ? source : File(result.path);
  }

  @override
  Future<void> discard(File compressed) async {
    if (_isOwn(compressed)) await _deleteQuietly(compressed);
  }

  @override
  Future<void> discardAll() async {
    final directory = await _directory();
    await for (final entity in directory.list()) {
      if (entity is File && _isOwn(entity)) await _deleteQuietly(entity);
    }
  }

  /// 이 압축기가 만든 이름인가 — 갤러리 사본 · 온보딩 임시 파일은 다른 이름이다.
  static bool _isOwn(File file) => file.uri.pathSegments.last.startsWith(_filePrefix);

  /// 이미 없거나 지우지 못해도 그만이다 — 정리 때문에 업로드 · 로그아웃이 막히지 않는다.
  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      return;
    }
  }
}
