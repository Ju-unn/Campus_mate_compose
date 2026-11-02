import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/tour/model/tour_seen_store.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/analytics/fake_analytics_service.dart';
import '../model/fake_tour_seen_store.dart';

void main() {
  late FakeTourSeenStore store;
  late FakeAnalyticsService analytics;

  ProviderContainer containerFor({String? profileId = 'profile-a'}) {
    final container = ProviderContainer(
      overrides: [
        tourSeenStoreProvider.overrideWithValue(store),
        tourAccountIdProvider.overrideWithValue(() => profileId),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    store = FakeTourSeenStore();
    analytics = FakeAnalyticsService();
    AppTourViewModel.autoStartEnabled = true;
  });
  tearDown(() => AppTourViewModel.autoStartEnabled = true);

  group('처음 1회 자동 시작', () {
    test('본 적 없는 계정이면 첫 단계부터 시작하고, 시작하는 순간 본 것으로 저장한다', () async {
      final container = containerFor();

      await container.read(appTourViewModelProvider.notifier).autoStart();

      final state = container.read(appTourViewModelProvider);
      expect(state.active, isTrue);
      expect(state.index, 0);
      expect(state.skipped, 0);
      // 중간에 꺼도 끝난 것 — 다음 단계로 가기 전에 이미 저장돼 있다.
      expect(store.marked, ['profile-a']);
    });

    test('이미 본 계정은 시작하지 않는다', () async {
      store = FakeTourSeenStore(seen: {'profile-a'});
      final container = containerFor();

      await container.read(appTourViewModelProvider.notifier).autoStart();

      expect(container.read(appTourViewModelProvider).active, isFalse);
      expect(store.marked, isEmpty);
    });

    test('같은 기기의 다른 계정은 따로 — b 가 봤어도 a 는 처음이다', () async {
      store = FakeTourSeenStore(seen: {'profile-b'});
      final container = containerFor();

      await container.read(appTourViewModelProvider.notifier).autoStart();

      expect(container.read(appTourViewModelProvider).active, isTrue);
    });

    test('로그인한 계정을 모르면(id 없음) 시작하지 않는다', () async {
      final container = containerFor(profileId: null);

      await container.read(appTourViewModelProvider.notifier).autoStart();

      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('저장소를 못 읽으면 띄우지 않는다 — 매번 뜨는 것보다 안 뜨는 쪽이 낫다', () async {
      store = FakeTourSeenStore(failing: true);
      final container = containerFor();

      await container.read(appTourViewModelProvider.notifier).autoStart();

      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('E2E 빌드처럼 자동 시작을 꺼 두면 처음이어도 시작하지 않는다', () async {
      AppTourViewModel.autoStartEnabled = false;
      final container = containerFor();

      await container.read(appTourViewModelProvider.notifier).autoStart();

      expect(container.read(appTourViewModelProvider).active, isFalse);
      expect(store.marked, isEmpty);
    });

    test('같은 프레임에 두 번 불려도 한 번만 시작한다', () async {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier);

      await Future.wait([viewModel.autoStart(), viewModel.autoStart()]);

      expect(container.read(appTourViewModelProvider).run, 1);
      expect(store.marked, ['profile-a']);
    });
  });

  group('진행', () {
    test('다음 → 한 단계씩, 대상을 못 찾아 건너뛰면 건너뛴 수도 센다, 끝내면 꺼진다', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)..replay();

      viewModel.next();
      expect(container.read(appTourViewModelProvider).index, 1);

      viewModel.skipMissing();
      final skipped = container.read(appTourViewModelProvider);
      expect(skipped.index, 2);
      expect(skipped.skipped, 1);

      viewModel.finish();
      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('다시 보기는 본 적이 있어도 첫 단계부터 다시 시작하고, 시작마다 run 이 오른다', () {
      store = FakeTourSeenStore(seen: {'profile-a'});
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..next()
        ..skipMissing()
        ..skip()
        ..replay();

      final state = container.read(appTourViewModelProvider);
      expect(state.active, isTrue);
      expect(state.index, 0);
      expect(state.skipped, 0);
      expect(state.run, 2);
      expect(viewModel, isNotNull);
    });
  });

  // 사용 통계 tour_finish — 결과(done · skip)와 단계 번호(단계 목록의 몇째, 1부터)만 나간다.
  group('끝내기 분석(tour_finish)', () {
    test('마지막에 "시작하기" 로 끝내면 done 과 그때 단계 번호', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..next()
        ..next();

      viewModel.finish();

      expect(analytics.calls, ['tour_finish:done:3']);
      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('건너뛰면 skip 과 그때 단계 번호', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..next();

      viewModel.skip();

      expect(analytics.calls, ['tour_finish:skip:2']);
      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('대상을 못 찾아 건너뛴 단계가 있어도 번호는 단계 목록에서의 자리다(말풍선 "n / 총" 과 다를 수 있다)', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..skipMissing()
        ..next();

      viewModel.skip();

      expect(analytics.calls, ['tour_finish:skip:3']);
    });

    test('이미 끝난 투어를 또 끝내도 한 번만 남긴다(투어가 사라진 뒤 프레임 콜백이 한 번 더 불러도)', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)..replay();

      viewModel.skip();
      viewModel.skip();
      viewModel.finish();

      expect(analytics.calls, ['tour_finish:skip:1']);
    });

    test('시작하지 않은 투어를 끝내라고 해도 남기지 않는다', () {
      final container = containerFor();

      container.read(appTourViewModelProvider.notifier).skip();

      expect(analytics.calls, isEmpty);
    });

    test('다시 보기로 다시 시작한 투어는 새로 센다', () {
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..next()
        ..skip()
        ..replay();

      viewModel.skip();

      expect(analytics.calls, ['tour_finish:skip:2', 'tour_finish:skip:1']);
    });
  });

}
