import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 화면 문구는 `lib/l10n/app_ko.arb` 한 곳에서만 정한다(1.0.2 B8, 2026-11-04). 옮긴 폴더에 한글 문자열 리터럴을 다시 쓰면
/// 문구가 조용히 두 곳이 된다 — 이 시험이 잡는다.
///
/// 예외는 경로 목록이 아니라 **코드 옆 마커**다(폴더 이동이 계속되므로 경로를 키로 쓰면 이동마다 깨진다):
/// `// l10n-ignore(server-text): 이유` · `// l10n-ignore(wire): 이유`(줄 끝 또는 바로 윗줄), 여러 줄은
/// `// l10n-ignore-start(wire): 이유` ~ `// l10n-ignore-end`. 로그(`debugPrint`) · `assert` · `throw` · `RegExp` 안의 글자는 마커 없이 면제다.
void main() {
  // 아직 안 옮긴 폴더(`lib/` 기준). 기능 하나를 옮기는 PR 이 자기 이름을 지운다 — 마지막 PR 에서 비면 `lib/` 전체가 엄격해진다.
  // `common/` 바로 아래 파일(failure.dart 등)은 이미 옮겼으므로 여기 없다. auth · billing · profile 은 B7 2단계(#660)에서 세부 기능
  // 폴더로 나뉘어 세부 기능마다 적었다 — 한글이 이미 없는 auth/gate · auth/media 는 처음부터 엄격하게 검사된다.
  const pending = <String>{};

  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더). 생성 폴더 `lib/l10n/` 은 검사하지 않는다.
  final libFiles = {
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart')) file.path.replaceAll(r'\', '/').substring('lib/'.length): file,
  }..removeWhere((path, _) => path.startsWith('l10n/'));

  bool isPending(String path) => pending.any((folder) => path.startsWith('$folder/'));

  String sourceOf(String path) => libFiles[path]!.readAsStringSync();

  test('아직 안 옮긴 폴더 이름이 모두 실제로 있다 — 이름이 바뀌었으면 이 목록을 고친다', () {
    for (final folder in pending) {
      expect(Directory('lib/$folder').existsSync(), isTrue, reason: 'lib/$folder 가 없다');
    }
  });

  test('아직 안 옮긴 폴더에는 실제로 옮길 한글 문자열이 남아 있다 — 다 옮겼으면 목록에서 뺀다', () {
    for (final folder in pending) {
      final remaining = [
        for (final path in libFiles.keys.where((path) => path.startsWith('$folder/')))
          ...unmovedHangulLiterals(sourceOf(path)),
      ];
      expect(remaining, isNotEmpty, reason: '$folder 는 다 옮겼다 — pending 에서 뺀다');
    }
  });

  test('옮긴 곳(lib 전체 − pending)의 문자열에는 한글이 없다 — 문구는 ARB, 서버 식별자 · 서버 문구 비교는 마커', () {
    final offenders = [
      for (final path in libFiles.keys.where((path) => !isPending(path)))
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
