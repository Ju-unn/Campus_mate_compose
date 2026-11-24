import 'dart:async';

import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [VerificationGateRepository].
/// 기본은 게이트를 모두 통과한 상태이고, `nextResult` 로 다른 결과를 흉내 낸다.
class FakeVerificationGateRepository implements VerificationGateRepository {
  Result<VerificationGate> nextResult = const Success(VerificationGate.complete);

  /// 라우터에 재평가를 알리려고 실제로 조회했는지 확인하는 용도.
  int fetchCount = 0;

  /// 채워 두면 조회가 이 Completer 가 끝날 때까지 기다린다(느린 네트워크 흉내). 끝난 뒤의 [nextResult] 를 준다.
  Completer<void>? holdFetch;

  @override
  Future<Result<VerificationGate>> fetchGate() async {
    fetchCount++;
    await holdFetch?.future;
    return nextResult;
  }
}
