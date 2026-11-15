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
}
