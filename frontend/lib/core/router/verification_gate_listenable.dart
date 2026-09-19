import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:flutter/foundation.dart';

/// 게이트 상태를 캐시하고, 바뀌면 go_router 재평가를 트리거한다.
/// AuthSessionListenable(1a) 이 세션 변화를 알려줄 때마다 [refresh] 를 호출해 쓴다.
///
/// 조회가 끝나기 전에는 미인증과 같게 다뤄 `needsStudentVerification` 으로 본다.
/// 낙관적으로 통과시키면 "통과 전까지 다음 단계로 못 감"(설계 §7.3)이 깨지고,
/// 반대로 이미 통과한 사용자는 게이트가 도착하는 즉시 되돌아가 짧은 깜빡임으로 끝난다.
class VerificationGateListenable extends ChangeNotifier {
  VerificationGateListenable(this._repository);

  final VerificationGateRepository _repository;
  VerificationGate _cached = VerificationGate.needsStudentVerification;

  VerificationGate get value => _cached;

  Future<void> refresh() async {
    final result = await _repository.fetchGate();
    result.when(
      onSuccess: _cache,
      onFailure: (_) {}, // 실패하면 캐시를 유지한다 — 다음 세션 변화 때 다시 시도
    );
  }

  /// 값이 그대로면 알리지 않는다 — go_router 가 헛되이 redirect 를 다시 돌지 않게.
  void _cache(VerificationGate gate) {
    if (gate == _cached) {
      return;
    }
    _cached = gate;
    notifyListeners();
  }
}
