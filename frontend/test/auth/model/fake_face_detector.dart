import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector.dart';

/// 테스트 전용 [FaceDetector]. 기본은 항상 얼굴을 찾은 것으로 처리한다.
class FakeFaceDetector implements FaceDetector {
  bool nextResult = true;

  /// 지정하면 [hasFace] 가 이 예외를 던진다.
  /// 실제 ML Kit 은 디코드하지 못한 사진에 `PlatformException` 을 던진다.
  Exception? nextError;

  /// 한 번에 여러 장을 검사하는 04-2 용. 앞에서부터 하나씩 쓰고, 다 쓰면 [nextResult] 로 돌아간다.
  final List<bool> queuedResults = [];

  /// 지정하면 이 [Completer] 가 끝날 때까지 검사가 멈춘다 — 검사 중 화면을 보는 테스트용.
  Completer<bool>? gate;

  /// 어떤 파일로 검출을 요청받았는지 — 원본이 아니라 압축본이어야 한다.
  final List<File> hasFaceCalls = [];

  @override
  Future<bool> hasFace(File image) async {
    hasFaceCalls.add(image);
    final waiting = gate;
    if (waiting != null) {
      return waiting.future;
    }
    final error = nextError;
    if (error != null) {
      throw error;
    }
    return queuedResults.isEmpty ? nextResult : queuedResults.removeAt(0);
  }
}
