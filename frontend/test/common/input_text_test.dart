import 'package:campus_mate/common/input_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'input_rules_cases.dart';

void main() {
  group('연속 글자(서버 has_letter_run 과 같은 표)', () {
    for (final text in inputRuleCases('letter_run', 'run')) {
      test('"$text" 는 같은 글자 3번 또는 알파벳 순서 3글자다', () {
        expect(InputText(text).hasLetterRun(), isTrue);
      });
    }
    for (final text in inputRuleCases('letter_run', 'not_run')) {
      test('"$text" 는 연속 글자가 아니다', () {
        expect(InputText(text).hasLetterRun(), isFalse);
      });
    }
  });

  test('학과처럼 알파벳 순서를 안 보면 "Korean Studies" 의 stu 는 걸리지 않는다', () {
    expect(const InputText('Korean Studies').hasLetterRun(), isTrue);
    expect(const InputText('Korean Studies').hasLetterRun(alphabetOrder: false), isFalse);
    expect(const InputText('aaa학과').hasLetterRun(alphabetOrder: false), isTrue);
  });
}
