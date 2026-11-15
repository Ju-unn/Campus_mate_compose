import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:campus_mate/auth/media/model/data/face_scan.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit;

/// 사진에 얼굴이 보이는지, 보이면 얼마나 큰지 기기 안에서 판단한다(프로필 사진 · 아바타 원본, 서버로 보내기 전 1차 필터).
/// 한 번의 검출로 둘 다 답한다 — 04-2 에서 잰 크기를 04-3 이 다시 검출하지 않고 쓴다.
abstract interface class FaceDetector {
  Future<FaceScan> scan(File image);
}

/// ML Kit 온디바이스 얼굴 검출로 [FaceDetector] 를 구현한다.
///
/// ML Kit 패키지도 `FaceDetector` 라는 이름을 쓰므로 `mlkit.` 접두사로 구분한다.
class MlKitFaceDetector implements FaceDetector {
  MlKitFaceDetector() : _detector = mlkit.FaceDetector(options: mlkit.FaceDetectorOptions());

  final mlkit.FaceDetector _detector;

  @override
  Future<FaceScan> scan(File image) async {
    final faces = await _detector.processImage(mlkit.InputImage.fromFile(image));
    if (faces.isEmpty) {
      return const FaceScan.none();
    }
    final largest = faces.map((face) => face.boundingBox.width).reduce(math.max);
    return FaceScan.found(widthRatio: await _ratioToImageWidth(largest, image));
  }

  /// [faceWidth] ÷ 사진 폭. 사진은 머리글만 읽고 전체를 풀지 않는다(`ImageDescriptor`). 못 읽으면 null(크기 모름 → 통과).
  /// 받는 사진은 압축본이라 EXIF 회전이 픽셀에 구워져 있고 회전 표시는 남지 않는다(`flutter_image_compress` 의
  /// `autoCorrectionAngle` 기본 true · `keepExif` 기본 false — 안드로이드 · iOS 소스 확인) — 그래서 머리글 폭이 ML Kit 상자
  /// 좌표와 같은 방향이다. 압축이 실패해 원본 JPEG 를 그대로 받아도 `ImageDescriptor` 는 EXIF 회전 표시를 반영한 세운 폭을
  /// 돌려준다(방향 6 · 저장 100×40 JPEG 가 40×100 으로 읽힘 — 2026-11-15 시험으로 확인).
  /// shortcut: 압축이 실패해 HEIC 원본을 그대로 받는 경우는 회전 방향이 맞는지 확인하지 못했다 — 잘못 막힌 사례가 보이면 여기서 본다.
  static Future<double?> _ratioToImageWidth(double faceWidth, File image) async {
    try {
      final width = await _encodedWidth(image);
      return width > 0 ? faceWidth / width : null;
    } on Exception {
      return null;
    }
  }

  static Future<int> _encodedWidth(File image) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(image.path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      descriptor.dispose();
      return width;
    } finally {
      buffer.dispose();
    }
  }
}
