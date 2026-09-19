import 'dart:io';

import 'package:campus_mate/auth/model/face_detector.dart';

/// 테스트 전용 [FaceDetector]. 기본은 항상 얼굴을 찾은 것으로 처리한다.
class FakeFaceDetector implements FaceDetector {
  bool nextResult = true;

  /// 지정하면 [hasFace] 가 이 예외를 던진다.
  /// 실제 ML Kit 은 디코드하지 못한 사진에 `PlatformException` 을 던진다.
  Exception? nextError;

  /// 어떤 파일로 검출을 요청받았는지 — 원본이 아니라 압축본이어야 한다.
  final List<File> hasFaceCalls = [];

  @override
  Future<bool> hasFace(File image) async {
    hasFaceCalls.add(image);
    final error = nextError;
    if (error != null) {
      throw error;
    }
    return nextResult;
  }
}
