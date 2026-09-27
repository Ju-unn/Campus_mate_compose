import 'package:campus_mate/safety/model/partner_profile.dart';

/// 14c 상대 프로필의 상태. 읽기 한 번으로 끝나는 화면이라 결과마다 새로 만들고 copyWith 는 두지 않는다.
class PartnerProfileUiState {
  const PartnerProfileUiState({
    this.isLoading = true,
    this.profile,
    this.errorMessage,
    this.isGone = false,
  });

  final bool isLoading;
  final PartnerProfile? profile;
  final String? errorMessage;

  /// 서버 404 — 매칭 이력 없음 · 차단 · 상대가 나감 · 탈퇴/정지를 서버가 일부러 구별하지 않는다.
  /// 보여 줄 상대가 없으니 화면은 빠져나가며 [errorMessage](서버가 하나로 묶은 문구)를 짧게 띄운다.
  final bool isGone;
}
