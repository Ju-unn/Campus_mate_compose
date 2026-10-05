import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/auth/session_scope.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart' show homeNowProvider;
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/main.dart' as app;
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 기기 · 시각 가설 13 중 앱이 화면을 보는 6개(E-CARD-03 · 13, E-HOME-23 · 24 · 25 · 26). PC 쪽은 e2e/area2_time_device.py 의 같은 번호.
/// 알림만 보는 가설(E-CARD-01 · 17 · 18 · 19 · 20 · 44, E-HOME-29)은 앱이 홈까지만 켜 두면 되므로 E-ONB-61 을 그대로 쓴다 — 배치 · 알림 확인은 PC.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드(home/view/cohort_wait_view.dart · home_screen.dart · today_cards_screen.dart)에서 옮겼다.
/// lib/ 는 바꾸지 않는다 — E-HOME-26 은 앱 시계 자리(homeNowProvider)를 바꿔 끼운 앱을 다시 띄운다.
/// 이 파일은 `flutter analyze` 만 돌렸고 기기에서는 아직 안 돌려 봤다.

const _cohortLine = '우리 학교 첫 카드까지'; // cohort_wait_view.dart _Hero — "우리 학교 첫 카드까지 · D-5"
const _heroLines = ['오늘의 카드가', '도착했어요']; // home_screen.dart _HeroToday
const _noCandidates = '지금은 소개할 사람이 없어요'; // today_cards_screen.dart _NoCandidatesPanel
const _todayTitle = '오늘의 카드';

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area2_c.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _inHome(Finder finder) => find.descendant(of: find.byType(HomeScreen), matching: finder);

Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

int _count(Finder finder) => finder.evaluate().length;

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 오래 걸리는 PC 일(배치)을 기다리는 멈춤 — support.step 은 2분까지만 기다린다.
Future<void> _longStep(String name, Duration within) async {
  await say({'step': name});
  await hear(timeout: within);
}

/// 날짜 · 시각 가설은 기기 시간대가 서울(+9)이어야 앱의 달력 날짜(D-숫자)가 PC 가 센 날짜와 같다.
void _requireSeoul() {
  if (DateTime.now().timeZoneOffset != const Duration(hours: 9)) {
    throw E2eBlocked('기기 시간대가 서울(+9)이 아님(${DateTime.now().timeZoneName}) — 앱의 달력 날짜가 PC 와 달라 판정할 수 없다');
  }
}

/// 홈 요약이 실제로 와야(null 이 아니어야) 코호트 여부가 정해진다 — 오기 전에는 코호트 학교도 히어로가 보인다(home_screen.dart).
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
Future<void> _waitScreen(WidgetTester tester, {String why = '닫힌 학교인데'}) async {
  await arrive(tester, 'home');
  final summary = await _loaded(tester);
  if (summary.cohort == null) throw E2eBlocked('$why 요약에 cohort 가 없음 — 준비가 틀렸거나 이미 열림');
  await pumpUntil(tester, find.textContaining(_cohortLine), timeout: const Duration(seconds: 10));
}

