import 'package:campus_mate/matching/model/card_detail.dart';

/// 받은 신청 · 프로필 보기(pen `o4QqYR`)의 읽기 상태. 읽기 한 번으로 끝나 결과마다 새로 만들고 copyWith 는 두지 않는다
/// (14c `PartnerProfileUiState` 와 같은 모양). 결정 중 · 결정 실패는 받은 신청 목록 상태(`AcceptancesUiState`)에 있다.
class AcceptanceDetailUiState {
  const AcceptanceDetailUiState({this.isLoading = true, this.detail, this.errorMessage});

  final bool isLoading;
  final CardDetail? detail;

  /// 읽기 실패 문구. 404(없음 · 숨김 · 이미 매칭) · 409(이미 답함) · 410(7일 지남)은 서버 문구 그대로다.
  final String? errorMessage;
}
