import 'package:campus_mate/account/model/repository/account_repository.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_ui_state.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/onboarding/model/repository/kakao_id_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common/input_rules_cases.dart';
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

  // 할 일 3 · 대장 판정(11-24): 04-1b 와 같은 규칙 — 서버가 거절할 아이디는 저장을 끄고, 안쪽 공백이면 칸 아래 공백 안내.
  group('입력 중 미리 검사(서버와 같은 표)', () {
    for (final kakaoId in inputRuleCases('kakao_id', 'reject')) {
      test('서버가 거절하는 ${Uri.encodeComponent(kakaoId)} 는 저장할 수 없다', () async {
        await viewModel().load();
        viewModel().change(kakaoId);
        expect(state().canSubmit, isFalse);
      });
    }

    test('안쪽에 공백이 있으면 칸 아래 오류는 공백 안내다', () async {
      await viewModel().load();
      viewModel().change('new id');
      expect(state().fieldError, const AppErrorFailure(AppError.kakaoIdSpace));
    });

    // 대장 규칙(15-6 과 같다): 저장된 옛 값은 사용자가 고칠 때만 본다 — 옛 앱이 받은 값으로 화면이 막히면 안 된다.
    test('저장된 옛 아이디에 안쪽 공백이 있어도 그대로면 오류가 없고 저장을 막지 않는다', () async {
      account.kakaoIdResult = const Success('old id');
      await viewModel().load();

      expect(state().fieldError, isNull);
      expect(state().canSubmit, isTrue);
    });

    test('옛 아이디를 고쳐 쓰면 그때부터 미리 검사한다', () async {
      account.kakaoIdResult = const Success('old id');
      await viewModel().load();
      viewModel().change('old idx');

      expect(state().fieldError, const AppErrorFailure(AppError.kakaoIdSpace));
      expect(state().canSubmit, isFalse);
    });

    test('고쳐 썼다가 옛 값으로 되돌리면 다시 막지 않는다', () async {
      account.kakaoIdResult = const Success('old id');
      await viewModel().load();
      viewModel().change('old idx');
      viewModel().change('old id');

      expect(state().fieldError, isNull);
      expect(state().canSubmit, isTrue);
    });

    testWidgets('고친 값이 공백 아닌 이유로 거절될 값이면 손을 멈춘 뒤에 입력 오류를 띄운다', (tester) async {
      await tester.runAsync(viewModel().load);
      viewModel().change('a');
      expect(state().fieldError, isNull, reason: '쓰는 도중에는 띄우지 않는다');

      await tester.pump(const Duration(milliseconds: 350));

      expect(state().fieldError, const AppErrorFailure(AppError.invalidInput));
    });

    testWidgets('고치지 않은 옛 아이디는 거절될 값이어도 입력 오류를 띄우지 않는다', (tester) async {
      account.kakaoIdResult = const Success('a');
      await tester.runAsync(viewModel().load);

      await tester.pump(const Duration(milliseconds: 350));

      expect(state().fieldError, isNull);
    });

    test('서버 실패가 있으면 그것을 그린다', () async {
      account.kakaoIdResult = const FailureResult(NetworkFailure());
      await viewModel().load();
      expect(state().fieldError, isA<NetworkFailure>());
    });
  });

  test('고쳐 쓰면 오류 문구가 지워진다', () async {
    kakao.nextResult = const FailureResult(NetworkFailure());
    await viewModel().load();
    await viewModel().save();

    viewModel().change('other');

    expect(state().error, isNull);
  });

  // 11-17: 만들자마자 버려지면(로그아웃) build 의 첫 읽기 microtask 가 버려진 ref 를 쓰면 던진다(#768 과 같은 모양).
  test('만들자마자 버려지면 첫 읽기를 하지 않는다', () async {
    final local = ProviderContainer(overrides: [
      accountRepositoryProvider.overrideWithValue(account),
      kakaoIdRepositoryProvider.overrideWithValue(kakao),
    ]);
    local.read(kakaoIdSettingsViewModelProvider);

    local.dispose();

    await pumpEventQueue();
  });
}
