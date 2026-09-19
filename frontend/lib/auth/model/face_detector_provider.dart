import 'package:campus_mate/auth/model/face_detector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ML Kit 검출기는 네이티브 자원을 열어두므로 앱 수명 내내 하나만 쓴다.
/// (자동 해제 provider 로 바꾸는 순간 해제 경로가 필요해진다 — [FaceDetector] 에 닫기 메서드가 없다)
final faceDetectorProvider = Provider<FaceDetector>((ref) {
  return MlKitFaceDetector();
});
