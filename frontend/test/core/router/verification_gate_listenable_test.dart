import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';

void main() {
  late FakeVerificationGateRepository repository;
  late VerificationGateListenable listenable;
  late int notifyCount;

  setUp(() {
    repository = FakeVerificationGateRepository();
    listenable = VerificationGateListenable(repository);
    notifyCount = 0;
    listenable.addListener(() => notifyCount++);
    addTearDown(listenable.dispose);
  });

  test('조회 전에는 학생증 인증이 필요한 상태로 본다', () {
    expect(listenable.value, VerificationGate.needsStudentVerification);
    expect(repository.fetchCount, 0);
  });

  test('refresh 하면 저장소를 조회해 값을 갱신하고 알린다', () async {
    await listenable.refresh();

    expect(repository.fetchCount, 1);
    expect(listenable.value, VerificationGate.complete);
    expect(notifyCount, 1);
  });

  test('값이 그대로면 알리지 않는다', () async {
    await listenable.refresh();
    await listenable.refresh();

    expect(repository.fetchCount, 2);
    expect(notifyCount, 1);
  });

  test('조회에 실패하면 캐시한 값을 유지한다', () async {
    await listenable.refresh();

    repository.nextResult = const FailureResult(NetworkFailure());
    await listenable.refresh();

    expect(listenable.value, VerificationGate.complete);
    expect(notifyCount, 1);
  });

  test('reset 하면 통과 상태를 버리고 기본값으로 돌아가며 알린다', () async {
    await listenable.refresh();

    listenable.reset();

    expect(listenable.value, VerificationGate.needsStudentVerification);
    expect(notifyCount, 2);
  });

  test('이미 기본값이면 reset 해도 알리지 않는다', () {
    listenable.reset();

    expect(listenable.value, VerificationGate.needsStudentVerification);
    expect(notifyCount, 0);
  });
}
