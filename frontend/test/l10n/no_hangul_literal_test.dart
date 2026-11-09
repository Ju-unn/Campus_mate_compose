import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 화면 문구는 `lib/l10n/app_ko.arb` 한 곳에서만 정한다(1.0.2 B8, 2026-11-04). `lib/` 에 한글 문자열 리터럴을 다시 쓰면
/// 문구가 조용히 두 곳이 된다 — 이 시험이 잡는다.
///
/// 예외는 경로 목록이 아니라 **코드 옆 마커**다(폴더 이동이 계속되므로 경로를 키로 쓰면 이동마다 깨진다):
/// `// l10n-ignore(server-text): 이유` · `// l10n-ignore(wire): 이유`(줄 끝 또는 바로 윗줄), 여러 줄은
/// `// l10n-ignore-start(wire): 이유` ~ `// l10n-ignore-end`. 로그(`debugPrint`) · `assert` · `throw` · `RegExp` 안의 글자는 마커 없이 면제다.
void main() {
  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더). 생성 폴더 `lib/l10n/` 은 검사하지 않는다.
  // 1.0.2 B8 묶음 ⑧-b 로 모든 화면 문구를 옮겨 예외 폴더 목록은 없다 — lib 전체가 같은 규칙이다.
  final libFiles = {
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart')) file.path.replaceAll(r'\', '/').substring('lib/'.length): file,
  }..removeWhere((path, _) => path.startsWith('l10n/'));

  String sourceOf(String path) => libFiles[path]!.readAsStringSync();

  test('lib 전체의 문자열에는 한글이 없다 — 문구는 ARB, 서버 식별자 · 서버 문구 비교는 마커', () {
    final offenders = [
      for (final path in libFiles.keys)
        for (final literal in unmovedHangulLiterals(sourceOf(path))) '$path:${literal.line}: ${literal.text}',
    ];

    expect(
      offenders,
      isEmpty,
      reason: '화면 문구는 lib/l10n/app_ko.arb 로 옮기고 context.l10n 으로 읽는다. 서버와 글자까지 같아야 하는 값이면 '
          '`// l10n-ignore(wire|server-text): 이유` 마커를 단다:\n${offenders.join('\n')}',
    );
  });

  test('l10n-ignore 마커는 이유가 있고, 허용된 코드이며, 짝이 맞고, 실제 한글 문자열에 붙어 있다', () {
    final problems = [
      for (final path in libFiles.keys)
        for (final problem in markerProblems(sourceOf(path))) '$path: $problem',
    ];

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
