import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'area4.dart' show area4Cases;
import 'regen_pick.dart';
import 'support.dart';

/// 영역 2 폰 A 3차 — 망 끊기 5 · 알림 2 · 카드 3 · 공유 창 1 · 하트 모자람 1 · 실제 AI 3. PC 쪽은 e2e/area2_phone3.py 의 같은 번호.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다. 비공개 도우미(_session · _tab 등)는 area2.dart 의 것을 복사했다.

const _networkDown = '네트워크 연결을 확인해 주세요'; // common/failure.dart NetworkFailure
const _retry = '다시 시도';
const _heroLines = ['오늘의 카드가', '도착했어요']; // home_screen.dart _HeroToday
const _heroCta = '지금 확인하기';
const _homeOnly = ['전달된 카드', '가입 수', '시작된 대화', '지금 함께 있는 사람들', '참여 중인 대학', '프로필 완성도']; // 요약이 있어야 그려지는 글
const _waitingTitle = '오늘 카드는 확인했어요'; // today_cards_screen.dart _WaitingPanel
const _noCandidates = '지금은 소개할 사람이 없어요';
const _todayTitle = '오늘의 카드';
const _accept = '대화 신청하기'; // common/widgets/card_action_bar.dart
const _cardNotFound = '카드를 찾을 수 없어요'; // backend core/errors.py CARD_NOT_FOUND
const _detail = '프로필 자세히 보기';
const _verified = '학생 인증';
const _heartTasksRow = '무료로 하트 모으기';
const _inviteRow = '친구 초대';
const _pill = '다시 만들기 · 10'; // me/view/profile_hero.dart — 무료 차례에도 같은 글
const _generating = '아바타로 변환 중이에요'; // me/view/my_profile_screen.dart
const _lowTitle = '하트가 모자라요';
const _lowBody = '하트 10개가 필요해요. 지금 보유한 하트는 9개예요.';
const _lowCta = '하트 충전하기';
const _storeTitle = '하트'; // billing/view/heart_store_screen.dart 앱바 제목 (18)
const _storeSection = '구매하기'; // 18 하트 스토어의 섹션 제목
const _regenTitle = '아바타를 다시 만들까요?';
const _freeBody = '첫 번째 다시 만들기는 무료예요. 새 아바타는 바로 프로필에 반영돼요.';
const _freeCta = '무료로 만들기';
const _paidCta = '10 쓰고 만들기';
final _countdown = RegExp(r'^\d\d:\d\d:\d\d$');

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area2.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _inHome(Finder finder) => find.descendant(of: find.byType(HomeScreen), matching: finder);

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

int _count(Finder finder) => finder.evaluate().length;

/// 오래 걸리는 PC 일(배치 · AI 생성)을 기다리는 멈춤 — support.step 은 2분까지만 기다린다.
Future<void> _longStep(String name, Duration within) async {
  await say({'step': name});
  await hear(timeout: within);
}

/// [finder] 가 [within] 안에 사라지면 true.
Future<bool> _gone(WidgetTester tester, Finder finder, Duration within) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isNotEmpty) {
    if (watch.elapsed > within) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

/// 홈 → 나 탭 → 톱니(설정). [beforeGear] 는 톱니 직전에 멈춘다 — 망을 끊고 설정을 여는 가설용.
Future<void> _toSettings(WidgetTester tester, {Future<void> Function()? beforeGear}) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
  await beforeGear?.call();
  await tap(tester, find.byTooltip('설정'));
  await arrive(tester, 'settings', timeout: const Duration(seconds: 5));
  await wait(tester, const Duration(milliseconds: 500));
}

/// PC 가 망을 끊은 직후 — 연결이 실제로 끊기기까지 잠깐 걸린다.
Future<void> _cut(WidgetTester tester) async {
  await step('cut');
  await wait(tester, const Duration(seconds: 3));
}

