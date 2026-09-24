import 'package:flutter/services.dart';

/// 전화번호 입력칸을 `010-1234-5678` 모양으로 유지한다(2026-09-24 사용자 요청).
///
/// 숫자만 남기고 11자리에서 끊은 뒤 3·4번째 자리 뒤에 하이픈을 다시 넣는다.
/// 커서는 **앞에 놓인 숫자 개수**로 다시 잡는다 — 글자 수로 세면 하이픈이 끼어드는 순간
/// 커서가 한 칸씩 밀리고, 붙여넣기·가운데 지우기에서 맨 뒤로 튄다.
class PhoneNumberFormatter extends TextInputFormatter {
  const PhoneNumberFormatter();

  /// 휴대전화 번호 자릿수. 화면이 "다 찼는지" 를 이 값으로 본다.
  static const int maxDigits = 11;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = _digitsOf(newValue.text);
    final capped = digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    // 선택 영역이 없을 때 `end` 는 -1 이다 — 그대로 자르면 예외가 난다.
    final cursor = newValue.selection.end < 0 ? newValue.text.length : newValue.selection.end;
    final digitsBeforeCursor = _digitsOf(newValue.text.substring(0, cursor)).length;
    final text = _hyphenate(capped);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: _offsetAfterDigits(text, digitsBeforeCursor)),
    );
  }

  static String _digitsOf(String text) => text.replaceAll(RegExp(r'\D'), '');

  /// 휴대전화 번호(010-1234-5678) 한 가지만 다룬다 — 이 칸은 지인 등록용 본인 번호다.
  static String _hyphenate(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 7) {
        buffer.write('-');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static int _offsetAfterDigits(String text, int digits) {
    if (digits == 0) {
      return 0;
    }
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (_digitsOf(text[i]).isNotEmpty) {
        seen++;
        if (seen == digits) {
          return i + 1;
        }
      }
    }
    return text.length;
  }
}
