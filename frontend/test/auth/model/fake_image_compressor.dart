import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';

/// 테스트 전용 [ImageCompressor]. 기본은 입력 파일을 그대로 돌려준다.
class FakeImageCompressor implements ImageCompressor {
  File? nextResult;

  /// 어떤 파일을 압축하라고 받았는지 — 사용자가 고른 원본이어야 한다.
  final List<File> compressedSources = [];

  @override
  Future<File> compressToJpeg(File source) async {
    compressedSources.add(source);
    return nextResult ?? source;
  }
}
