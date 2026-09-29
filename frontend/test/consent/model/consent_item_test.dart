import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('필수 4 · 선택 1(마케팅)', () {
    expect(ConsentItem.values.where((item) => item.isRequired), [
      ConsentItem.terms,
      ConsentItem.privacy,
      ConsentItem.sensitiveReligion,
      ConsentItem.overseasTransfer,
    ]);
    expect(ConsentItem.marketing.isRequired, isFalse);
  });

  test('전선 이름은 서버 policy.py REQUIRED_KINDS 와 같은 글자다 — 마케팅은 없다', () {
    // 언어가 달라 한 테스트로 못 묶는다. 서버 tests/consents/test_policy.py 에도 같은 목록이 있다.
    expect(
      [for (final item in ConsentItem.values) item.wireName],
      ['terms', 'privacy', 'sensitive_religion', 'overseas_transfer', null],
    );
  });

  test('줄 글은 pen 02-c 그대로다', () {
    expect([for (final item in ConsentItem.values) item.label], [
      '이용약관',
      '개인정보 수집·이용',
      '민감정보(종교) 처리',
      '개인정보 국외 이전\n(OpenAI 등)',
      '마케팅 알림 받기',
    ]);
  });

  test('보기는 노션 약관 페이지의 그 항으로 간다 — 마케팅은 보기가 없다', () {
    const page = 'https://app.notion.com/p/3e9d998f0dee8082be84e126630b02a7';
    expect(ConsentItem.terms.link, Uri.parse('$page#792b6855eaa04bf8a24c19c86702d62f'));
    expect(ConsentItem.privacy.link, Uri.parse('$page#efcc38385bef4185b6577d663ebd3bc8'));
    // 종교 문단은 2부 2항 끝에 있다(대장 확인 2026-09-29).
    expect(ConsentItem.sensitiveReligion.link, Uri.parse('$page#efcc38385bef4185b6577d663ebd3bc8'));
    expect(ConsentItem.overseasTransfer.link, Uri.parse('$page#dd3fc6260fa64d78ab12cfaa8a271120'));
    expect(ConsentItem.marketing.link, isNull);
  });
}
