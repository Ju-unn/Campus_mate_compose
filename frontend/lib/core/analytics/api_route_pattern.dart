/// 요청 주소를 **경로 패턴**(`/cards/:id/decision`)으로 바꾼다. 오류 수집에 보내는 요청 경로에 사람을 가리키는 값
/// (카드 · 채팅방 · 상대 id, 푸시 토큰, 초대 코드, 닉네임)이 실리지 않게 하는 유일한 길이다.
///
/// 규칙은 **고정 낱말 목록**이다 — 앱이 실제로 부르는 길 이름([routeWords])과 같은 조각만 남기고, 그 밖의 조각은 모두 `:id` 로
/// 바꾼다. 예전에는 소문자 · 하이픈 · 밑줄로만 된 짧은 조각이면 무엇이든 남겼는데, 그러면 소문자로만 된 값(닉네임 · 영문 코드 ·
/// 토큰 조각)이 그대로 새어 나갈 수 있어 목록 방식으로 바꿨다(앱 1.0.2 B5).
/// 쿼리 문자열(`?nickname=…`)과 주소 앞부분(호스트)은 버린다.
abstract final class ApiRoutePattern {
  /// 앞 몇 조각까지 보는가. 이 앱 길은 4조각을 넘지 않는다.
  static const int _maxSegments = 6;

  /// 앱이 서버에 부르는 길의 고정 조각(정렬). 자리는 가리지 않는다 — 어느 칸에 있든 이 낱말이면 남는다.
  /// **새 API 경로를 더하면 여기에도 더한다.** 빠지면 그 조각이 `:id` 로 가려져 오류가 어느 길에서 났는지 흐려진다
  /// (`test/core/analytics/api_route_pattern_test.dart` 가 서버를 부르는 소스의 글자 조각을 읽어 빠진 것을 알려 준다).
  /// 값이 들어가는 칸(id · 토큰 · 코드)에서 오는 글자는 절대 더하지 않는다. 값을 경로에 넣는 새 API 는 이 목록으로 못 막는다
  /// (값이 우연히 목록 낱말과 같으면 그대로 나간다) — 값은 쿼리 · 본문으로 보낸다.
  /// `interests` · `my-traits` · `ideal-traits` 는 `TagPickerKind.endpoint`, `everytime_post` · `kakao_share` ·
  /// `poll_vote` 는 `HeartTaskKind.code` 로 경로에 끼워 넣는 고정 값이다.
  static const Set<String> routeWords = {
    'about',
    'acceptances',
    'account',
    'acquisition',
    'app',
    'appearance-type',
    'apple',
    'avatar',
    'basic-info',
    'billing',
    'bio',
    'bio-draft',
    'blocks',
    'card-preview',
    'cards',
    'chat',
    'code-lookup',
    'community',
    'consents',
    'contact-blocks',
    'conversations',
    'decision',
    'everytime_post',
    'friend-reviews',
    'generate',
    'google',
    'graduate-verification',
    'heart-tasks',
    'home',
    'ideal-conditions',
    'ideal-note',
    'ideal-traits',
    'interests',
    'kakao-id',
    'kakao_share',
    'leave',
    'matches',
    'matching-paused',
    'me',
    'messages',
    'my-code',
    'my-traits',
    'next-step',
    'nickname-availability',
    'notification-settings',
    'notifications',
    'paid',
    'people',
    'photos',
    'poll_vote',
    'polls',
    'profile',
    'profile-onboarding',
    'profiles',
    'purchase',
    'push-tokens',
    'read',
    'read-all',
    'received',
    'redeem',
    'referral',
    'regenerate',
    'reports',
    'school-email',
    'school-info',
    'sent',
    'status',
    'submissions',
    'summary',
    'survey',
    'targets',
    'today',
    'trust',
    'unread-count',
    'verification-method',
    'verification-status',
    'verify',
    'version',
    'votes',
    'withdraw',
    'writable',
    'written',
  };

  static String of(Uri url) {
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).take(_maxSegments);
    if (segments.isEmpty) return '/';
    return '/${segments.map(_keep).join('/')}';
  }

  static String _keep(String segment) => routeWords.contains(segment) ? segment : ':id';
}
