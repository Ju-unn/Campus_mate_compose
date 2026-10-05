import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/system_message.dart';
import 'package:campus_mate/chat/view/trust_banner.dart';
import 'package:campus_mate/chat/view/trust_gate_sheet.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/partner_reviews_section.dart';
import 'package:campus_mate/friend_review/view/received_reviews_screen.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_view_model.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

part 'area3_b2.dart';
part 'area3_b3.dart';
part 'area3_safe.dart';
part 'area3_b4.dart';
part 'area3_b5.dart';
part 'area3_b6.dart';

/// 영역 3 폰 A 한 대 1차 — 채팅 · 지인 리뷰 화면 읽기 19개. PC 쪽은 e2e/area3_phone.py 의 같은 번호(계정 · 매칭 · 메시지 ·
/// 리뷰를 준비하고 앱이 말한 값을 판정한다). 앱은 화면을 읽기만 하고 본 것을 Map 으로 돌려준다.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드(frontend/lib/chat · matching/view/conversations_screen.dart · friend_review)에서 옮겼다.

const _sheetTitle = '카카오톡 아이디를 공유할까요?'; // trust_gate_sheet.dart:71 — 14f 시트
const _partnerGone = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'; // chat_room_screen.dart:549
const _leaveChat = '채팅방 나가기'; // chat_room_screen.dart:555
const _tagQuestion = '어떤 장점이 있나요?'; // friend_review_compose_sheet.dart:17 — 20b 시트 본문이 떴다는 표시
const _receivedEntry = '친구들이 본 나'; // my_friend_reviews_section.dart:39
const _writtenEntry = '내가 쓴 리뷰'; // my_friend_reviews_section.dart:46
const _receivedNotice = '받은 리뷰는 직접 삭제할 수 없어요. 부적절한 내용은 신고해주세요.'; // received_reviews_screen.dart
const _writtenNotice = '내가 남긴 리뷰는 언제든 지울 수 있어요.\n수정은 할 수 없어요.'; // written_reviews_screen.dart(줄바꿈 있음)
const _receivedEmpty = '아직 받은 리뷰가 없어요';
const _writtenEmpty = '아직 쓴 리뷰가 없어요';
const _waitingTitle = '리뷰를 기다리는 친구'; // written_reviews_screen.dart 20e-4
const _flag = '신고하기'; // friend_review_card.dart 깃발 tooltip
const _trash = '리뷰 지우기'; // friend_review_card.dart 휴지통 tooltip

/// 앞 가설의 세션을 지우고 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area1.dart 와 같다 — 그쪽 것은 라이브러리 밖에서 못 쓴다).
Area1Case _session(Area1Case body) => (tester, job) async {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

/// 대화 목록의 [nickname] 줄.
Finder _row(String nickname) =>
    find.byWidgetPredicate((w) => w is ChatListRow && w.conversation.partner.nickname == nickname);

Future<void> _toConversations(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('대화'));
}

/// 목록에서 [nickname] 방을 연다 — 앱바에 그 닉네임이 뜨면 방 머리말을 읽은 것이다.
Future<void> _openRoom(WidgetTester tester, String nickname) async {
  await _toConversations(tester);
  await pumpUntil(tester, _row(nickname));
  await tap(tester, _row(nickname));
  await pumpUntil(tester, find.descendant(of: find.byType(AppBar), matching: find.text(nickname)));
}

/// 아래 탭 뱃지 — 탭 이름은 글자라 숫자(와 "99+")만 뱃지다.
String? _navBadge(WidgetTester tester) {
  final badge = find.descendant(
    of: find.byType(AppBottomNav),
    matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+\+?$').hasMatch(w.data ?? '')),
  );
  return badge.evaluate().isEmpty ? null : tester.widget<Text>(badge.first).data;
}

List<String> _banners(WidgetTester tester) =>
    tester.widgetList<TrustBanner>(find.byType(TrustBanner)).map((banner) => banner.title).toList();

/// 말풍선 본문 — 목록이 그려 둔 것(화면 밖 캐시 포함).
List<String> _bubbles(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble, skipOffstage: false))
    .map((bubble) => bubble.message.body)
    .toList();

