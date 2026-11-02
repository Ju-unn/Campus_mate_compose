/// 요청 주소를 **경로 패턴**(`/cards/:id/accept`)으로 바꾼다. 오류 수집에 보내는 요청 경로에 사람을 가리키는 값
/// (카드 · 채팅방 · 상대 id, 푸시 토큰, 초대 코드)이 실리지 않게 하는 유일한 길이다.
///
/// 규칙은 허용 목록이다 — 고정된 길 이름(소문자 · 하이픈 · 밑줄로만 된 짧은 낱말)만 남기고, 그 밖의 조각은 모두 `:id` 로 바꾼다.
/// 숫자 · 대문자 · 콜론이 든 조각(UUID · 토큰 · 코드)이 새 id 모양을 가져도 낱말 모양이 아니면 저절로 걸러진다.
/// 쿼리 문자열(`?nickname=…`)과 주소 앞부분(호스트)은 버린다.
abstract final class ApiRoutePattern {
  /// 고정된 길 이름은 짧다(`profile-onboarding` 18자). 이보다 길면 낱말이 아니라 값으로 본다.
  static const int _maxWordLength = 40;

  /// 앞 몇 조각까지 보는가. 이 앱 길은 4조각을 넘지 않는다.
  static const int _maxSegments = 6;

  static final RegExp _word = RegExp(r'^[a-z][a-z_-]*$');

  static String of(Uri url) {
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).take(_maxSegments);
    if (segments.isEmpty) return '/';
    return '/${segments.map(_keep).join('/')}';
  }

  static String _keep(String segment) =>
      segment.length <= _maxWordLength && _word.hasMatch(segment) ? segment : ':id';
}
