import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 에뮬 홈 가설 7개(E-HOME-20 · 21 · 22 · 30 · 31 · 32 · 33) — 19 코호트 대기 화면 · "친구에게 초대 링크 보내기" · 글자 확대. B에뮬 전용.
/// PC 쪽은 e2e/area2_emu_home.py 의 같은 번호 — 시험대학을 닫고(여는 시각 = 다음 월요일 07:00) 계정 · 기대값을 일감에 실어 준다.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드(home/view/cohort_wait_view.dart · common/failure.dart)에서 옮겼다. lib/ 는 바꾸지 않는다.
/// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

const _cohortLine = '우리 학교 첫 카드까지'; // cohort_wait_view.dart _Hero — "우리 학교 첫 카드까지 · D-5"
const _recruitLabel = '현재 모집 인원'; // _RecruitPanel
const _inviteLabel = '친구에게 초대 링크 보내기'; // _InviteButton
const _networkDown = '네트워크 연결을 확인해 주세요'; // common/failure.dart NetworkFailure — 코드를 못 받았을 때 토스트 글
const _todayTitle = '오늘의 카드'; // today_cards_screen.dart 앱바

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area2_d.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

int _count(Finder finder) => finder.evaluate().length;

/// 날짜가 들어가는 글(D-숫자 · "M월 D일")은 기기 시간대가 서울(+9)이어야 PC 가 센 값과 같다.
void _requireSeoul() {
  if (DateTime.now().timeZoneOffset != const Duration(hours: 9)) {
    throw E2eBlocked('기기 시간대가 서울(+9)이 아님(${DateTime.now().timeZoneName}) — 앱의 달력 날짜가 PC 와 달라 판정할 수 없다');
  }
}

/// 홈 요약이 실제로 와야(null 이 아니어야) 코호트 여부가 정해진다 — 오기 전에는 히어로가 보인다(home_screen.dart).
Future<HomeSummary> _loaded(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 30)) {
    final summary = container.read(homeSummaryProvider).value;
    if (summary != null) return summary;
    await tester.pump(const Duration(milliseconds: 200));
  }
  throw TestFailure('30초 안에 홈 요약이 안 옴');
}

/// 홈에서 코호트 대기 화면이 그려질 때까지 — 닫힌 학교여야 한다(아니면 준비가 틀린 것이라 blocked).
Future<void> _waitScreen(WidgetTester tester) async {
  await arrive(tester, 'home');
  final summary = await _loaded(tester);
  if (summary.cohort == null) throw E2eBlocked('닫힌 학교인데 요약에 cohort 가 없음 — 준비가 틀렸거나 이미 열림');
  await pumpUntil(tester, find.textContaining(_cohortLine), timeout: const Duration(seconds: 10));
}

/// 초대 버튼 — 글자로 찾는다(대기 화면에만 있다).
Finder get _invite => find.text(_inviteLabel);

/// 버튼을 누르고 곧바로 돌아온다 — 공유 창이 뜨면 프레임이 멎을 수 있어 누른 뒤 pump 하지 않는다(E-REF-04 와 같다).
Future<void> _press(WidgetTester tester) async {
  must(_count(_invite) == 1, '초대 버튼 "$_inviteLabel" ${_count(_invite)}개(기대 1)');
  await tester.ensureVisible(_invite);
  await tester.pump();
  await tester.tap(_invite);
}

