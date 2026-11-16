import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/media/model/data/face_scan.dart';
import 'package:campus_mate/auth/media/model/repository/face_detector.dart';

/// 테스트 전용 [FaceDetector]. 기본은 항상 얼굴을 찾았고 크기는 모르는(null — 통과) 것으로 처리한다.
class FakeFaceDetector implements FaceDetector {
  /// 얼굴이 있는지.
  bool nextResult = true;

  /// 얼굴이 있을 때 가장 큰 얼굴 폭 ÷ 사진 폭. null 이면 크기를 모른다.
  double? nextWidthRatio;

  /// 지정하면 [scan] 이 이 예외를 던진다.
  /// 실제 ML Kit 은 디코드하지 못한 사진에 `PlatformException` 을 던진다.
  Exception? nextError;

  /// 한 번에 여러 장을 검사하는 04-2 용. 앞에서부터 하나씩 쓰고, 다 쓰면 [nextResult] 로 돌아간다.
  final List<bool> queuedResults = [];

  /// [queuedResults] 와 같은 방식의 얼굴 크기 줄. 다 쓰면 [nextWidthRatio] 로 돌아간다.
  final List<double?> queuedWidthRatios = [];

  /// 얼굴이 있을 때 같이 나온 사람이 있는지.
  bool nextHasCompanion = false;

  /// [queuedResults] 와 같은 방식의 같이 나온 사람 줄. 다 쓰면 [nextHasCompanion] 으로 돌아간다.
  final List<bool> queuedHasCompanion = [];

  /// 지정하면 이 [Completer] 가 끝날 때까지 검사가 멈춘다 — 검사 중 화면을 보는 테스트용. 값은 얼굴이 있는지.
  Completer<bool>? gate;

  /// 어떤 파일로 검출을 요청받았는지 — 원본이 아니라 압축본이어야 한다.
  final List<File> scanCalls = [];

  @override
  Future<FaceScan> scan(File image) async {
    scanCalls.add(image);
    final hasFace = await _hasFace();
    final ratio = queuedWidthRatios.isEmpty ? nextWidthRatio : queuedWidthRatios.removeAt(0);
    final companion = queuedHasCompanion.isEmpty ? nextHasCompanion : queuedHasCompanion.removeAt(0);
    return hasFace ? FaceScan.found(widthRatio: ratio, hasCompanion: companion) : const FaceScan.none();
  }

  Future<bool> _hasFace() async {
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
