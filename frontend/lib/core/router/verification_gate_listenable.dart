import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:flutter/foundation.dart';

/// 조회 결과가 없을 때 쓰는 기본값 — "아직 모름".
/// 생성 직후와 [VerificationGateListenable.reset] 이 같은 값을 써야 해 한곳에 둔다.
const VerificationGate _defaultGate = VerificationGate.unknown;

/// 게이트 상태를 캐시하고, 바뀌면 go_router 재평가를 트리거한다.
/// AuthSessionListenable(1a) 이 세션 변화를 알려줄 때마다 [refresh] 를 호출해 쓴다.
///
/// 조회가 끝나기 전에는 `unknown` 으로 두어 스플래시에 머문다. 낙관적으로 통과시키면
/// "통과 전까지 다음 단계로 못 감"(설계 §7.3)이 깨진다. 예전 기본값 `needsConsent` 는
/// 인터넷 없이 켜면 동의 화면에 세워 두었다(결함 B10) — 첫 조회가 실패하면 `unreachable` 이다.
class VerificationGateListenable extends ChangeNotifier {
  VerificationGateListenable(this._repository);

  final VerificationGateRepository _repository;
  VerificationGate _cached = _defaultGate;

  VerificationGate get value => _cached;

  /// 로그아웃처럼 조회할 근거가 사라지면 기본값으로 되돌린다.
  /// 다음 사용자가 앞 사용자의 통과 상태를 물려받아 홈으로 새면 §7.3 이 깨진다.
  void reset() {
    _cache(_defaultGate);
  }

  Future<void> refresh() async {
    final result = await _repository.fetchGate();
    result.when(
      onSuccess: _cache,
      // 아는 관문이 있으면 그대로 둔다 — 다음 세션 변화 때 다시 시도. 모르는데 실패했으면 01-1 로.
      onFailure: (_) {
        if (_cached == VerificationGate.unknown) {
          _cache(VerificationGate.unreachable);
        }
      },
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
