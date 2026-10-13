import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../profile/model/fake_onboarding_repository.dart';

void main() {
  late FakeOnboardingRepository repository;
  late OnboardingStepListenable listenable;
  late int notifyCount;

  setUp(() {
    repository = FakeOnboardingRepository();
    listenable = OnboardingStepListenable(repository);
    notifyCount = 0;
    listenable.addListener(() => notifyCount++);
    addTearDown(listenable.dispose);
  });

  // 예전에는 조회 전에도 04-1(basicInfo)이라 관문 조회가 먼저 끝나면 온보딩을 마친 사람도 04-1 이 잠깐 보였다.
  test('조회 전에는 아직 모르는 상태(null)로 본다', () {
    expect(listenable.value, isNull);
    expect(repository.fetchCount, 0);
  });

  test('조회에 성공하면 그 단계로 바꾸고 알린다', () async {
    await listenable.refresh();

    expect(listenable.value, OnboardingStep.complete);
    expect(notifyCount, 1);
  });

  test('첫 조회가 04-1 이어도 "모름" 에서 바뀐 것이라 알린다', () async {
    repository.nextResult = const Success(OnboardingStep.basicInfo);

    await listenable.refresh();

    expect(listenable.value, OnboardingStep.basicInfo);
    expect(notifyCount, 1);
  });

  test('첫 조회부터 실패하면 04-1 로 대신하고 알린다 — 스플래시에 갇히지 않게', () async {
    repository.nextResult = const FailureResult(NetworkFailure());

    await listenable.refresh();

    expect(listenable.value, OnboardingStep.basicInfo);
    expect(notifyCount, 1);
  });

  test('아는 단계가 있으면 조회에 실패해도 그대로 둔다', () async {
    await listenable.refresh();

    repository.nextResult = const FailureResult(NetworkFailure());
    await listenable.refresh();

    expect(listenable.value, OnboardingStep.complete);
    expect(notifyCount, 1);
  });

  test('값이 그대로면 알리지 않는다', () async {
    await listenable.refresh();
    await listenable.refresh();

    expect(repository.fetchCount, 2);
    expect(notifyCount, 1);
  });

  test('reset 하면 다시 모르는 상태로 돌아가며 알린다', () async {
    await listenable.refresh();

    listenable.reset();

    expect(listenable.value, isNull);
    expect(notifyCount, 2);
  });

  test('이미 모르는 상태면 reset 해도 알리지 않는다', () {
    listenable.reset();

    expect(listenable.value, isNull);
    expect(notifyCount, 0);
  });
}
