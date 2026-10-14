import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 주소 글자는 consent_links.dart 한 곳에만 둔다 — 여기서는 규칙만 본다(페이지 id 를 다시 적지 않는다).
  final links = {
    'termsLink': termsLink,
    'paidServiceTermsLink': paidServiceTermsLink,
    'privacyPolicyLink': privacyPolicyLink,
    'privacyItemsLink': privacyItemsLink,
  };

  test('모든 링크는 노션 공개 주소(notion.site)다 — app.notion.com 은 기기 브라우저에서 로그인을 요구할 수 있다', () {
    for (final MapEntry(:key, :value) in links.entries) {
      expect((value.scheme, value.host), ('https', 'golden-leech-197.notion.site'), reason: key);
    }
  });

  test('앵커 없이 페이지 맨 위를 연다 — 10-14 노션 재구성으로 옛 블록 앵커가 끊겼다', () {
    for (final MapEntry(:key, :value) in links.entries) {
      expect(value.hasFragment, isFalse, reason: key);
      expect(value.pathSegments, [matches(RegExp(r'^[0-9a-f]{32}$'))], reason: key);
    }
  });

  test('약관 두 줄은 약관동의 페이지, 처리방침 두 줄은 개인정보 처리방침 페이지를 연다', () {
    // 유료 서비스 약관은 약관동의 페이지 II 부다.
    expect(paidServiceTermsLink, termsLink);
    expect(privacyItemsLink, privacyPolicyLink);
    expect(privacyPolicyLink, isNot(termsLink));
  });
}
