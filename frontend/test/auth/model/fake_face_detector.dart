import 'dart:io';

import 'package:campus_mate/auth/model/face_detector.dart';

/// 테스트 전용 [FaceDetector]. 기본은 항상 얼굴을 찾은 것으로 처리한다.
class FakeFaceDetector implements FaceDetector {
  bool nextResult = true;

  @override
  Future<bool> hasFace(File image) async => nextResult;
}
