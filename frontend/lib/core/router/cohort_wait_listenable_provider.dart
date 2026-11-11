import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 우리 학교가 아직 첫 카드를 안 열었는지(홈 요약에 cohort) 라우터에 알린다 — 출시 전 막기(사용자 결정 11-11).
///
/// main.dart 는 이것을 라우터의 `refreshListenable` 에 걸고 값은 `isCohortWaiting` 으로 넘긴다
/// (`verificationGateListenableProvider` 와 같은 방식). 요약을 아직 못 받았거나 실패했으면 false — 열린 것으로 친다.
/// 요약은 홈 · 오늘 탭 · 설정이 읽을 때만 받는다 — 여기서 먼저 읽으면(관문 · 온보딩 전) 실패한 요약이 남아
/// 가입을 마친 뒤 홈이 대기 화면을 못 그린다. 그래서 약하게(weak) 듣는다.
final cohortWaitListenableProvider = Provider<ValueListenable<bool>>((ref) {
  final waiting = ValueNotifier(false);
  ref.listen(homeSummaryProvider, (_, summary) => waiting.value = summary.value?.cohort != null, weak: true);
  ref.onDispose(waiting.dispose);
  return waiting;
});
