import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 시험의 `MaterialApp` · `MaterialApp.router` 는 앱(`lib/main.dart`)과 같은 문구 위임자를 단다(1.0.2 B8 ⑧-c, 사용자 결정
/// 「B안으로 조이기」 2026-11-09): `localizationsDelegates: AppLocalizations.localizationsDelegates` ·
/// `supportedLocales: AppLocalizations.supportedLocales`. 위임자가 없으면 `context.l10n` 은 바로 실패하지만(`nullable-getter: false`),
/// 문구를 안 쓰는 위젯은 머티리얼 영어 기본 글자(뒤로 버튼 툴팁 'Back' 등)로 조용히 돌아 앱에 없는 글자를 단언하게 된다 — 이 시험이 잡는다.
/// `CupertinoApp` · `WidgetsApp` 도 같은 규칙이다(지금 쓰는 곳은 없다).
void main() {
  final appCall = RegExp(r'\b(?:MaterialApp|CupertinoApp|WidgetsApp)(?:\.router)?\s*\(');
  final delegates = RegExp(r'\blocalizationsDelegates:\s*AppLocalizations\.localizationsDelegates\b');
  final locales = RegExp(r'\bsupportedLocales:\s*AppLocalizations\.supportedLocales\b');
  // 위임자를 일부러 빼거나 바꿔 끼우는 시험(위임자가 없을 때의 동작을 보는 곳).
  const deliberatelyWithout = {'test/core/l10n/l10n_context_test.dart'};
  // 한 줄 문자열을 비운다 — 시험 이름에 'MaterialApp(…)' 이 들어가도 호출로 세지 않게.
  // shortcut: 여러 줄 문자열 · 보간 속 따옴표는 못 비운다, 그런 곳에 MaterialApp( 이 생기면 dart_literals 분리기가 문자열 구간을 내게 바꾼다.
  final oneLineString = RegExp(r''''(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"''');

  /// [open] 의 `(` 와 짝이 맞는 `)` 까지(인자 목록).
  String argumentsFrom(String code, int open) {
    var depth = 0;
    for (var i = open; i < code.length; i++) {
      if (code[i] == '(') depth++;
      if (code[i] == ')' && --depth == 0) return code.substring(open, i + 1);
    }
    return code.substring(open);
  }

  /// 맨 위 인자만 남긴다 — 안쪽 괄호 · 대괄호 · 중괄호 속은 버려, 안쪽 MaterialApp 의 위임자를 바깥 것으로 세지 않게.
  String topLevel(String arguments) {
    final buffer = StringBuffer();
    var depth = 0;
    for (final char in arguments.split('')) {
      if ('([{'.contains(char)) depth++;
      if (depth == 1) buffer.write(char);
      if (')]}'.contains(char)) depth--;
    }
    return buffer.toString();
  }

  List<({String path, String where, String arguments})> callsIn(String path, String source) {
    final code = stripComments(source).replaceAll(oneLineString, "''");
    return [
      for (final match in appCall.allMatches(code))
        (
          path: path,
          where: '$path:${'\n'.allMatches(code.substring(0, match.start)).length + 1}',
          arguments: topLevel(argumentsFrom(code, match.end - 1)),
        ),
    ];
  }

  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
  final calls = [
    for (final file in Directory('test').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart')) ...callsIn(file.path.replaceAll(r'\', '/'), file.readAsStringSync()),
  ];
  final missing = [
    for (final call in calls)
      if (!delegates.hasMatch(call.arguments) || !locales.hasMatch(call.arguments)) call,
  ];

  test('시험이 빈 껍데기가 아니다 — 시험 폴더에서 MaterialApp 호출을 찾는다', () {
    expect(calls.length, greaterThan(100));
  });

  test('시험의 MaterialApp · MaterialApp.router 는 앱과 같은 문구 위임자 · 지원 언어를 단다', () {
    final offenders = [
      for (final call in missing)
        if (!deliberatelyWithout.contains(call.path)) call.where,
    ];

    expect(
      offenders,
      isEmpty,
      reason: '앱(lib/main.dart)처럼 맨 위 인자로 `localizationsDelegates: AppLocalizations.localizationsDelegates, '
          'supportedLocales: AppLocalizations.supportedLocales,` 를 단다:\n${offenders.join('\n')}',
    );
  });

  test('일부러 빼는 시험 목록은 낡지 않았다 — 목록의 파일마다 위임자 없는 호출이 실제로 있다', () {
    expect(deliberatelyWithout.difference({for (final call in missing) call.path}), isEmpty);
  });
}
