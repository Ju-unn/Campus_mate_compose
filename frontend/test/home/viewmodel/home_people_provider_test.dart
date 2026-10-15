import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/viewmodel/home_people_provider.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_home_repository.dart';

/// 레일 사람 칸은 요약과 따로 읽는다. 사람이 있게 받으면 앱이 켜져 있는 동안 그대로 두고,
/// 못 받았거나 빈 목록(인원 부족)이면 5분이 지난 뒤 홈에 다시 들어올 때 다시 받는다.
/// 시간은 testWidgets 의 가짜 시계로 흘린다(위젯은 띄우지 않는다).
void main() {
  ProviderContainer containerWith(FakeHomeRepository repository) {
    final container = ProviderContainer(overrides: [homeRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    return container;
  }

  /// 홈 화면이 들어와 사람 칸을 보고 있는 동안. 닫으면 홈을 떠난 것이다.
  Future<(ProviderSubscription<AsyncValue<HomePeople>>, HomePeople)> enterHome(ProviderContainer container) async {
    final subscription = container.listen(homePeopleProvider, (_, _) {});
    return (subscription, await container.read(homePeopleProvider.future));
  }

  Future<void> leaveHome(WidgetTester tester, ProviderSubscription<AsyncValue<HomePeople>> subscription) async {
    subscription.close();
    await tester.pump();
  }

  test('받은 사람 칸을 그대로 준다', () async {
    final container = containerWith(FakeHomeRepository(const FailureResult(NetworkFailure())));

    expect(await container.read(homePeopleProvider.future), same(twoPeople));
  });

  test('못 받으면 던지지 않고 비어 있는 값을 준다 — 레일은 기본 그림 칸으로 대신한다', () async {
    final container = containerWith(
      FakeHomeRepository(const FailureResult(NetworkFailure()), people: const FailureResult(NetworkFailure())),
    );

    final people = await container.read(homePeopleProvider.future);

    expect(people.isEmpty, isTrue);
    expect(container.read(homePeopleProvider).hasError, isFalse);
  });

  testWidgets('사람이 있게 받았으면 앱이 켜져 있는 동안 다시 받지 않는다 — 홈을 떠났다 와도 · 오래 지나도 · 요약을 다시 읽어도', (tester) async {
    final repository = FakeHomeRepository(const FailureResult(NetworkFailure()));
    final container = containerWith(repository);
    var (subscription, people) = await enterHome(container);
    await leaveHome(tester, subscription);

    await tester.pump(const Duration(hours: 1));
    container.invalidate(homeSummaryProvider);
    await container.read(homeSummaryProvider.future);
    (subscription, people) = await enterHome(container);

    expect(people, same(twoPeople));
    expect(repository.peopleCalls, 1);
  });

  testWidgets('실패 → 5분 안에 홈에 다시 와도 다시 받지 않는다(요청 폭주 방지) → 5분 뒤 다시 오면 다시 받아 성공을 그린다 → 그 뒤로는 그대로', (tester) async {
    final repository = FakeHomeRepository(
      const FailureResult(NetworkFailure()),
      people: const FailureResult(NetworkFailure()),
    );
    final container = containerWith(repository);
    var (subscription, people) = await enterHome(container);
    expect(people.isEmpty, isTrue);
    await leaveHome(tester, subscription);

    await tester.pump(const Duration(minutes: 4));
    (subscription, people) = await enterHome(container);
    expect((people.isEmpty, repository.peopleCalls), (true, 1));
    await leaveHome(tester, subscription);

    repository.people = Success(twoPeople);
    await tester.pump(const Duration(minutes: 1));
    (subscription, people) = await enterHome(container);
    expect(people, same(twoPeople));
    expect(repository.peopleCalls, 2);
    await leaveHome(tester, subscription);

    await tester.pump(const Duration(hours: 1));
    (subscription, people) = await enterHome(container);
    expect(repository.peopleCalls, 2);
  });

  testWidgets('빈 목록(인원 부족)도 5분 뒤 홈에 다시 오면 다시 받는다 — 사람이 늘면 레일에 나온다', (tester) async {
    final repository = FakeHomeRepository(
      const FailureResult(NetworkFailure()),
      people: const Success(HomePeople.none),
    );
    final container = containerWith(repository);
    var (subscription, people) = await enterHome(container);
    expect(people.isEmpty, isTrue);
    await leaveHome(tester, subscription);

    repository.people = Success(twoPeople);
    await tester.pump(const Duration(minutes: 5));
    (subscription, people) = await enterHome(container);

    expect(people, same(twoPeople));
    expect(repository.peopleCalls, 2);
  });

  testWidgets('홈에 머무는 동안은 5분이 지나도 다시 받지 않는다 — 다시 받는 것은 다시 들어올 때다', (tester) async {
    final repository = FakeHomeRepository(
      const FailureResult(NetworkFailure()),
      people: const FailureResult(NetworkFailure()),
    );
    final container = containerWith(repository);
    await enterHome(container);

    await tester.pump(const Duration(minutes: 10));

    expect(repository.peopleCalls, 1);
  });

  test('요약이 실패해도 사람 칸은 따로 받는다', () async {
    final repository = FakeHomeRepository(const FailureResult(NetworkFailure()));
    final container = containerWith(repository);

    expect(await container.read(homeSummaryProvider.future), isNull);
    expect(await container.read(homePeopleProvider.future), same(twoPeople));
  });
}
