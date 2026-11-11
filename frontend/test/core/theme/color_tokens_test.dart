import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 색은 `lib/core/theme/` 의 토큰(AppColors · AppElevation) 한 곳에서만 정한다(1.0.2 계획 B2).
/// 화면 코드에 `Color(0x…)` 를 쓰거나 `Colors.black.withValues(...)` 로 투명도를 계산하면 같은 값이 여러 곳에
/// 흩어지고 기준 밖 색이 조용히 늘어난다 — 토큰을 쓰고, 없으면 토큰에 더한다.
void main() {
  // 파일 경로(`lib/` 기준) → 예외 이유. 이유 없이 더하지 않는다.
  const exceptions = <String, String>{};

  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더). 생성 폴더 `l10n/` 은 뺀다.
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.path.replaceAll(r'\', '/').substring('lib/'.length))
      .where((path) => !path.startsWith('core/theme/') && !path.startsWith('l10n/'))
      .toList()
    ..sort();

  final colorLiteral = RegExp(r'\bColor\(\s*0x|\bColor\.from(ARGB|RGBO)\(');
  final colorsOpacity = RegExp(r'(?<![A-Za-z0-9_])Colors\.[A-Za-z]+(\.shade\d+)?\.with(Values|Opacity|Alpha)\b');
  // 줄 주석은 줄 맨 앞이나 공백 뒤의 `//` 부터다 — 문자열 주소(`'https://…'`)의 `//` 는 주석이 아니다.
  final lineComment = RegExp(r'(^|\s)//.*');

  bool usesRawColor(String line) {
    final code = line.replaceFirst(lineComment, '');
    return colorLiteral.hasMatch(code) || colorsOpacity.hasMatch(code);
  }

  List<String> offendingLines(String path) {
    final lines = File('lib/$path').readAsLinesSync();
    return [
      for (var i = 0; i < lines.length; i++)
        if (usesRawColor(lines[i])) '$path:${i + 1}: ${lines[i].trim()}',
    ];
  }

  test('줄 주석 안의 색은 세지 않고, 토큰 위의 `.withValues` 는 세지 않는다', () {
    expect(usesRawColor('  static const c = Color(0xFF222222);'), isTrue);
    expect(usesRawColor('  final c = Color.fromARGB(255, 0, 0, 0);'), isTrue);
    expect(usesRawColor('  color: Colors.black.withValues(alpha: 0.6),'), isTrue);
    expect(usesRawColor('  color: Colors.red.shade100.withOpacity(0.5),'), isTrue);
    expect(usesRawColor('  // pen 값은 Color(0xFF222222) 다'), isFalse);
    expect(usesRawColor('  color: AppColors.canvas.withValues(alpha: 0.8),'), isFalse);
    expect(usesRawColor('  color: AppColors.photoBadge,'), isFalse);
  });

  test('lib/core/theme 밖에는 `Color(0x…)` 와 `Colors.<이름>.withValues` 가 없다 — 예외 파일은 이유와 함께 이 시험에 적는다', () {
    final offenders = [
      for (final path in libFiles)
        if (!exceptions.containsKey(path)) ...offendingLines(path),
    ];

    expect(offenders, isEmpty, reason: 'AppColors · AppElevation 토큰을 쓴다(없으면 값이 같은 토큰을 core/theme 에 더한다):\n${offenders.join('\n')}');
  });

  test('예외 파일은 실제로 색 리터럴을 쓰고 있다 — 쓰지 않게 되면 예외에서 뺀다', () {
    for (final path in exceptions.keys) {
      expect(File('lib/$path').existsSync(), isTrue, reason: '$path 가 없다');
      expect(offendingLines(path), isNotEmpty, reason: '$path 는 더 이상 예외가 아니다');
    }
  });
}