/// [within] 동안 [finder] 가 한 번이라도 보였는지.
Future<bool> _ever(WidgetTester tester, Finder finder, Duration within) async =>
    await appears(tester, finder, within) != null;

/// E-CHAT-08 · 09 — 목록 줄의 안 읽은 수와 아래 탭 뱃지.
Future<Map<String, Object?>> _badges(WidgetTester tester, Map<String, dynamic> job) async {
  await _toConversations(tester);
  final row = _row(job['nickname'] as String);
  await pumpUntil(tester, row);
  await wait(tester, const Duration(seconds: 1)); // 아래 탭 합(수락 대기 + 안 읽음)이 같이 그려지게
  final badge = find.descendant(of: row, matching: find.byType(UnreadBadge));
  return {
    'row_badge': badge.evaluate().isEmpty
        ? null
        : tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text)).first).data,
    'nav_badge': _navBadge(tester),
  };
}

/// E-CHAT-18 · 19 · 20 — 방을 열고 맨 위까지 올린다. 맨 위 200 안에 들어가면 다음 쪽을 부르므로
/// (chat_room_screen.dart:82-86) 그 바로 밑(201)까지 반 화면씩 올리며 그려진 말풍선을 모으고, 그때의 수를 적은 뒤 맨 위로 간다.
/// 위에 새 쪽이 붙으면(뷰모델 messages 가 늘면) 다시, 5초 동안 안 붙으면 끝. 다음 쪽 요청 수는 뷰모델의 isLoadingMore 로 센다.
/// 최대 스크롤은 늦게 그려지는 줄 때문에 쪽이 안 붙어도 변하므로(실기기 첫 실행: 같은 경계 값이 두 번 기록됨) 쪽 판정에 쓰지 않는다.
Future<Map<String, Object?>> _scrollToTop(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  await pumpUntil(tester, find.byType(MessageBubble));
  final room = find.byType(ChatRoomScreen);
  final container = ProviderScope.containerOf(tester.element(room));
  var requests = 0;
  final provider = chatRoomViewModelProvider(tester.widget<ChatRoomScreen>(room).matchId);
  final watching = container.listen(provider, (previous, next) {
    if (next.isLoadingMore && previous?.isLoadingMore != true) requests++;
  });
  final list = find.descendant(of: find.descendant(of: room, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first;
  ScrollPosition position() => tester.state<ScrollableState>(list).position;
  final seen = <String>{};
  var overlap = 0;
  void look() {
    final bodies = _bubbles(tester);
    overlap = max(overlap, bodies.length - bodies.toSet().length);
    seen.addAll(bodies);
  }

  int loaded() => container.read(provider).messages.length;
  var known = loaded();
  final stages = <int>[];
  try {
    while (true) {
      while (position().pixels < position().maxScrollExtent - 201) {
        final p = position();
        p.jumpTo(min(p.pixels + p.viewportDimension / 2, p.maxScrollExtent - 201));
        await tester.pump(const Duration(milliseconds: 200));
        look();
      }
      look();
      final before = seen.length;
      position().jumpTo(position().maxScrollExtent);
      final watch = Stopwatch()..start();
      var grew = loaded() > known;
      while (!grew && watch.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 200));
        look();
        grew = loaded() > known;
      }
      if (!grew) {
        stages.add(seen.length);
        break;
      }
      stages.add(before);
      known = loaded();
    }
  } finally {
    watching.close();
  }
  return {'stages': stages, 'requests': requests, 'seen': seen.toList(), 'overlap': overlap};
}

/// E-CHAT-60 · 62 앞 — 상대가 나간 방.
Future<Map<String, Object?>> _partnerLeftRoom(WidgetTester tester, Map<String, dynamic> job) async {
  await _openRoom(tester, job['nickname'] as String);
  await pumpUntil(tester, find.byType(SystemMessage));
  final sheet = await _ever(tester, find.text(_sheetTitle), const Duration(seconds: 3));
  return {
    'input': find.byType(ChatInputBar).evaluate().isNotEmpty,
    'notice': find.text(_partnerGone).evaluate().isNotEmpty,
    'leave_button': button(_leaveChat).evaluate().isNotEmpty,
    'bodies': _bubbles(tester),
    'system': tester.widgetList<SystemMessage>(find.byType(SystemMessage, skipOffstage: false)).map((s) => s.body).toList(),
    'banners': _banners(tester),
    'sheet': sheet,
  };
}

