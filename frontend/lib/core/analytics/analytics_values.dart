// 사용 통계 이벤트 매개변수에 실을 수 있는 **정해진 종류값**들. 매개변수에는 여기 적힌 글자와 작은 정수만 나간다 —
// 사용자 id · 닉네임 · 학교 · 상대 id · 카드 id · 채팅방 id · 금액 · 글 내용 같은 개인을 가리키는 값은 값 목록에 둘 자리가 없다.
//
// 글자를 고치거나 더하면 `docs/ANALYTICS_EVENTS.md` 표도 함께 고친다(시험 `analytics_values_test.dart` 가 글자를 못박는다).

/// 카드가 어디서 왔는지. 서버 `CardSource.daily` 는 분석에서 `free`(무료 카드)라고 부른다.
enum CardOrigin {
  free('free'),
  purchased('purchased');

  const CardOrigin(this.wire);
  final String wire;
}

/// 오늘 탭 유료 카드 칸의 모양 — 지금 열 수 있는 사람이 있다 · 없다.
enum PaidCardState {
  offered('offered'),
  empty('empty');

  const PaidCardState(this.wire);
  final String wire;
}

/// 하트 상점에 들어온 곳. 길 위에서 `extra` 로 실어 보낸다(`HeartStoreEntry` 를 모르는 곳은 [other]).
enum HeartStoreEntry {
  /// 홈 앱바 하트 칩 "+".
  home('home'),

  /// 설정의 보유 하트 블록 · 하트 충전 줄.
  settings('settings'),

  /// 오늘 탭 유료 카드의 "하트가 모자라요" 시트 → 하트 스토어로 가기.
  paidCard('paid_card'),

  /// 아바타 다시 만들기 시트의 "하트 충전하기".
  avatarRegen('avatar_regen'),

  /// 그 밖의 "하트가 모자라요" 안내에서 온 길. 아직 이 값을 쓰는 진입점은 없다(예약).
  heartShort('heart_short'),

  /// 위에 들지 않는 곳(나 탭 칩 · 앱 투어 · 길을 직접 연 경우).
  other('other');

  const HeartStoreEntry(this.wire);
  final String wire;
}

/// 하트 결제 창의 결과. 느린 결제 확인(pending)은 아직 성공도 실패도 아니라 보내지 않는다.
enum HeartPurchaseResult {
  success('success'),
  cancel('cancel'),
  fail('fail');

  const HeartPurchaseResult(this.wire);
  final String wire;
}

/// 앱 투어를 어떻게 끝냈는가 — 끝까지 봤다(done) · 건너뛰었다(skip).
enum TourResult {
  done('done'),
  skip('skip');

  const TourResult(this.wire);
  final String wire;
}

/// 가입 단계에서 막힌 이유(`onboarding_blocked.reason`).
enum OnboardingBlockReason {
  /// 글자 많은 사진(학생증 · 서류)을 서버가 거절했다.
  photoDocument('photo_document'),

  /// 서버가 사진을 거절했다(부적절 사진 등, 위 서류 거절 제외).
  photoRejected('photo_rejected'),

  /// 고른 사진에서 얼굴을 못 찾아 한 장도 담지 못했다(기기 안 검사).
  photoNoFace('photo_no_face'),

  /// 서버가 입력을 거절했다(닉네임 중복 등 4xx).
  rejected('rejected'),

  /// 인터넷 연결 실패.
  network('network'),

  /// 서버가 잠깐 못 받거나 오류를 냈다(5xx).
  server('server'),

  /// 요청이 너무 많다는 한도(429).
  rateLimited('rate_limited'),

  /// 로그인이 끊겼다.
  session('session');

  const OnboardingBlockReason(this.wire);
  final String wire;
}

/// 푸시를 눌러 앱이 열릴 때의 종류 — 푸시 `data.route` 값(`PushRoute.resolve`)과 같은 글자다. 모르는 값은 [other].
enum PushOpenType {
  dailyCard('daily_card'),
  acceptances('acceptances'),
  match('match'),
  chat('chat'),
  friendReviews('friend_reviews'),
  friendReviewWrite('friend_review_write'),
  heartTasks('heart_tasks'),
  heartTaskRetry('heart_task_retry'),
  poll('poll'),
  other('other');

  const PushOpenType(this.wire);
  final String wire;
}
