import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/viewmodel/method_back_view_model.dart';
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

  MethodBackViewModel viewModel() => container.read(methodBackViewModelProvider.notifier);

  test('뒤로 가면 서버 값을 먼저 비우고(null), 성공하면 관문을 한 번 다시 묻는다', () async {
    await viewModel().goBack();

    expect(repository.chosen, [null]);
    expect(gateRepository.fetchCount, 1);
    expect(container.read(methodBackViewModelProvider).errorMessage, isNull);
    expect(container.read(methodBackViewModelProvider).isLeaving, isFalse);
  });

  test('서버 값을 비우지 못하면 그 자리에 머문다 — 관문을 다시 묻지 않고 오류 문구만 둔다', () async {
    repository.chooseResult = const FailureResult(NetworkFailure());

    await viewModel().goBack();

    expect(repository.chosen, [null]);
    expect(gateRepository.fetchCount, 0);
    expect(container.read(methodBackViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
    expect(container.read(methodBackViewModelProvider).isLeaving, isFalse);
  });

  test('다시 눌러 성공하면 앞의 오류 문구가 사라진다', () async {
    repository.chooseResult = const FailureResult(NetworkFailure());
    await viewModel().goBack();
    repository.chooseResult = const Success(null);

    await viewModel().goBack();

    expect(container.read(methodBackViewModelProvider).errorMessage, isNull);
    expect(gateRepository.fetchCount, 1);
  });

  test('서버 값은 비웠는데 관문을 다시 묻지 못하면 같은 실패 안내(네트워크)를 한 번 남긴다', () async {
    gateRepository.nextResult = const FailureResult(NetworkFailure());

    await viewModel().goBack();

    expect(repository.chosen, [null]);
    expect(gateRepository.fetchCount, 1);
    expect(container.read(methodBackViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
    expect(container.read(methodBackViewModelProvider).isLeaving, isFalse);
  });

  test('연타해도 서버 값 비우기는 한 번만 나간다', () async {
    repository.holdChoose = Completer<void>();

    final first = viewModel().goBack();
    await pumpEventQueue();
    expect(container.read(methodBackViewModelProvider).isLeaving, isTrue);
    final second = viewModel().goBack();
    repository.holdChoose!.complete();
    await Future.wait([first, second]);

    expect(repository.chosen, hasLength(1));
    expect(gateRepository.fetchCount, 1);
  });
}
