import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 입력칸에 글자가 들어올 때 포매터가 순서대로 도는 것과 같다.
  String typed(List<TextInputFormatter> formatters, String text) {
    var value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    for (final formatter in formatters) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    return value.text;
  }

  test('닉네임은 한글·영문만 남고 숫자·특수문자·공백은 들어오지 않는다', () {
    expect(typed(nicknameInputFormatters, '홍길동'), '홍길동');
    expect(typed(nicknameInputFormatters, 'Gildong'), 'Gildong');
    expect(typed(nicknameInputFormatters, '홍길동1!@# '), '홍길동');
  });

  test('닉네임은 한글 조합 중의 자모를 막지 않는다', () {
    // 막으면 기기에서 한글 자체를 칠 수 없다 — 자모만 남은 값은 보낼 때 형식 검사가 거른다.
    expect(typed(nicknameInputFormatters, 'ㅎ'), 'ㅎ');
    expect(typed(nicknameInputFormatters, '호ㅇ'), '호ㅇ');
  });

  test('출생연도는 숫자 4자리에서 끊는다', () {
    expect(typed(birthYearInputFormatters, '2003'), '2003');
    expect(typed(birthYearInputFormatters, '20a03년'), '2003');
    expect(typed(birthYearInputFormatters, '20031'), '2003');
  });

  test('키는 숫자 3자리에서 끊는다', () {
    expect(typed(heightInputFormatters, '175'), '175');
    expect(typed(heightInputFormatters, '17cm5'), '175');
    expect(typed(heightInputFormatters, '1750'), '175');
  });
}
