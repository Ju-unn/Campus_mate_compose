import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:campus_mate/graduate/viewmodel/verification_method_ui_state.dart';
import 'package:campus_mate/graduate/viewmodel/verification_method_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../model/fake_graduate_verification_repository.dart';

void main() {
  late FakeGraduateVerificationRepository repository;
  late FakeVerificationGateRepository gateRepository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeGraduateVerificationRepository();
    gateRepository = FakeVerificationGateRepository();
    container = ProviderContainer(overrides: [
      graduateVerificationRepositoryProvider.overrideWithValue(repository),
      verificationGateRepositoryProvider.overrideWithValue(gateRepository),
    ]);
    addTearDown(container.dispose);
  });

  /// autoDispose 라 듣는 쪽이 있어야 살아 있다.
  VerificationMethodViewModel viewModel() {
    container.listen(verificationMethodViewModelProvider, (_, _) {});
    return container.read(verificationMethodViewModelProvider.notifier);
  }

  VerificationMethodUiState state() => container.read(verificationMethodViewModelProvider);

  test('처음에는 고른 카드가 없어 [다음] 이 꺼져 있다', () {
    viewModel();

    expect(state().selected, isNull);
    expect(state().canGoNext, isFalse);
  });

  test('카드를 눌러 고르는 것은 앱 안 선택일 뿐 서버를 부르지 않는다', () {
    final model = viewModel();

    model.select(VerificationMethod.schoolEmail);
    model.select(VerificationMethod.graduateCertificate);
    model.select(VerificationMethod.schoolEmail);

    expect(state().selected, VerificationMethod.schoolEmail);
    expect(state().canGoNext, isTrue);
    expect(repository.chosen, isEmpty);
    expect(gateRepository.fetchCount, 0);
  });

  test('[다음] 은 고른 방법을 한 번 보내고 성공하면 관문을 한 번 다시 묻는다', () async {
    final model = viewModel()..select(VerificationMethod.graduateCertificate);

    await model.next();

    expect(repository.chosen, [VerificationMethod.graduateCertificate]);
    expect(gateRepository.fetchCount, 1);
    expect(state().errorMessage, isNull);
  });

  test('고른 카드가 없으면 [다음] 은 아무 일도 하지 않는다', () async {
    final model = viewModel();

    await model.next();

    expect(repository.chosen, isEmpty);
    expect(gateRepository.fetchCount, 0);
  });

  test('보내기에 실패하면 문구를 두고, 선택은 그대로, 관문은 건드리지 않는다', () async {
    repository.chooseResult = const FailureResult(NetworkFailure());
    final model = viewModel()..select(VerificationMethod.schoolEmail);

    await model.next();

    expect(state().errorMessage, '네트워크 연결을 확인해 주세요');
    expect(state().selected, VerificationMethod.schoolEmail);
    expect(state().isSubmitting, isFalse);
    expect(gateRepository.fetchCount, 0);
  });

  test('실패한 뒤 다시 고르면 오류 문구가 사라진다', () async {
    repository.chooseResult = const FailureResult(NetworkFailure());
    final model = viewModel()..select(VerificationMethod.schoolEmail);
    await model.next();

    model.select(VerificationMethod.graduateCertificate);

    expect(state().errorMessage, isNull);
  });

  test('보내는 중에 [다음] 을 연타해도 한 번만 나간다', () async {
    repository.holdChoose = Completer<void>();
    final model = viewModel()..select(VerificationMethod.schoolEmail);

    final first = model.next();
    await pumpEventQueue();
    expect(state().isSubmitting, isTrue);
    expect(state().canGoNext, isFalse);
    final second = model.next();
    repository.holdChoose!.complete();
    await Future.wait([first, second]);

    expect(repository.chosen, hasLength(1));
    expect(gateRepository.fetchCount, 1);
  });

  test('보내는 중에는 카드를 바꾸지 못한다', () async {
    repository.holdChoose = Completer<void>();
    final model = viewModel()..select(VerificationMethod.schoolEmail);

    final sending = model.next();
    await pumpEventQueue();
    model.select(VerificationMethod.graduateCertificate);
    repository.holdChoose!.complete();
    await sending;

    expect(repository.chosen, [VerificationMethod.schoolEmail]);
    expect(state().selected, VerificationMethod.schoolEmail);
  });
}
