import 'package:campus_mate/common/phone_number_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = PhoneNumberFormatter();

  TextEditingValue value(String text, {int? cursor}) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor ?? text.length));

  TextEditingValue format(String text, {int? cursor, String previous = ''}) =>
      formatter.formatEditUpdate(value(previous), value(text, cursor: cursor));

  test('숫자를 채우는 대로 하이픈이 들어간다', () {
    expect(format('01012345678').text, '010-1234-5678');
    expect(format('0101').text, '010-1');
    expect(format('010').text, '010');
  });

  test('숫자가 아닌 글자와 11자리를 넘는 뒷자리는 버린다', () {
    expect(format('010abc1234-5678999').text, '010-1234-5678');
  });

  test('하이픈이 붙은 값을 붙여넣어도 그대로 읽는다', () {
    final pasted = format('010-1234-5678');

    expect(pasted.text, '010-1234-5678');
    expect(pasted.selection.baseOffset, '010-1234-5678'.length);
  });

  test('가운데를 지우면 커서가 지운 자리에 남는다', () {
    // 커서가 맨 뒤로 튀면 이어서 칠 수 없다 — 하이픈 개수가 아니라 앞에 놓인 숫자를 센다.
    final edited = format('010-234-5678', cursor: 4, previous: '010-1234-5678');

    expect(edited.text, '010-2345-678');
    expect(edited.selection.baseOffset, 3);
  });
}
