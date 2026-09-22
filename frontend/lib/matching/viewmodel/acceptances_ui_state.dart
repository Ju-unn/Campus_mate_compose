import 'package:campus_mate/matching/model/acceptance.dart';

/// 받은 수락함(화면 13 상단 섹션)의 상태.
/// [matchedNickname] 과 [errorMessage] 는 [copyWith] 에서 덮어쓰기다 — null 로도 지워져야 한다.
class AcceptancesUiState {
  const AcceptancesUiState({
    this.isLoading = true,
    this.acceptances = const [],
    this.respondingCardId,
    this.matchedNickname,
    this.matchedMatchId,
    this.errorMessage,
  });

  final bool isLoading;
  final List<Acceptance> acceptances;

  /// 답을 보내는 중인 행. 하나라도 있으면 다른 행도 누를 수 없다(연타 방지).
  final String? respondingCardId;

  /// 매칭이 성사된 상대의 닉네임. 화면 12 로 한 번 보내고 비운다.
  final String? matchedNickname;

  /// 그 매칭의 방. 화면 12 의 "대화 시작하기" 가 이걸로 방을 연다(조각 5).
  final String? matchedMatchId;
  final String? errorMessage;

  String? nicknameOf(String cardId) {
    for (final acceptance in acceptances) {
      if (acceptance.cardId == cardId) {
        return acceptance.profile.nickname;
      }
    }
    return null;
  }

  AcceptancesUiState copyWith({
    bool? isLoading,
    List<Acceptance>? acceptances,
    String? respondingCardId,
    String? matchedNickname,
    String? matchedMatchId,
    String? errorMessage,
  }) {
    return AcceptancesUiState(
      isLoading: isLoading ?? this.isLoading,
      acceptances: acceptances ?? this.acceptances,
      respondingCardId: respondingCardId,
      matchedNickname: matchedNickname,
      matchedMatchId: matchedMatchId,
      errorMessage: errorMessage,
    );
  }
}
