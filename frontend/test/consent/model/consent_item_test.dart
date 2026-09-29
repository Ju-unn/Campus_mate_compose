import 'package:campus_mate/consent/model/consent_item.dart';
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

  test('보기는 노션 약관 페이지의 그 항으로 간다 — 마케팅은 보기가 없다', () {
    const page = 'https://app.notion.com/p/3e9d998f0dee8082be84e126630b02a7';
    expect(ConsentItem.terms.link, Uri.parse('$page#792b6855eaa04bf8a24c19c86702d62f'));
    // 2부 2항 — 수집·이용 항목과 끝의 종교 문단(대장 확인 2026-09-29). 종교 동의도 이 줄이 받는다.
    expect(ConsentItem.privacy.link, Uri.parse('$page#efcc38385bef4185b6577d663ebd3bc8'));
    expect(ConsentItem.marketing.link, isNull);
  });
}