/// E-REV-10 · 12 — [20b 열기](app_router.dart:181). 시트 본문이 한 번이라도 떴는지와 토스트 글자.
Future<Map<String, Object?>> _openCompose(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  GoRouter.of(tester.element(screen('home'))).go('${AppRoutes.friendReviewWrite}/${job['profile_id']}');
  var form = false;
  String? toast;
  final watch = Stopwatch()..start();
  while (toast == null && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
    form |= find.text(_tagQuestion).evaluate().isNotEmpty;
    final toasts = find.byType(AppToast);
    if (toasts.evaluate().isNotEmpty) toast = tester.widget<AppToast>(toasts.first).label;
  }
  must(toast != null, '15초 안에 토스트가 안 나옴');
  form |= await _ever(tester, find.text(_tagQuestion), const Duration(seconds: 1)); // 토스트 뒤에 시트가 뜨지 않는지
  return {'toast': toast, 'form': form};
}

/// 나 탭을 열고 GET /me/profile 이 끝날 때까지 기다린다. 화면 위젯은 로딩 스피너일 때도 있어 그것만으론 부족하다 —
/// 안에 Scrollable 이 생겨야 읽기가 끝난 것이다.
Future<void> _openMyTab(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  final loaded = find.descendant(of: find.byType(MyProfileScreen), matching: find.byType(Scrollable));
  try {
    await pumpUntil(tester, loaded, timeout: const Duration(seconds: 60));
  } on TestFailure {
    throw TestFailure(find.byType(MeLoadError).evaluate().isNotEmpty
        ? '나 탭(GET /me/profile)이 오류 화면(MeLoadError)으로 끝남'
        : '나 탭(GET /me/profile)이 60초 안에 로딩을 못 끝냄');
  }
}

/// E-REV-19 · 21 · 22 · 23 · 32 · 33 — 나 탭 → "친구들이 본 나"(20c, list=received) 또는 "내가 쓴 리뷰"(20e, list=written).
Future<Map<String, Object?>> _reviewList(WidgetTester tester, Map<String, dynamic> job) async {
  final received = job['list'] == 'received';
  await _openMyTab(tester);
  final entry = find.text(received ? _receivedEntry : _writtenEntry);
  await tester.scrollUntilVisible(entry, 300,
      scrollable: find.descendant(of: find.byType(MyProfileScreen), matching: find.byType(Scrollable)).first);
  await tap(tester, entry);
  final page = find.byType(received ? ReceivedReviewsScreen : WrittenReviewsScreen);
  Finder inPage(Finder finder) => find.descendant(of: page, matching: finder);
  final emptyTitle = received ? _receivedEmpty : _writtenEmpty;
  await pumpUntil(
    tester,
    inPage(find.byWidgetPredicate((w) => w is FriendReviewCard || (w is Text && w.data == emptyTitle))),
  );
  await wait(tester, const Duration(seconds: 2)); // 들어올 때 다시 읽기 · 기다리는 친구 칸이 늦게 온다
  final cards = tester.widgetList<FriendReviewCard>(inPage(find.byType(FriendReviewCard))).map((card) => {
        'nickname': card.review.nickname,
        'tags': card.review.tags,
        'comment': card.review.comment,
        'school': card.review.university,
      });
  return {
    'cards': cards.toList(),
    'relations': inPage(find.text(friendReviewRelationLabel)).evaluate().length,
    'notice': inPage(find.text(received ? _receivedNotice : _writtenNotice)).evaluate().isNotEmpty,
    'empty': inPage(find.text(emptyTitle)).evaluate().isNotEmpty,
    'trash': inPage(find.byTooltip(_trash)).evaluate().length,
    'flags': inPage(find.byTooltip(_flag)).evaluate().length,
    'waiting': inPage(find.text(_waitingTitle)).evaluate().isNotEmpty,
  };
}