final Map<String, Area1Case> area2dCases = {
  // 알림만 보는 가설 — 앱은 홈까지 켜 두고(알림 토큰 등록), HOME · 배치 · 알림 확인은 PC 가 한다.
  'E-CARD-01': area1Cases['E-ONB-61']!,
  'E-CARD-17': area1Cases['E-ONB-61']!,
  'E-CARD-18': area1Cases['E-ONB-61']!,
  'E-CARD-19': area1Cases['E-ONB-61']!,
  'E-CARD-20': area1Cases['E-ONB-61']!,
  'E-CARD-44': area1Cases['E-ONB-61']!,
  'E-HOME-29': area1Cases['E-ONB-61']!,
  // 앱이 오늘 탭을 앞에 둔 채 PC 가 배치를 돌린다 — 배너 없이 목록이 저절로 새로 고쳐져 카드가 나타나야 한다.
  'E-CARD-03': _session((tester, job) async {
    await arrive(tester, 'home');
    await tap(tester, _tab('오늘'));
    await pumpUntil(tester, find.text(_todayTitle), timeout: const Duration(seconds: 15));
    await wait(tester, const Duration(seconds: 4)); // 첫 조회가 끝나기를
    if (_count(find.byType(DailyCardSummary)) != 0) throw E2eBlocked('준비가 틀림: 배치 전인데 카드가 이미 있음');
    await _longStep('live', const Duration(minutes: 15)); // PC 가 배치 · 알림창 확인을 한다(새로 고침은 하지 않는다)
    await pumpUntil(tester, find.byType(DailyCardSummary), timeout: const Duration(seconds: 10));
    must(_count(find.byType(DailyCardSummary)) == 1, '카드 ${_count(find.byType(DailyCardSummary))}장(기대 1)');
    return null;
  }),
  // 후보가 하나도 없는 사람 — PC 가 후보를 쉬게 하고 배치를 돌린 뒤 오늘 탭을 열면 11b.
  'E-CARD-13': _session((tester, job) async {
    await arrive(tester, 'home');
    await wait(tester, const Duration(seconds: 2));
    await _longStep('batch', const Duration(minutes: 15));
    await tap(tester, _tab('오늘'));
    await pumpUntil(tester, find.text(_noCandidates), timeout: const Duration(seconds: 30));
    must(_count(find.text(_noCandidates)) == 1, '"$_noCandidates" ${_count(find.text(_noCandidates))}개');
    must(_count(find.byType(DailyCardSummary)) == 0, '후보가 없는데 카드가 보임');
    return null;
  }),
  // 닫힌 학교(wait) → PC 가 여는 시각을 지난 월요일로 옮기고 앱을 강제 종료 · 실행(open) → 대기 화면 0 · 히어로 1.
  'E-HOME-23': _session((tester, job) async {
    if (job['phase'] == 'wait') {
      await _waitScreen(tester);
      must(_count(_inHome(find.text(_heroLines.first))) == 0, '대기 화면인데 히어로 줄 "${_heroLines.first}" 가 보임');
      return null;
    }
    await arrive(tester, 'home');
    final summary = await _loaded(tester);
    must(summary.cohort == null, '여는 시각이 지났는데 요약에 cohort 가 남음');
    await tester.pump(const Duration(milliseconds: 500));
    must(_count(find.textContaining(_cohortLine)) == 0, '대기 화면 글자 "$_cohortLine" 이 남음');
    for (final line in _heroLines) {
      must(_count(_inHome(find.text(line))) == 1, '히어로 줄 "$line" ${_count(_inHome(find.text(line)))}개(기대 1)');
    }
    return null;
  }),
  // 대기 화면을 켜 둔 채 PC 시계가 07:00 을 지난다 — 다시 켜지 않아도 09b 로 바뀌고, 요약을 다시 읽는 간격은 1분 이상이어야 한다.
  'E-HOME-24': _session((tester, job) async {
    await _waitScreen(tester, why: '월요일 07:00 직전인데');
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    final loads = <int>[];
    // 요약을 읽기 시작한 때마다 적는다 — 서버 로그가 아니라 앱이 요청을 낸 횟수다.
    final subscription = container.listen<AsyncValue<HomeSummary?>>(homeSummaryProvider, (previous, next) {
      if (next.isLoading) loads.add(_nowMs());
    });
    final deadline = job['deadline_ms'] as int;
    int? openedAt;
    while (_nowMs() < deadline) {
      await tester.pump(const Duration(milliseconds: 200));
      final summary = container.read(homeSummaryProvider).value;
      if (summary != null && summary.cohort == null && _count(_inHome(find.text(_heroLines.first))) == 1) {
        openedAt = _nowMs();
        break;
      }
    }
    subscription.close();
    must(openedAt != null, '마감 안에 09b 로 안 바뀜 — 지금 화면: ${_count(find.textContaining(_cohortLine)) > 0 ? '대기 화면' : '그 밖'}');
    return {'opened_ms': openedAt, 'loads_ms': loads};
  }),
  // 대기 화면의 "D-n" 이 자정을 넘기면 다시 켜지 않아도 "D-(n-1)" 로 줄어든다.
  'E-HOME-25': _session((tester, job) async {
    _requireSeoul();
    await _waitScreen(tester, why: '며칠 뒤 열리는 학교인데');
    final days = job['days'] as int;
    final before = '$_cohortLine · D-$days';
    final after = '$_cohortLine · D-${days - 1}';
    await pumpUntil(tester, find.text(before), timeout: const Duration(seconds: 10));
    final deadline = job['deadline_ms'] as int;
    int? flippedAt;
    while (_nowMs() < deadline) {
      await tester.pump(const Duration(milliseconds: 200));
      if (_count(find.text(after)) == 1) {
        flippedAt = _nowMs();
        break;
      }
    }
    must(flippedAt != null, '마감 안에 "$after" 로 안 바뀜 — 보인 글: ${tester.widgetList<Text>(find.textContaining(_cohortLine)).map((t) => t.data).toList()}');
    must(_count(find.text(before)) == 0, '"$after" 가 떴는데 "$before" 도 남음');
    return {'flipped_ms': flippedAt};
  }),
  // 서버는 "아직 안 열렸다" 고 하고, 앱 시계 자리(homeNowProvider)만 여는 날 06:30 으로 바꿔 끼운 앱을 다시 띄운다 — 요일 · 시각 제약 없음.
  'E-HOME-26': (tester, job) async {
    _requireSeoul();
    final opensAt = DateTime.parse(job['opens_at'] as String).toLocal();
    final fake = DateTime(opensAt.year, opensAt.month, opensAt.day, 6, 30);
    // app.main() 이 이미 띄운 앱을 시계만 다른 같은 앱으로 바꾼다 — main() 과 같은 모양(SessionScope 안에 앱)에 ProviderScope 로 시계 자리만 끼운다.
    // 위험(기기 미확인): SessionScope 의 ProviderScope 안에 겹친 ProviderScope 가 homeNowProvider 를 덮는지 · 옛 앱의 세션 상태가 새 트리에 비치는지.
    runApp(SessionScope(
      key: UniqueKey(), // 같은 타입이라 키가 없으면 옛 SessionScope 상태(옛 provider 컨테이너)를 그대로 이어 쓴다
      authChanges: Supabase.instance.client.auth.onAuthStateChange,
      child: ProviderScope(
        overrides: [homeNowProvider.overrideWithValue(() => fake)],
        child: const app.CampusMateApp(),
      ),
    ));
    await tester.pump();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await signIn(job['token_hash'] as String);
    await _waitScreen(tester);
    must(_count(find.text('$_cohortLine · D-day')) == 1, '"$_cohortLine · D-day" ${_count(find.text('$_cohortLine · D-day'))}개(기대 1)');
    must(_count(find.text('오늘 오전 7시')) == 1, '"오늘 오전 7시" ${_count(find.text('오늘 오전 7시'))}개(기대 1)');
    return null;
  },
};
