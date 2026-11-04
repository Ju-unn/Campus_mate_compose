import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 에러 문구는 같은 ARB 파일 안에서 키가 `error` 로 시작하고(사용자 결정 「1」 2026-11-04), 글자로 바꾸는 곳은
/// `lib/core/l10n/error_text.dart` 한 파일뿐이다(뷰모델은 `Failure` 종류만 낸다). 어느 쪽으로 새도 시험이 잡는다:
///  - 에러 키를 error_text.dart 밖에서 쓰면 — 일반 코드가 에러 문구를 따로 고르고 있다는 뜻
///  - error_text.dart 가 에러가 아닌 키를 쓰면 — 에러 자리를 일반 문구로 채우는 길이 열렸다는 뜻
void main() {
  const errorTextPath = 'core/l10n/error_text.dart';

  final arb = jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync()) as Map<String, dynamic>;
  final messageKeys = arb.keys.where((key) => !key.startsWith('@')).toSet();
  final errorKeys = messageKeys.where((key) => key.startsWith('error')).toSet();
  final generalKeys = messageKeys.difference(errorKeys);

  // 파일(lib/ 기준) → 코드에 나온 식별자(주석 제외). 생성 폴더 lib/l10n/ 은 빼고 읽는다.
  final identifiersByFile = {
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !file.path.replaceAll(r'\', '/').startsWith('lib/l10n/'))
        file.path.replaceAll(r'\', '/').substring('lib/'.length): {
          ...RegExp(r'[A-Za-z_]\w*').allMatches(stripComments(file.readAsStringSync())).map((m) => m.group(0)!),
        },
  };

  test('시험이 빈 껍데기가 아니다 — 에러 키도 일반 키도 있고 error_text.dart 가 있다', () {
    expect(errorKeys, isNotEmpty);
    expect(generalKeys, isNotEmpty);
    expect(identifiersByFile.containsKey(errorTextPath), isTrue);
  });

  test('error 로 시작하는 키는 error_text.dart 밖에서 쓰이지 않는다', () {
    final leaks = [
      for (final entry in identifiersByFile.entries)
        if (entry.key != errorTextPath) ...errorKeys.intersection(entry.value).map((key) => '${entry.key}: $key'),
    ];

    expect(leaks, isEmpty, reason: '에러 문구는 context.errorText(Failure) / context.appErrorText(AppError) 로만 읽는다:\n${leaks.join('\n')}');
  });

  test('error_text.dart 는 error 로 시작하지 않는 키를 쓰지 않는다', () {
    final used = generalKeys.intersection(identifiersByFile[errorTextPath]!);

    expect(used, isEmpty, reason: '에러 자리를 채우는 문구의 키는 error 로 시작해야 한다: $used');
  });

  test('error 키는 하나도 빠짐없이 error_text.dart 에서 쓰인다', () {
    final unused = errorKeys.difference(identifiersByFile[errorTextPath]!);

    expect(unused, isEmpty, reason: 'error_text.dart 가 아직 쓰지 않는 에러 문구: $unused');
  });
}
