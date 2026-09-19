import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit;

/// 학생증 사진에 얼굴이 보이는지 기기 안에서 판단한다(설계 §7.3, 서버로 보내기 전 1차 필터).
abstract interface class FaceDetector {
  Future<bool> hasFace(File image);
}

/// ML Kit 온디바이스 얼굴 검출로 [FaceDetector] 를 구현한다.
///
/// ML Kit 패키지도 `FaceDetector` 라는 이름을 쓰므로 `mlkit.` 접두사로 구분한다.
class MlKitFaceDetector implements FaceDetector {
  MlKitFaceDetector() : _detector = mlkit.FaceDetector(options: mlkit.FaceDetectorOptions());

  final mlkit.FaceDetector _detector;

  @override
  Future<bool> hasFace(File image) async {
    final faces = await _detector.processImage(mlkit.InputImage.fromFile(image));
    return faces.isNotEmpty;
  }
}
