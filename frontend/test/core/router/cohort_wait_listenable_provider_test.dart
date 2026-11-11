import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/cohort_wait_listenable_provider.dart';
import 'package:campus_mate/home/model/data/cohort_wait.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/repository/home_repository_provider.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/model/repository/fake_home_repository.dart';

/// 출시 전 막기 — 라우터가 듣는 "학교 오픈 전(코호트 대기)인가". 값은 홈 요약이 정한다.
void main() {
  HomeSummary summaryWith(CohortWait? cohort) => HomeSummary(
        deliveredCards: 0,
        signups: 0,
        conversationsStarted: 0,
        reviewRating: 0,
        reviewCount: 0,
        campuses: const [],
        profileCompletionPercent: 60,
        cohort: cohort,
      );
  final waiting = summaryWith(CohortWait(firstCardAt: DateTime(2099, 9, 21, 7), recruitCount: 5));

  late FakeHomeRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeHomeRepository(Success(waiting));
    container = ProviderContainer(overrides: [homeRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
  });

  test('요약을 스스로 읽지 않는다 — 대기 아님으로 시작하고 조회를 일으키지 않는다', () async {
    expect(container.read(cohortWaitListenableProvider).value, isFalse);

    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 0);
  });

  test('홈이 읽은 요약이 cohort 를 담아 오면 대기로 바뀌고 한 번 알린다', () async {
    final listenable = container.read(cohortWaitListenableProvider);
    var notified = 0;
    listenable.addListener(() => notified++);

    await container.read(homeSummaryProvider.future);

    expect(listenable.value, isTrue);
    expect(notified, 1);
  });

  test('다시 읽은 요약에 cohort 가 없으면(학교가 열림) 대기를 푼다', () async {
    final listenable = container.read(cohortWaitListenableProvider);
    await container.read(homeSummaryProvider.future);
    expect(listenable.value, isTrue);

    repository.summary = Success(summaryWith(null));
    container.invalidate(homeSummaryProvider);
    await container.read(homeSummaryProvider.future);

    expect(listenable.value, isFalse);
  });

  test('요약을 못 받으면 열린 것으로 친다', () async {
    repository.summary = const FailureResult(NetworkFailure());
    final listenable = container.read(cohortWaitListenableProvider);

    await container.read(homeSummaryProvider.future);

    expect(listenable.value, isFalse);
  });
}
