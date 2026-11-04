/// 지킴 시험이 Dart 소스에서 문자열 리터럴 · 주석을 가려내는 작은 분리기(1.0.2 B8).
///
/// 줄 단위 정규식(`font_size_tokens_test` 방식)은 꼬리 주석 · 여러 줄 문자열 · `${}` 안의 문자열에서 틀리므로, 따옴표 · 삼중 따옴표 ·
/// raw · 보간 중첩 · 줄/블록 주석을 직접 읽는다. 이 파일의 동작은 `dart_literals_test.dart` 가 지킨다.
library;

final RegExp _hangul = RegExp('[가-힣ㄱ-ㆎ]');

/// 화면에 안 나가는 개발자용 호출 — 이 안의 글자는 옮기지 않는다(로그 · assert · throw · 정규식).
const Set<String> _developerCalls = {'debugPrint', 'assert', 'RegExp', 'throw'};

/// `// l10n-ignore(<코드>): <이유>` 에 쓸 수 있는 코드. server-text = 서버 문구와 글자까지 같아야 하는 비교 상수, wire = 서버 식별자.
const Set<String> _markerCodes = {'server-text', 'wire'};

/// 소스에서 찾은 문자열 하나. [text] 에는 보간 `${}` 의 식 코드가 들어 있지 않다(그 안의 문자열은 따로 나온다).
class DartStringLiteral {
  const DartStringLiteral({required this.line, required this.text, required this.calls});

  /// 여는 따옴표가 있는 줄(1부터).
  final int line;
  final String text;

  /// 이 문자열을 감싼 호출 이름들(바깥 → 안). `throw X(...)` 는 `throw` 로 적는다.
  final List<String> calls;

  bool get hasHangul => _hangul.hasMatch(text);

  bool get isDeveloperOnly => calls.any(_developerCalls.contains);
}

List<DartStringLiteral> scanStringLiterals(String source) => _Scanner(source).run().literals;

/// 주석만 공백으로 바꾼 소스(줄 수 · 문자열은 그대로). 식별자가 코드에 실제로 나오는지 볼 때 쓴다.
String stripComments(String source) {
  final comments = _Scanner(source).run().comments;
  final buffer = StringBuffer();
  var from = 0;
  for (final (start, end) in comments) {
    buffer.write(source.substring(from, start));
    buffer.write(source.substring(start, end).replaceAll(RegExp(r'[^\n]'), ' '));
    from = end;
  }
  buffer.write(source.substring(from));
  return buffer.toString();
}

final RegExp _lineMarker = RegExp(r'//\s*l10n-ignore\((\S*?)\):[ \t]*(.*)$');
final RegExp _startMarker = RegExp(r'//\s*l10n-ignore-start\((\S*?)\):[ \t]*(.*)$');
final RegExp _endMarker = RegExp(r'//\s*l10n-ignore-end\b');

/// 한글이 든 문자열 중 아직 ARB 로 안 옮긴 것 — 개발자용 호출 안의 것과 `l10n-ignore` 마커가 면제한 것은 뺀다.
List<DartStringLiteral> unmovedHangulLiterals(String source) {
  final exempt = _exemptLines(_lines(source));
  return [
    for (final literal in scanStringLiterals(source))
      if (literal.hasHangul && !literal.isDeveloperOnly && !exempt.contains(literal.line)) literal,
  ];
}

/// 줄로 나눈다 — 윈도 저장소(CRLF)에서도 줄 끝 `\r` 이 마커 정규식의 `$` 를 막지 않게 `\r\n` 을 한 줄바꿈으로 본다.
List<String> _lines(String source) => source.split(RegExp(r'\r?\n'));

/// 마커가 면제하는 줄 번호들 — 줄 끝 마커는 그 줄, 마커만 있는 줄은 바로 아랫줄, start ~ end 는 그 사이 줄.
Set<int> _exemptLines(List<String> lines) {
  final exempt = <int>{};
  var inBlock = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_startMarker.hasMatch(line)) inBlock = true;
    if (_endMarker.hasMatch(line)) inBlock = false;
    if (inBlock) exempt.add(i + 1);
    if (!_lineMarker.hasMatch(line)) continue;
    exempt.add(line.trimLeft().startsWith('//') ? i + 2 : i + 1);
  }
  return exempt;
}

/// 마커 자체의 문제 — 이유 없음 · 허용 밖 코드 · start/end 짝 · 한글 문자열에 안 붙은 낡은 마커.
List<String> markerProblems(String source) {
  final lines = _lines(source);
  final hangulLines = {
    for (final literal in scanStringLiterals(source))
      if (literal.hasHangul) literal.line,
  };
  final problems = <String>[];
  var blockStart = 0;
  for (var i = 0; i < lines.length; i++) {
    final number = i + 1;
    final marker = _lineMarker.firstMatch(lines[i]) ?? _startMarker.firstMatch(lines[i]);
    if (marker != null && !_markerCodes.contains(marker.group(1))) problems.add('$number: 허용 밖 코드 ${marker.group(1)}');
    if (marker != null && marker.group(2)!.trim().isEmpty) problems.add('$number: 이유가 없다');
    if (_lineMarker.hasMatch(lines[i]) && !hangulLines.contains(_markedLine(lines[i], number))) {
      problems.add('$number: 낡은 마커 — 붙은 줄에 한글 문자열이 없다');
    }
    if (_startMarker.hasMatch(lines[i])) {
      if (blockStart != 0) problems.add('$number: start 안에 start');
      blockStart = number;
    }
    if (_endMarker.hasMatch(lines[i])) {
      if (blockStart == 0) problems.add('$number: start 없는 end');
      if (blockStart != 0 && !hangulLines.any((line) => line > blockStart && line < number)) {
        problems.add('$blockStart: 낡은 마커 — start ~ end 사이에 한글 문자열이 없다');
      }
      blockStart = 0;
    }
  }
  if (blockStart != 0) problems.add('$blockStart: end 가 없다');
  return problems;
}

