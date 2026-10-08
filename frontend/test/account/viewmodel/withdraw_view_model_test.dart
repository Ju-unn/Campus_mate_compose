import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/viewmodel/withdraw_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/draft/fake_draft_store.dart';
import '../model/fake_account_repository.dart';

void main() {
  late FakeAccountRepository repository;
  late FakeDraftStore drafts;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAccountRepository();
    drafts = FakeDraftStore()..saved['account-a/basic_info'] = '{"nickname":"가나다"}';
    container = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repository),
        draftStoreProvider.overrideWithValue(drafts),
      ],
    );
    addTearDown(container.dispose);
    // 시트가 떠 있는 동안처럼 붙잡아 둔다(autoDispose).
    container.listen(withdrawViewModelProvider, (_, _) {});
  });

  WithdrawViewModel viewModel() => container.read(withdrawViewModelProvider.notifier);
  AccountStatus status() => container.read(accountStatusListenableProvider).value;

  test('success marks the account withdrawn', () async {
    await viewModel().withdraw();

    expect(status(), AccountStatus.withdrawn);
    expect(container.read(withdrawViewModelProvider).errorMessage, isNull);
  });

  test('withdrawn 401 on retry counts as success', () async {
    // 첫 응답이 끊겨 다시 눌렀더니 이미 탈퇴된 계정이다 — 원하던 결과가 이미 났다.
    repository.withdrawResult = const FailureResult(WithdrawnFailure());

    await viewModel().withdraw();

    expect(container.read(withdrawViewModelProvider).errorMessage, isNull);
    expect(status(), AccountStatus.withdrawn);
  });

  test('other failure shows its message and stays active', () async {
    repository.withdrawResult = const FailureResult(NetworkFailure());

    await viewModel().withdraw();

    final state = container.read(withdrawViewModelProvider);
    expect(state.errorMessage, '네트워크 연결을 확인해 주세요');
    expect(state.isSubmitting, isFalse);
    expect(status(), AccountStatus.active);
  });

  test('보내는 중에 한 번 더 불러도 서버에는 한 번만 간다', () async {
    repository.holdWithdraw = Completer<void>();

    final first = viewModel().withdraw();
    expect(container.read(withdrawViewModelProvider).isSubmitting, isTrue);
    await viewModel().withdraw();
    repository.holdWithdraw!.complete();
    await first;

    expect(repository.withdrawCalls, 1);
  });

  test('성공 뒤에도 버튼은 꺼 둔 채다 — 로그아웃이 화면을 바꿀 때까지 다시 누르지 못한다', () async {
    await viewModel().withdraw();

    expect(container.read(withdrawViewModelProvider).isSubmitting, isTrue);
  });

  test('탈퇴에 성공하면 온보딩 임시 저장 값을 전부 지운다', () async {
    await viewModel().withdraw();

    expect(drafts.clearAllCalls, 1);
    expect(drafts.saved, isEmpty);
  });

  test('다시 눌러 이미 탈퇴된 계정(401 withdrawn)이어도 성공과 같이 지운다', () async {
    repository.withdrawResult = const FailureResult(WithdrawnFailure());

    await viewModel().withdraw();

    expect(drafts.saved, isEmpty);
  });

  test('탈퇴가 실패하면 임시 저장 값은 그대로 둔다', () async {
    repository.withdrawResult = const FailureResult(NetworkFailure());

    await viewModel().withdraw();

    expect(drafts.clearAllCalls, 0);
    expect(drafts.saved, isNotEmpty);
  });
}
