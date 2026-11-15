/// 아바타 원본으로 쓰려면 사진 속 가장 큰 얼굴의 상자 폭이 사진 폭의 이 비율 이상이어야 한다(사용자 결정 2026-11-15).
/// 0.15 인 이유(사용자 「얼굴폭 15퍼로 하자」): 전신 · 먼 사진(얼굴 폭 4~10%)은 막고 상반신 · 셀카는 통과시킨다.
/// 기준을 바꿀 때는 이 값 하나만 고친다.
const double avatarSourceMinFaceWidthRatio = 0.15;

/// 얼굴이 아바타 원본으로 쓰기에 작은가. 비율을 모르면(null — 검사 실패 · 이미 올려 둔 사진 · 옛 임시 저장) 막지 않는다:
/// 검출기 고장으로 가입이 막히는 쪽이 더 나쁘다(얼굴 검사 예외를 통과시키는 것과 같은 원칙).
bool isFaceTooSmallForAvatar(double? faceWidthRatio) =>
    faceWidthRatio != null && faceWidthRatio < avatarSourceMinFaceWidthRatio;

/// 사진 한 장을 기기 안에서 살펴본 결과(04-2 · 15-7 · 15b). 얼굴이 있으면 가장 큰 얼굴의 폭 ÷ 사진 폭을 함께 담는다.
final class FaceScan {
  const FaceScan.none()
      : hasFace = false,
        widthRatio = null;

  /// [widthRatio] 를 잴 수 없었으면(사진 폭을 못 읽음) null.
  const FaceScan.found({this.widthRatio}) : hasFace = true;

  final bool hasFace;

  /// 가장 큰 얼굴 상자 폭 ÷ 사진 폭(같은 방향 — 압축본은 회전이 픽셀에 구워져 있다).
  final double? widthRatio;

  bool get isTooSmallForAvatar => isFaceTooSmallForAvatar(widthRatio);
}