/// E-REV-29 · 30 — 14c 상대 프로필의 지인 리뷰 칸(과 open_sheet 면 14d). 14c 로 가는 화면 길은 신뢰 확인을 통과한 방의
/// 14b "상대 프로필 보기" 뿐이라(방 머리말은 눌리지 않는다) 라우터로 바로 연다.
Future<Map<String, Object?>> _partnerReviews(WidgetTester tester, Map<String, dynamic> job) async {
  await arrive(tester, 'home');
  unawaited(GoRouter.of(tester.element(screen('home'))).push('${AppRoutes.partnerProfile}/${job['profile_id']}'));
  await pumpUntil(tester, find.text('${job['nickname']} 님 프로필'));
  final section = find.byType(PartnerReviewsSection);
  final cards = find.descendant(of: section, matching: find.byType(FriendReviewCard));
  await pumpUntil(tester, cards);
  await wait(tester, const Duration(seconds: 1));
  final link = find.descendant(of: section, matching: find.textContaining('개 모두 보기'));
  final result = <String, Object?>{
    'cards': cards.evaluate().length,
    'link': link.evaluate().isEmpty ? null : tester.widget<Text>(link.first).data,
    'flags': find.descendant(of: section, matching: find.byTooltip(_flag)).evaluate().length,
  };
  if (job['open_sheet'] == true) {
    must(link.evaluate().isNotEmpty, '"모두 보기" 링크가 없어 14d 를 못 연다');
    await tester.ensureVisible(link.first);
    await tester.pump();
    // 보이는 링크 위에 같은 크기의 누르는 칸이 겹쳐 있다(partner_reviews_section.dart) — 그 칸이 탭을 받는다.
    await tester.tap(link.first, warnIfMissed: false);
    final sheet = find.byType(PartnerReviewsSheet);
    final sheetCards = find.descendant(of: sheet, matching: find.byType(FriendReviewCard));
    await pumpUntil(tester, sheetCards, timeout: const Duration(seconds: 5));
    await wait(tester, const Duration(milliseconds: 500));
    result['sheet'] = sheetCards.evaluate().length;
    result['flags'] = (result['flags']! as int) + find.descendant(of: sheet, matching: find.byTooltip(_flag)).evaluate().length;
  }
  return result;
}

final Map<String, Area1Case> area3Cases = {
  'E-CHAT-06': _session((tester, job) async {
    final nicknames = (job['nicknames'] as List).cast<String>();
    await _toConversations(tester);
    for (final nickname in nicknames) {
      await pumpUntil(tester, _row(nickname));
    }
    final order = tester.widgetList<ChatListRow>(find.byType(ChatListRow)).map((row) => row.conversation.partner.nickname);
    return {'order': order.toList()};
  }),
  'E-CHAT-08': _session(_badges),
  'E-CHAT-09': _session(_badges),
  'E-CHAT-18': _session(_scrollToTop),
  'E-CHAT-19': _session(_scrollToTop),
  'E-CHAT-20': _session(_scrollToTop),
  'E-CHAT-36': _session((tester, job) async {
    await _openRoom(tester, job['nickname'] as String);
    await pumpUntil(tester, find.byType(ChatInputBar));
    final sheet = await _ever(tester, find.text(_sheetTitle), const Duration(seconds: 3));
    return {'banners': _banners(tester), 'sheet': sheet};
  }),
  'E-CHAT-60': _session(_partnerLeftRoom),
  'E-CHAT-62': _session((tester, job) async {
    await _toConversations(tester);
    final row = _row(job['nickname'] as String);
    await pumpUntil(tester, row);
    return {'preview': tester.widget<ChatListRow>(row).conversation.lastMessage};
  }),
  'E-REV-10': _session(_openCompose),
  'E-REV-12': _session(_openCompose),
  'E-REV-19': _session(_reviewList),
  'E-REV-21': _session(_reviewList),
  'E-REV-22': _session(_reviewList),
  'E-REV-23': _session(_reviewList),
  'E-REV-29': _session(_partnerReviews),
  'E-REV-30': _session(_partnerReviews),
  'E-REV-32': _session(_reviewList),
  'E-REV-33': _session(_reviewList),
  ...area3Cases2,
  ...area3CasesSafe,
  ...area3Cases3,
  ...area3Cases4,
  ...area3Cases5,
  ...area3Cases6,
};
