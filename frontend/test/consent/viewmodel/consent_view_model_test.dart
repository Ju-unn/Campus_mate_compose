import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_repository_provider.dart';
import 'package:campus_mate/consent/viewmodel/consent_ui_state.dart';
import 'package:campus_mate/consent/viewmodel/consent_view_model.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';
import '../model/fake_consent_repository.dart';

/// 온보딩 단계 조회를 문 앞에 세워 둘 수 있는 가짜 — 게이트보다 먼저 끝나는지 본다.
class _GatedOnboardingRepository extends FakeOnboardingRepository {
  Completer<void>? gate;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() async {
    await gate?.future;
    return super.fetchNextStep();
  }
}

const _required = {
  ConsentItem.terms,
  ConsentItem.privacy,
  ConsentItem.sensitiveReligion,
  ConsentItem.overseasTransfer,
};

void main() {
  late FakeConsentRepository consents;
  late FakeVerificationGateRepository gate;
  late _GatedOnboardingRepository onboarding;
  late ProviderContainer container;

  setUp(() {
    consents = FakeConsentRepository();
    gate = FakeVerificationGateRepository();
    onboarding = _GatedOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        consentRepositoryProvider.overrideWithValue(consents),
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라 듣는 쪽이 있어야 await 사이에 내려가지 않는다.
    final sub = container.listen(consentViewModelProvider, (_, _) {});
    addTearDown(sub.close);
  });

  ConsentViewModel vm() => container.read(consentViewModelProvider.notifier);
  ConsentUiState state() => container.read(consentViewModelProvider);

  test('처음에는 모두 꺼져 있고 보낼 수 없다', () {
    expect(state().checked, isEmpty);
    expect(state().canSubmit, isFalse);
  });

  test('필수 4개를 켜면 보낼 수 있다 — 마케팅은 꺼져 있어도 된다', () {
    for (final item in _required) {
      vm().toggle(item);
    }
    expect(state().canSubmit, isTrue);
    expect(state().allChecked, isFalse);
  });

  test('필수가 하나라도 꺼져 있으면 보낼 수 없다', () {
    vm().toggleAll();
    vm().toggle(ConsentItem.overseasTransfer);
    expect(state().canSubmit, isFalse);
    expect(state().allChecked, isFalse);
  });

  test('전체 동의는 모두 켜고, 다 켜진 상태에서 한 번 더 누르면 모두 끈다', () {
    vm().toggleAll();
    expect(state().checked, ConsentItem.values.toSet());
    expect(state().allChecked, isTrue);

    vm().toggleAll();
    expect(state().checked, isEmpty);
  });

  test('일부만 켜진 상태에서 전체 동의를 누르면 모두 켠다', () {
    vm().toggle(ConsentItem.marketing);
    vm().toggleAll();
    expect(state().checked, ConsentItem.values.toSet());
  });

  test('보내는 동안 다시 눌러도 저장소는 한 번만 부른다', () async {
    consents.gate = Completer<void>();
    vm().toggleAll();

    final first = vm().submit();
    final second = vm().submit();
    expect(state().isSubmitting, isTrue);
    consents.gate!.complete();
    await Future.wait([first, second]);

    expect(consents.submitted, hasLength(1));
    expect(consents.submitted.single, ConsentItem.values.toSet());
  });

  test('성공하면 온보딩 단계를 먼저 끝까지 다시 읽고, 그다음 게이트를 읽는다', () async {
    // 재동의 계정은 앱을 켤 때 next-step 이 403 이라 온보딩 캐시가 기본값(04-1)에 머문다.
    // 게이트가 먼저 complete 로 바뀌면 라우터가 04-1 로 보낸다 — 온보딩 단계가 먼저여야 한다.
    onboarding.gate = Completer<void>();
    for (final item in _required) {
      vm().toggle(item);
    }

    final submitting = vm().submit();
    await pumpEventQueue();
    expect(onboarding.fetchCount, 0, reason: '온보딩 조회가 문 앞에서 기다린다');
    expect(gate.fetchCount, 0, reason: '온보딩 단계가 끝나기 전에는 게이트를 읽지 않는다');

    onboarding.gate!.complete();
    await submitting;
    expect(onboarding.fetchCount, 1);
    expect(gate.fetchCount, 1);
  });

  test('저장이 실패하면 문구를 남기고 다시 누를 수 있다 — 게이트는 읽지 않는다', () async {
    consents.nextResult = const FailureResult(NetworkFailure());
    vm().toggleAll();

    await vm().submit();

    expect(state().errorMessage, const NetworkFailure().toDisplayMessage());
    expect(state().isSubmitting, isFalse);
    expect(state().canSubmit, isTrue);
    expect(gate.fetchCount, 0);
  });

  test('게이트를 다시 읽었는데 화면에 남아 있으면(조회 실패 등) 버튼을 다시 살린다', () async {
    gate.nextResult = const FailureResult(NetworkFailure());
    vm().toggleAll();

    await vm().submit();

    expect(gate.fetchCount, 1);
    expect(state().isSubmitting, isFalse);
  });
}