final Map<String, Area1Case> area2EmuHomeCases = {
  // 닫힌 학교의 메인 탭 = 대기 화면 — D-숫자 · 큰 날짜 · 모집 인원 · 초대 버튼이 PC 가 센 값과 같다.
  'E-HOME-20': _session((tester, job) async {
    _requireSeoul();
    final today = DateTime.now();
    final deviceDay = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (deviceDay != job['today']) throw E2eBlocked('기기 날짜($deviceDay)가 PC 날짜(${job['today']})와 다름 — D-숫자를 비교할 수 없다');
    await _waitScreen(tester);
    final line = '$_cohortLine · D-${job['days']}';
    final date = job['date'] as String;
    final recruit = '${job['recruit']}명';
    final seen = tester.widgetList<Text>(find.textContaining(_cohortLine)).map((t) => t.data).toList();
    must(_count(find.text(line)) == 1, '"$line" ${_count(find.text(line))}개(기대 1) — 보인 글 $seen');
    must(_count(find.text(date)) == 1, '큰 날짜 "$date" ${_count(find.text(date))}개(기대 1)');
    must(_count(find.text(_recruitLabel)) == 1, '"$_recruitLabel" ${_count(find.text(_recruitLabel))}개(기대 1)');
    must(_count(find.text(recruit)) == 1, '모집 인원 "$recruit" ${_count(find.text(recruit))}개(기대 1)');
    must(_count(_invite) == 1, '"$_inviteLabel" ${_count(_invite)}개(기대 1)');
    return null;
  }),
  // 오늘 탭도 같은 대기 화면 — "우리 학교 첫 카드까지" 1개, 카드 목록 0.
  'E-HOME-21': _session((tester, job) async {
    await _waitScreen(tester);
    await tap(tester, _tab('오늘'));
    await pumpUntil(tester, find.text(_todayTitle), timeout: const Duration(seconds: 15));
    await pumpUntil(tester, find.textContaining(_cohortLine), timeout: const Duration(seconds: 15));
    must(_count(find.textContaining(_cohortLine)) == 1, '"$_cohortLine" ${_count(find.textContaining(_cohortLine))}개(기대 1)');
    must(_count(find.byType(CohortWaitView)) == 1, '대기 화면 ${_count(find.byType(CohortWaitView))}개(기대 1)');
    must(_count(find.byType(DailyCardSummary)) == 0, '대기 화면인데 카드 ${_count(find.byType(DailyCardSummary))}장이 보임');
    return null;
  }),
  // 모집 인원 = 같은 학교의 활성 계정 수. 앱을 켜 보고(PC 가 V 한 명을 탈퇴시킨 뒤) 다시 켜면 하나 줄어 있다 — 어느 쪽이든 PC 가 DB 에서 센 값을 준다.
  'E-HOME-22': _session((tester, job) async {
    await _waitScreen(tester);
    final recruit = '${job['recruit']}명';
    final shown = tester.widgetList<Text>(find.textContaining(RegExp(r'^\d+명$'))).map((t) => t.data).toList();
    must(_count(find.text(recruit)) == 1, '모집 인원 "$recruit" ${_count(find.text(recruit))}개(기대 1) — 보인 글 $shown');
    return null;
  }),
  // 버튼 → 휴대폰 공유 창 → PC 가 창의 "복사" 를 누른다 → 앱이 읽은 클립보드가 초대 글이다(글은 PC 가 같은 코드로 짜서 맞춘다).
  'E-HOME-30': _session((tester, job) async {
    await _waitScreen(tester);
    await Clipboard.setData(const ClipboardData(text: '')); // 앞 가설이 남긴 글이 초대 글과 같아 보이지 않게
    await _press(tester);
    await step('shared'); // PC 가 공유 창이 떴는지 보고 "복사" 를 누른다
    await wait(tester, const Duration(seconds: 2));
    return {'clipboard': (await Clipboard.getData(Clipboard.kTextPlain))?.text};
  }),
  // 대기 화면이 뜬 뒤 PC 가 네트워크를 끈다 → 버튼 → 오류 토스트 1개(3초), 공유 창 0, 앱은 그대로.
  'E-HOME-31': _session((tester, job) async {
    await _waitScreen(tester);
    await step('offline'); // PC 가 네트워크를 끈다
    await tester.pump(const Duration(seconds: 1));
    await _press(tester);
    final toast = find.byType(AppToast);
    final shown = await appears(tester, toast, const Duration(seconds: 15));
    must(shown != null, '네트워크를 끄고 눌렀는데 15초 안에 토스트가 안 뜸');
    must(_count(toast) == 1, '토스트 ${_count(toast)}개(기대 1)');
    final label = tester.widget<Text>(find.descendant(of: toast, matching: find.byType(Text))).data;
    must(label == _networkDown, '토스트 글 "$label"(기대 "$_networkDown")');
    // 토스트가 뜬 때부터 센다 — 프레임 하나가 느린 만큼 "사라짐" 을 늦게 본다(area1_emu E-GATE-12 와 같은 허용).
    final watch = Stopwatch()..start();
    var slowest = Duration.zero;
    var last = Duration.zero;
    while (toast.evaluate().isNotEmpty && watch.elapsed < const Duration(seconds: 8)) {
      await tester.pump(const Duration(milliseconds: 100));
      final now = watch.elapsed;
      if (now - last > slowest) slowest = now - last;
      last = now;
    }
    must(toast.evaluate().isEmpty, '8초가 지나도 토스트가 안 사라짐');
    final held = watch.elapsed;
    final detail = '토스트 ${held.inMilliseconds}ms(뜨기까지 ${shown!.inMilliseconds}ms · 확인 간격 최대 ${slowest.inMilliseconds}ms)';
    must(held + slowest >= const Duration(milliseconds: 2500), '토스트가 너무 빨리 사라짐: $detail');
    must(held <= const Duration(milliseconds: 3200) + slowest, '토스트가 3초보다 오래 떠 있음: $detail');
    // 공유 창이 떴다면 앱이 앞에 없다(inactive · paused) — PC 도 맨 앞을 따로 본다.
    final state = WidgetsBinding.instance.lifecycleState;
    must(state == null || state == AppLifecycleState.resumed, '앱이 앞에 없음($state) — 공유 창이 떴나');
    must(_count(find.byType(CohortWaitView)) == 1, '토스트 뒤 대기 화면이 사라짐');
    return {'note': detail};
  }),
  // 0.2초 간격으로 두 번 눌러도 공유 창은 한 번 — 누르기는 앱이 하고(adb 는 느려 간격을 못 맞춘다), 창 개수는 PC 가 센다.
  'E-HOME-32': _session((tester, job) async {
    await _waitScreen(tester);
    await _press(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(_invite); // 두 번째 — 코드를 기다리는 동안이면 무시돼야 한다
    await step('tapped'); // PC 가 공유 창 개수를 센다
    await wait(tester, const Duration(seconds: 2));
    return null;
  }),
  // 글자 1.3배 · 360dp(PC 가 에뮬 설정을 바꿔 앱을 새로 켠다) — 날짜 줄이 폭을 안 넘고, 끝까지 스크롤하면 초대 버튼이 스크롤 영역 안에 있다.
  'E-HOME-33': _session((tester, job) async {
    _requireSeoul();
    await arrive(tester, 'home');
    final media = MediaQuery.of(tester.element(find.byType(HomeScreen)));
    final wantWidth = (job['width_dp'] as num).toDouble();
    final wantScale = (job['font_scale'] as num).toDouble();
    if ((media.size.width - wantWidth).abs() > 1) throw E2eBlocked('화면 폭 ${media.size.width}dp 가 ${wantWidth}dp 가 아님 — 기기 설정이 안 먹었다');
    final scale = media.textScaler.scale(14) / 14; // 안드로이드 14 의 비선형 확대는 큰 글자에서 덜 커지므로 작은 글자로 잰다
    if ((scale - wantScale).abs() > 0.1) throw E2eBlocked('글자 배율 $scale 이 $wantScale 이 아님 — 기기 설정이 안 먹었다');
    await _waitScreen(tester);
    final scrollable = find.descendant(of: find.byType(CohortWaitView), matching: find.byType(Scrollable)).first;
    await tester.fling(scrollable, const Offset(0, -3000), 3000); // 끝까지
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    must(_count(_invite) == 1, '"$_inviteLabel" ${_count(_invite)}개(기대 1)');
    final area = tester.getRect(scrollable);
    final button = tester.getRect(_invite);
    must(button.top >= area.top - 1 && button.bottom <= area.bottom + 1, '초대 버튼이 스크롤 영역 밖: 버튼 $button · 영역 $area');
    final date = tester.getRect(find.text(job['date'] as String));
    must(date.left >= -1 && date.right <= media.size.width + 1, '날짜 줄이 화면 폭을 넘음: $date · 폭 ${media.size.width}');
    final error = tester.takeException();
    must(error == null, '레이아웃 오류: $error');
    return {'note': '폭 ${media.size.width}dp · 배율 ${scale.toStringAsFixed(2)}'};
  }),
};
