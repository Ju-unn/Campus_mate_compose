import 'package:campus_mate/tour/model/tour_seen_store.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_tour_seen_store.dart';

void main() {
  late FakeTourSeenStore store;

  ProviderContainer containerFor({String? profileId = 'profile-a'}) {
    final container = ProviderContainer(
      overrides: [
        tourSeenStoreProvider.overrideWithValue(store),
        tourAccountIdProvider.overrideWithValue(() => profileId),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    store = FakeTourSeenStore();
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

      viewModel.end();
      expect(container.read(appTourViewModelProvider).active, isFalse);
    });

    test('다시 보기는 본 적이 있어도 첫 단계부터 다시 시작하고, 시작마다 run 이 오른다', () {
      store = FakeTourSeenStore(seen: {'profile-a'});
      final container = containerFor();
      final viewModel = container.read(appTourViewModelProvider.notifier)
        ..replay()
        ..next()
        ..skipMissing()
        ..end()
        ..replay();

      final state = container.read(appTourViewModelProvider);
      expect(state.active, isTrue);
      expect(state.index, 0);
      expect(state.skipped, 0);
      expect(state.run, 2);
      expect(viewModel, isNotNull);
    });
  });
}
