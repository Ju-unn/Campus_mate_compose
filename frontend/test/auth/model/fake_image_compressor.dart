import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';

/// 테스트 전용 [ImageCompressor]. 기본은 입력 파일을 그대로 돌려준다.
class FakeImageCompressor implements ImageCompressor {
  File? nextResult;

  /// 지정하면 [compressToJpeg] 가 이 예외를 던진다 — 실제 플러그인은 읽지 못하는 사진에 `PlatformException` 을 던진다.
  Exception? nextError;

  /// 지정하면 그 번째(1부터) [compressToJpeg] 호출에서만 실패한다 — 여러 장 중 하나만 못 읽는 경우.
  int? failOnCall;

  /// 어떤 파일을 압축하라고 받았는지 — 사용자가 고른 원본이어야 한다.
  final List<File> compressedSources = [];

  /// 다 썼다고 지우라고 받은 파일 경로.
  final List<String> discardedPaths = [];

  @override
  Future<File> compressToJpeg(File source) async {
    compressedSources.add(source);
    if (failOnCall == compressedSources.length) {
      throw Exception('unreadable');
    }
    final error = nextError;
    if (error != null) {
      throw error;
    }
    return nextResult ?? source;
  }

  // 시험 파일을 지우지 않는다 — 받은 경로만 남긴다.
  @override
  Future<void> discard(File compressed) async => discardedPaths.add(compressed.path);

  @override
  Future<void> discardAll() async {}
}
