import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/block_list_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/block_list_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_safety_repository.dart';

void main() {
  late FakeSafetyRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeSafetyRepository()
      ..blocks = Success([
        blockedUserFixture(profileId: 'p2', nickname: '여우비'),
        blockedUserFixture(profileId: 'p3', nickname: '소나기'),
      ]);
    container = ProviderContainer(
      overrides: [safetyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  BlockListViewModel viewModel() => container.read(blockListViewModelProvider.notifier);
  BlockListUiState state() => container.read(blockListViewModelProvider);

  Future<BlockListUiState> opened() async {
    container.listen(blockListViewModelProvider, (_, _) {});
    // build() 의 microtask 가 끝나야 목록이 들어온다.
    await Future<void>.delayed(Duration.zero);
    return state();
  }

  test('열면 차단 목록을 읽는다', () async {
    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.blocks.map((user) => user.nickname), ['여우비', '소나기']);
  });

  test('목록을 못 읽으면 문구를 띄운다', () async {
    repository.blocks = const FailureResult(NetworkFailure());

    final loaded = await opened();

    expect(loaded.isLoading, isFalse);
    expect(loaded.blocks, isEmpty);
    expect(loaded.errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('해제에 성공하면 그 줄만 빼고 목록을 다시 부르지 않는다', () async {
    await opened();

    await viewModel().unblock('p2');

    expect(repository.unblocked, ['p2']);
    expect(state().blocks.map((user) => user.profileId), ['p3']);
    expect(repository.fetchCount, 1);
  });

  test('해제에 실패하면 목록은 그대로 두고 문구를 띄운다', () async {
    repository.unblockResult = const FailureResult(ServerUnavailableFailure());
    await opened();

    await viewModel().unblock('p2');

    expect(state().blocks.map((user) => user.profileId), ['p2', 'p3']);
    expect(state().errorMessage, '잠시 뒤 다시 시도해 주세요');
    expect(state().unblockingProfileId, isNull);
  });

  test('해제 중에 또 눌러도 한 번만 보낸다', () async {
    repository.holdUnblock = Completer<void>();
    await opened();

    final first = viewModel().unblock('p2');
    expect(state().unblockingProfileId, 'p2');
    await viewModel().unblock('p2');
    await viewModel().unblock('p3');

    repository.holdUnblock!.complete();
    await first;
    expect(repository.unblocked, ['p2']);
    expect(state().unblockingProfileId, isNull);
  });

  test('읽는 중에 화면을 떠나도 응답이 왔을 때 터지지 않는다', () async {
    repository.holdFetch = Completer<void>();
    final subscription = container.listen(blockListViewModelProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    // 16f 를 뒤로가기로 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    repository.holdFetch!.complete();

    await Future<void>.delayed(Duration.zero);
  });

  test('해제 중에 화면을 떠나도 응답이 왔을 때 터지지 않는다', () async {
    final subscription = container.listen(blockListViewModelProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    repository.holdUnblock = Completer<void>();
    final pending = viewModel().unblock('p2');

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    repository.holdUnblock!.complete();

    await expectLater(pending, completes);
  });
}
