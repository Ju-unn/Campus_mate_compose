import 'package:flutter/services.dart';

/// 엔터로 만든 줄을 최대 [maxLines] 줄(= 줄 바꿈 [maxLines] - 1 개)로 막는다. 자동 줄 바꿈은 세지 않는다.
/// - 엔터 한 번이 한도를 넘기면 그 입력만 무시한다(글 · 커서 그대로).
/// - 붙여넣기 등으로 한도를 넘기면 넘는 줄 바꿈을 공백으로 바꾼다 — 글은 한 글자도 잃지 않는다.
/// - `\r\n` · `\r` 은 `\n` 하나로 줄인다(Windows 줄 끝이 글자 수에 2로 잡히지 않게).
/// 100자 상한(`codePointLimitFormatter`)보다 먼저 건다. 이 시트 한마디 칸에만 쓴다(신고 메모 · 입력 바는 그대로).
TextInputFormatter lineBreakLimitFormatter(int maxLines) {
  final maxBreaks = maxLines - 1;
  return TextInputFormatter.withFunction((oldValue, newValue) {
    final text = _limit(newValue.text, maxBreaks);
    if (text == newValue.text) {
      return newValue;
    }
    if (_breaks(newValue.text) > maxBreaks && _isSingleBreakInsert(oldValue.text, newValue.text)) {
      return oldValue;
    }
    // 앞부분을 같은 규칙으로 바꾼 길이가 새 커서 자리다(바꾸기가 앞에서부터 세기 때문에 앞부분만 잘라도 같다).
    int map(int offset) => _limit(newValue.text.substring(0, offset.clamp(0, newValue.text.length)), maxBreaks).length;
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: map(selection.baseOffset),
              extentOffset: map(selection.extentOffset),
              affinity: selection.affinity,
              isDirectional: selection.isDirectional,
            )
          : selection,
    );
  });
}

final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');

int _breaks(String text) => _lineBreak.allMatches(text).length;

/// `\r\n` · `\r` 을 `\n` 으로 줄이고, [maxBreaks] 개를 넘는 줄 바꿈은 공백으로 바꾼다.
String _limit(String text, int maxBreaks) {
  var seen = 0;
  return text.replaceAllMapped(_lineBreak, (_) => ++seen > maxBreaks ? ' ' : '\n');
}

/// 앞뒤가 같은 글에서 바뀐 가운데 조각이 줄 바꿈 하나뿐이면(= 엔터 한 번) true.
bool _isSingleBreakInsert(String oldText, String newText) {
  var prefix = 0;
  while (prefix < oldText.length && prefix < newText.length && oldText[prefix] == newText[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldText.length - prefix &&
      suffix < newText.length - prefix &&
      oldText[oldText.length - 1 - suffix] == newText[newText.length - 1 - suffix]) {
    suffix++;
  }
  return const {'\n', '\r\n', '\r'}.contains(newText.substring(prefix, newText.length - suffix));
}