/// 줄 끝 마커가 면제하는 줄 번호(마커만 있는 줄이면 아랫줄).
int _markedLine(String line, int number) => line.trimLeft().startsWith('//') ? number + 1 : number;

class _Scanned {
  final List<DartStringLiteral> literals = [];
  final List<(int, int)> comments = [];
}

class _Scanner {
  _Scanner(this._src);

  final String _src;
  final _Scanned _result = _Scanned();
  final List<String> _calls = [];
  int _i = 0;
  int _line = 1;

  _Scanned run() {
    _code(inInterpolation: false);
    return _result;
  }

  bool _isIdentifierChar(String char) => RegExp(r'[A-Za-z0-9_$]').hasMatch(char);

  /// 코드 구간을 읽는다. 보간 `${ … }` 안이면 짝이 맞는 `}` 에서 돌아온다.
  void _code({required bool inInterpolation}) {
    var depth = 0;
    while (_i < _src.length) {
      final char = _src[_i];
      if (char == '\n') {
        _line++;
        _i++;
      } else if (_src.startsWith('//', _i)) {
        _skipLineComment();
      } else if (_src.startsWith('/*', _i)) {
        _skipBlockComment();
      } else if (char == "'" || char == '"') {
        _string(raw: _i > 0 && _src[_i - 1] == 'r' && (_i < 2 || !_isIdentifierChar(_src[_i - 2])));
      } else if (char == '(') {
        _calls.add(_callNameBefore());
        _i++;
      } else if (char == ')') {
        if (_calls.isNotEmpty) _calls.removeLast();
        _i++;
      } else if (char == '}' && inInterpolation && depth == 0) {
        _i++;
        return;
      } else {
        if (char == '{') depth++;
        if (char == '}') depth--;
        _i++;
      }
    }
  }

  /// `(` 바로 앞의 이름. `throw Foo(` 이면 `throw`.
  String _callNameBefore() {
    final before = _src.substring(_i > 80 ? _i - 80 : 0, _i);
    if (RegExp(r'\bthrow\s+(?:const\s+)?[A-Za-z_]\w*\s*$').hasMatch(before)) return 'throw';
    return RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(before)?.group(1) ?? '';
  }

  void _skipLineComment() {
    final start = _i;
    while (_i < _src.length && _src[_i] != '\n') {
      _i++;
    }
    _result.comments.add((start, _i));
  }

  /// Dart 블록 주석은 중첩된다.
  void _skipBlockComment() {
    final start = _i;
    var depth = 0;
    do {
      if (_src.startsWith('/*', _i)) {
        depth++;
        _i += 2;
      } else if (_src.startsWith('*/', _i)) {
        depth--;
        _i += 2;
      } else {
        if (_src[_i] == '\n') _line++;
        _i++;
      }
    } while (depth > 0 && _i < _src.length);
    _result.comments.add((start, _i));
  }

  void _string({required bool raw}) {
    final quote = _src[_i];
    final triple = _src.startsWith(quote * 3, _i);
    final startLine = _line;
    final calls = List<String>.of(_calls);
    final text = StringBuffer();
    _i += triple ? 3 : 1;
    while (_i < _src.length) {
      final char = _src[_i];
      if (triple ? _src.startsWith(quote * 3, _i) : char == quote) {
        _i += triple ? 3 : 1;
        break;
      }
      if (!triple && char == '\n') break; // 닫히지 않은 한 줄 문자열 — 깨진 소스는 여기서 멈춘다
      if (!raw && char == r'\' && _i + 1 < _src.length) {
        text.write(_src[_i + 1]);
        if (_src[_i + 1] == '\n') _line++;
        _i += 2;
      } else if (!raw && char == r'$' && _src.startsWith('{', _i + 1)) {
        _i += 2;
        final saved = List<String>.of(_calls);
        _code(inInterpolation: true);
        _calls
          ..clear()
          ..addAll(saved);
      } else if (!raw && char == r'$') {
        _i = RegExp(r'[A-Za-z_]\w*').matchAsPrefix(_src, _i + 1)?.end ?? _i + 1; // $이름 보간 — 이름까지 건너뛴다
      } else {
        if (char == '\n') _line++;
        text.write(char);
        _i++;
      }
    }
    _result.literals.add(DartStringLiteral(line: startLine, text: text.toString(), calls: calls));
  }
}