Future<void> _failedThenRecovered(WidgetTester tester, Finder recovered) async {
  await pumpUntil(tester, find.text(_retry), timeout: const Duration(seconds: 30));
  must(_count(find.text(_retry)) == 1, '"$_retry" ${_count(find.text(_retry))}개');
  must(_count(find.text(_networkDown)) == 1, '오류 글 "$_networkDown" ${_count(find.text(_networkDown))}개');
  await step('restore');
  await tap(tester, find.text(_retry));
  await pumpUntil(tester, recovered, timeout: const Duration(seconds: 30));
  must(await _gone(tester, find.text(_networkDown), const Duration(seconds: 5)), '복구 뒤에도 오류 글이 남음');
}

Finder get _sheet => find.byType(InviteFriendsSheet);

Finder get _sheetCode => find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^[A-Z0-9]{6}$').hasMatch(w.data ?? '')),
    );

/// 오늘 탭을 열고 [name] 이 뜰 때까지.
Future<void> _todayShows(WidgetTester tester, Finder name) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('오늘'));
  await pumpUntil(tester, name, timeout: const Duration(seconds: 30));
}

int? _seconds(WidgetTester tester) {
  final text = find.byWidgetPredicate((w) => w is Text && _countdown.hasMatch(w.data ?? ''));
  if (text.evaluate().isEmpty) return null;
  final parts = tester.widget<Text>(text.first).data!.split(':').map(int.parse).toList();
  return parts[0] * 3600 + parts[1] * 60 + parts[2];
}

/// 나 탭 → "다시 만들기 · 10" 알약 → 사진 고르기(15b-4 → 15b-5, PC 가 앱 캐시에 넣어 둔 사진 한 장) → 15b 시트가 뜰 때까지.
/// 알약은 이제 시트가 아니라 사진 고르기를 먼저 연다 — 시트의 만들기를 누르면 그 사진이 지금 아바타 원본 칸을 대신한다.
Future<void> _openRegen(WidgetTester tester, String title) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.text(_pill), timeout: const Duration(seconds: 20));
  await e2eRegenToSheet(tester, _pill);
  await pumpUntil(tester, find.text(title), timeout: const Duration(seconds: 10));
}

/// 완성 · 잔액이 정해진 계정의 다시 만들기 한 번(실제 AI). 시트 글을 본 뒤 만들고, PC 가 완성을 확인하는 동안 멈춘다.
Area1Case _regen() => _session((tester, job) async {
      final free = job['free'] == true;
      await _openRegen(tester, _regenTitle);
      final body = free ? _freeBody : '하트 10개가 차감돼요. 지금 보유한 하트는 ${job['balance']}개예요. 새 아바타는 바로 프로필에 반영돼요.';
      must(_count(find.text(body)) == 1, '시트 글 "$body" ${_count(find.text(body))}개');
      await tap(tester, find.text(free ? _freeCta : _paidCta));
      // 만들기는 사진 교체(PUT /me/photos — 업로드 · SafeSearch)가 먼저라 "변환 중" 안내까지 예전(등록만)보다 오래 걸린다 — area5_photo 와 같이 60초.
      await pumpUntil(tester, find.text(_generating), timeout: const Duration(seconds: 60));
      await _longStep('started', const Duration(minutes: 12)); // PC 가 새 아바타 완성 · 잔액을 본다
      must(await _gone(tester, find.text(_generating), const Duration(seconds: 120)), '완성 뒤에도 "$_generating" 안내가 남음');
      return null;
    });

