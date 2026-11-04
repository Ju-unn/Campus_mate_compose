import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 글자 크기는 `lib/core/theme/app_typography.dart` 의 토큰 한 곳에서만 정한다(2026-11-03 사용자 결정 —
/// 기준 48 · 32 · 24 · 20 · 18 · 16 · 14 · 12 · 10, 모두 짝수). 화면 코드에 `fontSize: 숫자` 를 다시 쓰면 기준 밖 크기가
/// 조용히 늘어난다 — 토큰 + `copyWith(fontWeight: …, height: …)` 로 쓴다.
void main() {
  // 파일 경로(`lib/` 기준) → 예외 이유. 이유 없이 더하지 않는다.
  const exceptions = <String, String>{
    'auth/social/view/social_login_button.dart': '카카오 · 구글 공식 버튼 글자 — 카카오 가이드 "레이블은 버튼 높이의 1/3 이하"(46/3 ≈ 15.3 이하라 15), 구글은 Roboto Medium 14/20 이고 둘 다 앱 글꼴(Pretendard)이 아니다',
  };

  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.path.replaceAll(r'\', '/').substring('lib/'.length))
      .where((path) => !path.startsWith('core/theme/'))
      .toList()
    ..sort();

  final fontSizeNamedArgument = RegExp(r'\bfontSize\s*:');
  // 줄 주석은 줄 맨 앞이나 공백 뒤의 `//` 부터다 — 문자열 주소(`'https://…'`)의 `//` 는 주석이 아니다.
  final lineComment = RegExp(r'(^|\s)//.*');

  bool usesFontSizeArgument(String line) => fontSizeNamedArgument.hasMatch(line.replaceFirst(lineComment, ''));

  List<String> offendingLines(String path) {
    final lines = File('lib/$path').readAsLinesSync();
    return [
      for (var i = 0; i < lines.length; i++)
        if (usesFontSizeArgument(lines[i])) '$path:${i + 1}: ${lines[i].trim()}',
    ];
  }

  test('줄 주석 안의 `fontSize:` 는 세지 않고, 문자열 주소(`https://`) 뒤의 `fontSize:` 는 센다', () {
    expect(usesFontSizeArgument('    fontSize: 12,'), isTrue);
    expect(usesFontSizeArgument('    // fontSize: 12 는 옛 값'), isFalse);
    expect(usesFontSizeArgument('    /// `fontSize: 12` 로 쓰지 않는다'), isFalse);
    expect(usesFontSizeArgument('    final style = base; // fontSize: 12'), isFalse);
    expect(usesFontSizeArgument("    final url = 'https://x.y'; final s = TextStyle(fontSize: 12);"), isTrue);
  });

  test('lib/core/theme 밖에는 `fontSize:` 가 없다 — 예외 파일은 이유와 함께 이 시험에 적는다', () {
    final offenders = [
      for (final path in libFiles)
        if (!exceptions.containsKey(path)) ...offendingLines(path),
    ];

    expect(offenders, isEmpty, reason: 'AppTypography 토큰을 쓰고 굵기 · 줄높이만 copyWith 로 덮어쓴다:\n${offenders.join('\n')}');
  });

  test('예외 파일은 실제로 `fontSize:` 를 쓰고 있다 — 쓰지 않게 되면 예외에서 뺀다', () {
    for (final path in exceptions.keys) {
      expect(File('lib/$path').existsSync(), isTrue, reason: '$path 가 없다');
      expect(offendingLines(path), isNotEmpty, reason: '$path 는 더 이상 예외가 아니다');
    }
  });
}
