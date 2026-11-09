import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 앱 코드는 한국어 문구 클래스(`AppLocalizationsKo`)를 직접 만들지 않는다 — 문구는 위임자를 거쳐 `context.l10n` ·
/// `context.errorText` 로만 읽는다(1.0.2 B8 ⑧-c, 사용자 결정 「B안으로 조이기」 2026-11-09). 직접 만들면 위임자를 빠뜨려도
/// 한국어가 나와, 지운 한국어 대체(`l10n_context.dart` 의 `_koreanFallback`)가 다른 이름으로 돌아온다. 시험 코드는 대상이 아니다.
void main() {
  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더). 생성 폴더 `lib/l10n/` 은 읽지 않는다.
  final libFiles = [
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !file.path.replaceAll(r'\', '/').startsWith('lib/l10n/')) file,
  ];

  test('lib(생성 폴더 lib/l10n/ 제외)은 AppLocalizationsKo 를 직접 만들지 않는다 — 생성자 · 생성자 떼어 쓰기 · lookupAppLocalizations', () {
    final direct = RegExp(r'\bAppLocalizationsKo\s*\(|\bAppLocalizationsKo\.new\b|\blookupAppLocalizations\s*\(');
    final calls = [
      for (final file in libFiles)
        if (direct.hasMatch(stripComments(file.readAsStringSync())))
          file.path.replaceAll(r'\', '/'),
    ];

    expect(libFiles, isNotEmpty);
    expect(calls, isEmpty, reason: '화면 문구는 context.l10n, 에러 문구는 context.errorText 로 읽는다: $calls');
  });
}
