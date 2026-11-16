import 'package:campus_mate/auth/media/model/data/face_scan.dart';
import 'package:flutter_test/flutter_test.dart';

/// 아바타 원본 얼굴 크기 기준(사용자 결정 2026-11-15) — 가장 큰 얼굴 폭 ÷ 사진 폭 ≥ 0.15.
void main() {
  test('기준은 0.15 이다', () {
    expect(avatarSourceMinFaceWidthRatio, 0.15);
  });

  test('0.14 는 아바타 원본으로 쓰기에 작다', () {
    expect(const FaceScan.found(widthRatio: 0.14).isTooSmallForAvatar, isTrue);
  });

  test('0.15 는 통과한다', () {
    expect(const FaceScan.found(widthRatio: 0.15).isTooSmallForAvatar, isFalse);
  });

  test('비율을 모르면 막지 않는다', () {
    expect(const FaceScan.found().isTooSmallForAvatar, isFalse);
    expect(isFaceTooSmallForAvatar(null), isFalse);
  });

  test('얼굴이 없으면 얼굴 있음이 아니다', () {
    expect(const FaceScan.none().hasFace, isFalse);
    expect(const FaceScan.found(widthRatio: 0.5).hasFace, isTrue);
  });

  // 사용자 결정 2026-11-17 — 여러 명이 나온 사진은 누가 아바타로 그려질지 모른다. 아바타 원본은 혼자 나온 사진만.
  group('같이 나온 사람', () {
    test('기준은 가장 큰 얼굴 폭의 절반이다', () {
      expect(companionFaceMinWidthShare, 0.5);
    });

    test('얼굴이 하나면 혼자다', () {
      expect(hasCompanionFace([30]), isFalse);
      expect(hasCompanionFace([]), isFalse);
    });

    test('다른 얼굴이 가장 큰 얼굴 폭의 절반이면 같이 나온 사람이다', () {
      expect(hasCompanionFace([30, 15]), isTrue);
      expect(hasCompanionFace([12, 40, 25, 30]), isTrue);
    });

    test('절반보다 작은 얼굴(뒤로 지나가는 사람)은 세지 않는다', () {
      expect(hasCompanionFace([30, 14.9]), isFalse);
      expect(hasCompanionFace([10, 30, 12]), isFalse);
    });

    test('기본은 혼자, 얼굴이 없으면 혼자가 아닌 것도 아니다', () {
      expect(const FaceScan.found().hasCompanion, isFalse);
      expect(const FaceScan.found(hasCompanion: true).hasCompanion, isTrue);
      expect(const FaceScan.none().hasCompanion, isFalse);
    });
  });
}
