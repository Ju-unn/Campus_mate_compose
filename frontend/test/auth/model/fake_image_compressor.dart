import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';

/// 테스트 전용 [ImageCompressor]. 기본은 입력 파일을 그대로 돌려준다.
class FakeImageCompressor implements ImageCompressor {
  File? nextResult;

  @override
  Future<File> compressToJpeg(File source) async => nextResult ?? source;
}
