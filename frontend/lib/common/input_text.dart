/// 사람이 적는 글 칸의 검사 — 서버 `backend/app/core/text.py` · `core/junk_text.py` 를 그대로 옮겼다.
/// 기준은 서버다. 같은 입력 표(`backend/tests/fixtures/input_rules_cases.json`)를 앱 · 서버 시험이 같이 읽어 어긋나면 실패한다.
///
/// 파이썬과 같게 글자는 코드 포인트로 세고(Dart `length` 는 UTF-16 단위라 이모지가 2로 셈), 앞뒤 공백은 파이썬
/// `str.strip()` 의 공백만 뗀다(Dart `trim()` 은 U+FEFF 를 떼고 U+001C ~ 001F 는 남겨 서버와 달라진다).
extension type const InputText(String _text) {
  /// 0폭 문자(서버 `ZERO_WIDTH`).
  static const Set<int> _zeroWidth = {0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF};

  /// 파이썬 `str.isspace()` 가 참인 글자 전부(유니코드 전 범위에서 뽑은 목록).
  static final Set<int> _pythonSpaces = {
    ...List.generate(5, (index) => 0x09 + index), // \t \n \v \f \r
    ...List.generate(4, (index) => 0x1C + index),
    0x20, 0x85, 0xA0, 0x1680,
    ...List.generate(11, (index) => 0x2000 + index),
    0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
  };

  /// 여러 줄 칸이 받는 제어 문자(탭 · 줄바꿈).
  static const Set<int> _lineBreaks = {0x09, 0x0A, 0x0D};

  /// 앞뒤의 파이썬 공백을 뗀 글.
  InputText stripped() {
    final head = _text.runes.skipWhile(_pythonSpaces.contains).toList();
    final kept = head.reversed.skipWhile(_pythonSpaces.contains).toList().reversed;
    return InputText(String.fromCharCodes(kept));
  }

  /// 0폭 문자를 빼고 앞뒤 공백을 뗀 글(서버 `visible`). 빈 값 · 최소 길이를 잴 때만 쓴다.
  InputText visible() => InputText(String.fromCharCodes(_text.runes.where((code) => !_zeroWidth.contains(code)))).stripped();

  /// 코드 포인트 수(파이썬 `len`).
  int length() => _text.runes.length;

  /// 제어 문자(여러 줄이면 탭 · 줄바꿈은 받는다)나 글 방향 문자가 있다(서버 `has_bad_char`).
  bool hasBadChar({required bool multiline}) =>
      _text.runes.any((code) => _isBidi(code) || (_isControl(code) && !(multiline && _lineBreaks.contains(code))));

  /// 공백(파이썬 `isspace`)이나 0폭 문자가 하나라도 있다.
  bool hasSpaceOrZeroWidth() => _text.runes.any((code) => _pythonSpaces.contains(code) || _zeroWidth.contains(code));

  /// 한글 자음 · 모음 낱자(옛 자모 포함 U+3130 ~ 318F)가 있다.
  bool hasJamo() => _text.runes.any((code) => code >= 0x3130 && code <= 0x318F);

  /// 완성 한글이나 영문이 하나라도 있다.
  bool hasLetter() => RegExp('[가-힣a-zA-Z]').hasMatch(_text);

  /// 같은 글자 3번 연속("aaa" · "가가가") 또는 알파벳 순서 오름 · 내림 3글자("abc" · "cba"), 대소문자 무시(서버 `has_letter_run`).
  /// 학과는 [alphabetOrder] false — "Korean Studies"(stu) 같은 실제 학과가 걸려서다.
  bool hasLetterRun({bool alphabetOrder = true}) {
    final codes = _text.toLowerCase().runes.toList();
    return Iterable<int>.generate(codes.length < 3 ? 0 : codes.length - 2)
        .any((index) => _isRun(codes.sublist(index, index + 3), alphabetOrder: alphabetOrder));
  }

  static bool _isRun(List<int> three, {required bool alphabetOrder}) {
    if (three[0] == three[1] && three[1] == three[2]) {
      return true;
    }
    final step = three[1] - three[0];
    return alphabetOrder && three.every(_isLowerAscii) && (step == 1 || step == -1) && three[2] - three[1] == step;
  }

  static bool _isLowerAscii(int code) => code >= 0x61 && code <= 0x7A;

  /// 유니코드 범주 Cc(U+0000 ~ 001F, U+007F ~ 009F).
  static bool _isControl(int code) => code <= 0x1F || (code >= 0x7F && code <= 0x9F);

  /// 글 방향을 바꾸는 문자(U+202A ~ 202E, U+2066 ~ 2069).
  static bool _isBidi(int code) => (code >= 0x202A && code <= 0x202E) || (code >= 0x2066 && code <= 0x2069);
}
