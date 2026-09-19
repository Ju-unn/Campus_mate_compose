import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이 파일 밖에서는 쓰지 않아 private 으로 둔다.
class _FakeVerificationGateRepository implements VerificationGateRepository {
  Result<VerificationGate> nextResult = const Success(VerificationGate.complete);
  int fetchCount = 0;

  @override
  Future<Result<VerificationGate>> fetchGate() async {
    fetchCount++;
    return nextResult;
  }
}

void main() {
  late _FakeVerificationGateRepository repository;
  late VerificationGateListenable listenable;
  late int notifyCount;

  setUp(() {
    repository = _FakeVerificationGateRepository();
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
}
