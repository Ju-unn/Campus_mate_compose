import 'dart:math' as math;

/// 아바타 원본으로 쓰려면 사진 속 가장 큰 얼굴의 상자 폭이 사진 폭의 이 비율 이상이어야 한다(사용자 결정 2026-11-15).
/// 0.15 인 이유(사용자 「얼굴폭 15퍼로 하자」): 전신 · 먼 사진(얼굴 폭 4~10%)은 막고 상반신 · 셀카는 통과시킨다.
/// 기준을 바꿀 때는 이 값 하나만 고친다.
const double avatarSourceMinFaceWidthRatio = 0.15;

/// 얼굴이 아바타 원본으로 쓰기에 작은가. 비율을 모르면(null — 검사 실패 · 이미 올려 둔 사진 · 옛 임시 저장) 막지 않는다:
/// 검출기 고장으로 가입이 막히는 쪽이 더 나쁘다(얼굴 검사 예외를 통과시키는 것과 같은 원칙).
bool isFaceTooSmallForAvatar(double? faceWidthRatio) =>
    faceWidthRatio != null && faceWidthRatio < avatarSourceMinFaceWidthRatio;

/// 다른 얼굴의 폭이 가장 큰 얼굴 폭의 이 비율 이상이면 같이 찍힌 사람으로 본다. "아바타 원본은 혼자 나온 사진만" 은 사용자 결정
/// (2026-11-17)이고, 0.5 라는 값은 대장이 정했다(사용자 확인 전) — 뒤로 작게 지나가는 사람은 세지 않으려는 값이다.
/// 여러 명이면 서버가 가장 큰 얼굴로 자르고 생성기가 한 사람만 그려, 본인이 아닌 사람이 아바타가 될 수 있다.
/// 같은 사람이 여러 번 나오는 인생네컷 · 콜라주도 여러 명으로 잡힌다. 기준을 바꿀 때는 이 값 하나만 고친다.
const double companionFaceMinWidthShare = 0.5;

/// 얼굴 상자 폭들 가운데 가장 큰 얼굴 말고도 [companionFaceMinWidthShare] 이상인 얼굴이 있는가.
bool hasCompanionFace(List<double> faceWidths) {
  if (faceWidths.length < 2) return false;
  final largest = faceWidths.reduce(math.max);
  return faceWidths.where((width) => width >= largest * companionFaceMinWidthShare).length >= 2;
}

/// 사진 한 장을 기기 안에서 살펴본 결과(04-2 · 15-7 · 15b). 얼굴이 있으면 가장 큰 얼굴의 폭 ÷ 사진 폭과 같이 나온 사람이 있는지를 함께 담는다.
final class FaceScan {
  const FaceScan.none()
      : hasFace = false,
        widthRatio = null,
        hasCompanion = false;

  /// [widthRatio] 를 잴 수 없었으면(사진 폭을 못 읽음) null.
  const FaceScan.found({this.widthRatio, this.hasCompanion = false}) : hasFace = true;

  final bool hasFace;

  /// 가장 큰 얼굴 상자 폭 ÷ 사진 폭(같은 방향 — 압축본은 회전이 픽셀에 구워져 있다).
  final double? widthRatio;

  /// 가장 큰 얼굴 말고도 큰 얼굴이 있다([hasCompanionFace]) — 아바타 원본으로 쓰지 않는다.
  final bool hasCompanion;

  bool get isTooSmallForAvatar => isFaceTooSmallForAvatar(widthRatio);
}
