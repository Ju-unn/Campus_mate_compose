import 'package:campus_mate/account/model/repository/account_repository.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_ui_state.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/onboarding/model/repository/kakao_id_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../profile/onboarding/model/repository/fake_kakao_id_repository.dart';
import '../model/repository/fake_account_repository.dart';

void main() {
  late FakeAccountRepository account;
  late FakeKakaoIdRepository kakao;
  late ProviderContainer container;

  setUp(() {
    account = FakeAccountRepository();
    kakao = FakeKakaoIdRepository();
    container = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(account),
        kakaoIdRepositoryProvider.overrideWithValue(kakao),
      ],
    );
    addTearDown(container.dispose);
    // 화면이 떠 있는 동안처럼 붙잡아 둔다(autoDispose).
    container.listen(kakaoIdSettingsViewModelProvider, (_, _) {});
  });

  KakaoIdSettingsViewModel viewModel() => container.read(kakaoIdSettingsViewModelProvider.notifier);
  KakaoIdSettingsUiState state() => container.read(kakaoIdSettingsViewModelProvider);

  test('열면 읽는 중이고 저장할 수 없다', () {
    expect(state().isLoading, isTrue);
    expect(state().canSubmit, isFalse);
  });

  test('load fills the input with the saved id', () async {
    await viewModel().load();

    expect(state().isLoading, isFalse);
    expect(state().kakaoIdInput, 'hong_gildong');
    expect(state().canSubmit, isTrue);
  });

  test('저장된 아이디가 없으면 빈 칸이다', () async {
    account.kakaoIdResult = const Success(null);

    await viewModel().load();

    expect(state().kakaoIdInput, '');
  });

  test('읽지 못하면 문구를 보여준다', () async {
    account.kakaoIdResult = const FailureResult(NetworkFailure());

    await viewModel().load();

    expect(state().isLoading, isFalse);
    expect(state().error, isA<NetworkFailure>());
  });

  test('save trims, submits and completes', () async {
    await viewModel().load();
    viewModel().change('  new_id  ');

    await viewModel().save();

    expect(kakao.submitted, ['new_id']);
    expect(state().completed, isTrue);
    expect(state().isSubmitting, isFalse);
  });

  test('save is disabled for blank input', () async {
    // canSubmit 규칙은 04-1b(KakaoIdUiState)와 같다 — 공백만이면 못 보낸다.
    await viewModel().load();
    viewModel().change('   ');

    expect(state().canSubmit, isFalse);
    await viewModel().save();
    expect(kakao.submitted, isEmpty);
  });

  test('저장이 실패하면 문구를 보여주고 끝나지 않는다', () async {
    kakao.nextResult = const FailureResult(ServerRejectedFailure('형식이 맞지 않아요'));
    await viewModel().load();

    await viewModel().save();

    expect(state().error, isA<ServerRejectedFailure>());
    expect(state().completed, isFalse);
    expect(state().canSubmit, isTrue);
  });

  test('고쳐 쓰면 오류 문구가 지워진다', () async {
    kakao.nextResult = const FailureResult(NetworkFailure());
    await viewModel().load();
    await viewModel().save();

    viewModel().change('other');

    expect(state().error, isNull);
  });
}