final Map<String, Area1Case> area2cCases = {
  // 홈 요약이 한 번 그려진 뒤 망을 끊고 요약을 다시 받게 한다 — 끈 채 켜면 01-1 에서 막혀 홈에 못 닿는다(E-AUTH-22).
  'E-HOME-09': _session((tester, job) async {
    await arrive(tester, 'home');
    await pumpUntil(tester, _inHome(find.text('지금 함께 있는 사람들')), timeout: const Duration(seconds: 30));
    await _cut(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.invalidate(homeSummaryProvider);
    final watch = Stopwatch()..start();
    while (container.read(homeSummaryProvider).isLoading) {
      must(watch.elapsed < const Duration(seconds: 30), '30초 안에 요약 조회가 안 끝남');
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 500));
    for (final text in [..._heroLines, _heroCta]) {
      must(_count(_inHome(find.text(text))) == 1, '"$text" ${_count(_inHome(find.text(text)))}개');
    }
    for (final text in _homeOnly) {
      must(_count(_inHome(find.textContaining(text))) == 0, '요약이 없는데 "$text" 가 보임');
    }
    return null;
  }),
  'E-CARD-16': _session((tester, job) async {
    await arrive(tester, 'home');
    await _cut(tester);
    await tap(tester, _tab('오늘'));
    // 복구 뒤 모양은 계정 상태(카드 · 대기 · 후보 없음)에 따라 다르다 — 오류 화면이 아니면 된다.
    await _failedThenRecovered(
        tester,
        find.byWidgetPredicate(
            (w) => w is DailyCardSummary || (w is Text && (w.data == _waitingTitle || w.data == _noCandidates))));
    return null;
  }),
  'E-POLL-30': _session((tester, job) async {
    await arrive(tester, 'home');
    await _cut(tester);
    await tap(tester, _tab('커뮤니티'));
    await _failedThenRecovered(tester, find.byTooltip('질문 올리기'));
    return null;
  }),
  'E-HEART-26': _session((tester, job) async {
    await _toSettings(tester, beforeGear: () => _cut(tester));
    await tap(tester, find.text(_heartTasksRow));
    await _failedThenRecovered(tester, find.byType(HeartTaskRow));
    must(_count(find.byType(HeartTaskRow)) == 3, '복구 뒤 줄 ${_count(find.byType(HeartTaskRow))}개(기대 3)');
    return null;
  }),
  // E-SET-61 과 같은 동작(친구 초대 → 오류 + 다시 시도 → 켜고 누르면 코드).
  'E-REF-05': area4Cases['E-SET-61']!,
  // PC 가 오늘 탭 부제를 서울 날짜로 계산해 넘긴다. 남은 시간은 3초 간격으로 두 번 읽어 줄어드는지 본다.
  'E-CARD-14': _waitingCase(),
  'E-CARD-15': _waitingCase(),
  'E-CARD-35': _session((tester, job) async {
    await _todayShows(tester, find.byType(DailyCardSummary));
    must(_count(find.byType(DailyCardSummary)) == 1, '카드 ${_count(find.byType(DailyCardSummary))}장(기대 1)');
    await tap(tester, find.byType(DailyCardSummary));
    await pumpUntil(tester, find.text(_accept), timeout: const Duration(seconds: 15));
    await step('blocked'); // PC 가 상대의 차단 행을 넣는다
    await tap(tester, find.text(_accept));
    await pumpUntil(tester, find.text(_cardNotFound), timeout: const Duration(seconds: 15));
    await tap(tester, find.byType(BackButton));
    must(await _gone(tester, find.byType(DailyCardSummary), const Duration(seconds: 15)), '돌아왔는데 오늘 탭에 카드가 남음');
    return null;
  }),
  // 홈에서 멈춰 PC 가 HOME → 배치 → 알림 확인 → 알림 누르기를 한 뒤 오늘 탭에 온 카드를 본다.
  'E-CARD-02': _session((tester, job) async {
    await arrive(tester, 'home');
    await wait(tester, const Duration(seconds: 2));
    // 새 선정은 구간 안 무작위라 카드 상대가 PC 가 처음 만든 B 가 아닐 수 있다 — PC 가 배치 뒤 실제 카드 상대를 go 에 실어 주면 그 글을 찾는다.
    final go = await step('background', timeout: const Duration(minutes: 6));
    final nameAge = (go['name_age'] ?? job['name_age']) as String;
    final school = (go['school'] ?? job['school']) as String;
    await pumpUntil(tester, find.text(_todayTitle), timeout: const Duration(seconds: 30));
    await pumpUntil(tester, find.byType(DailyCardSummary), timeout: const Duration(seconds: 30));
    must(_count(find.byType(DailyCardSummary)) == 1, '카드 ${_count(find.byType(DailyCardSummary))}장(기대 1)');
    for (final text in [nameAge, _verified, _detail]) {
      must(_count(find.text(text)) == 1, '"$text" ${_count(find.text(text))}개');
    }
    must(find.textContaining(school).evaluate().isNotEmpty, '학교 줄 "$school" 없음');
    return null;
  }),
  // 영역 1 E-ONB-61 과 같은 앱 동작(추천인 폰을 홈까지 켜 둔다) — 알림 확인은 PC.
  'E-REF-18': area1Cases['E-ONB-61']!,
  'E-REF-04': _session((tester, job) async {
    await _toSettings(tester);
    await tap(tester, find.text(_inviteRow));
    await pumpUntil(tester, _sheetCode, timeout: const Duration(seconds: 15));
    final code = tester.widget<Text>(_sheetCode).data!;
    final share = find.descendant(of: _sheet, matching: find.text('공유하기'));
    must(share.evaluate().isNotEmpty, '못 찾음: 공유하기');
    await tester.ensureVisible(share.last);
    await tester.pump();
    await tester.tap(share.last); // 누른 뒤 pump 하지 않는다 — 공유 창이 뜨면 프레임이 멎을 수 있다
    await step('shared'); // PC 가 공유 창에서 "복사" 를 누른다
    await wait(tester, const Duration(seconds: 2));
    final clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    return {'code': code, 'clipboard': clipboard};
  }),
  'E-HEART-44': _session((tester, job) async {
    await _openRegen(tester, _lowTitle);
    must(_count(find.text(_lowBody)) == 1, '시트 글 "$_lowBody" ${_count(find.text(_lowBody))}개');
    await tap(tester, find.text(_lowCta));
    // "하트 충전하기" 는 시트를 닫고 하트 스토어(18)로 간다 — 앱바 "하트" + 섹션 "구매하기" (예전엔 "곧 열려요" 토스트).
    final section = find.text(_storeSection);
    await pumpUntil(tester, section, timeout: const Duration(seconds: 5));
    must(_count(section) == 1, '스토어 섹션 "$_storeSection" ${_count(section)}개');
    final title = find.descendant(of: find.byType(AppBar), matching: find.text(_storeTitle));
    must(_count(title) == 1, '스토어 앱바 제목 "$_storeTitle" ${_count(title)}개');
    must(_count(find.text(_lowTitle)) == 0, '"$_lowTitle" 시트가 닫히지 않음');
    return null;
  }),
  'E-HEART-42': _regen(),
  'E-HEART-43': _regen(),
  'E-HEART-45': _regen(),
};

Area1Case _waitingCase() => _session((tester, job) async {
      await _todayShows(tester, find.text(_waitingTitle));
      must(_count(find.text(_waitingTitle)) == 1, '"$_waitingTitle" ${_count(find.text(_waitingTitle))}개');
      final subtitle = job['subtitle'] as String;
      final seen = tester.widgetList<Text>(find.textContaining('새로운')).map((t) => t.data).toList();
      must(_count(find.text(subtitle)) == 1, '부제 "$subtitle" 가 아님 — 보인 글 $seen');
      final first = _seconds(tester);
      must(first != null, '남은 시간 hh:mm:ss 가 안 보임');
      await wait(tester, const Duration(seconds: 3));
      final second = _seconds(tester);
      must(second != null && second < first!, '남은 시간이 줄지 않음 $first → $second');
      return null;
    });
