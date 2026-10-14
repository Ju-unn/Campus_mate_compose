import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('필수 2 · 선택 1(마케팅) — 09-29 최종 4칸', () {
    // 종교는 개인정보 수집·이용 안에, OpenAI 국외 이전은 처리방침 공개로 대신한다(사용자 결정 2026-09-29).
    expect(ConsentItem.values.where((item) => item.isRequired), [ConsentItem.terms, ConsentItem.privacy]);
    expect(ConsentItem.marketing.isRequired, isFalse);
  });

  test('전선 이름은 서버 policy.py REQUIRED_KINDS 와 같은 글자다 — 마케팅은 없다', () {
    // 언어가 달라 한 테스트로 못 묶는다. 서버 tests/consents/test_policy.py 에도 같은 목록이 있다.
    expect(
      [for (final item in ConsentItem.values) item.wireName],
      ['terms', 'privacy', null],
    );
  });

  test('줄 글은 pen 02-c 그대로다', () {
    expect([for (final item in ConsentItem.values) item.label], [
      '이용약관',
      '개인정보 수집·이용',
      '마케팅 알림 받기',
    ]);
  });

  test('이용약관 보기는 약관동의 페이지, 개인정보 수집·이용 보기는 처리방침 페이지를 연다 — 마케팅은 보기가 없다', () {
    // 주소 글자는 consent_links.dart 한 곳에만 있다(규칙은 consent_links_test.dart). 종교 동의도 privacy 줄이 받는다(09-29).
    expect(ConsentItem.terms.link, termsLink);
    expect(ConsentItem.privacy.link, privacyItemsLink);
    expect(ConsentItem.marketing.link, isNull);
  });
}
