import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/analytics/collection_switch.dart';

/// 사용 통계 · 오류 수집 · 성능 측정을 **켜도 되는 때**를 정한다 — 약관 동의(02-c)를 마친 로그인 사용자뿐이다.
/// 셋은 늘 같이 켜지고 같이 꺼진다. 앱 루트(main.dart)가 세션 · 관문이 바뀔 때마다 [sync] 를 부른다.
///
/// 켜기 · 끄기는 Firebase 가 기기에 기억한다(앱을 다시 켜도 유지). 그래서 "아직 모르는" 동안(관문 조회 중 · 인터넷 없음)에는
/// 건드리지 않는다 — 동의한 사람이 앱을 켤 때마다 잠깐 꺼졌다 켜져 시작 이벤트를 놓치지 않게. 동의하지 않은 사람이
/// 켜진 채로 남을 길은 없다: 켜는 것은 동의 뒤뿐이고, 로그아웃 · 탈퇴(세션 없음)와 재동의 요구는 반드시 끈다.
class CollectionConsent {
  CollectionConsent(this._switches);

  final List<CollectionSwitch> _switches;

  void sync({required bool isAuthenticated, required VerificationGate gate}) {
    final consented = isAuthenticated ? _consentOf(gate) : false;
    switch (consented) {
      case true:
        for (final collection in _switches) {
          collection.enableAfterConsent();
        }
      case false:
        for (final collection in _switches) {
          collection.disable();
        }
      case null:
        break;
    }
  }

  /// 이 관문에 선 사람이 약관 동의를 마쳤는가. 모르면 null.
  /// 관문이 새로 생기면 여기서 컴파일 오류가 나게 모두 적어 둔다 — 동의 전 관문이 조용히 "켬" 이 되지 않도록.
  static bool? _consentOf(VerificationGate gate) => switch (gate) {
        VerificationGate.unknown || VerificationGate.unreachable => null,
        VerificationGate.needsConsent || VerificationGate.needsConsentRenewal => false,
        VerificationGate.needsSchoolEmail ||
        VerificationGate.needsVerificationMethod ||
        VerificationGate.needsSchoolEmailChosen ||
        VerificationGate.needsGraduateApplication ||
        VerificationGate.graduateReviewing ||
        VerificationGate.needsSchoolInfo ||
        VerificationGate.complete =>
          true,
      };
}
