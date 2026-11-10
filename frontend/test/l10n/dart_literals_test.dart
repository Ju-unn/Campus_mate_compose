import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 지킴 시험(`no_hangul_literal_test` · `arb_test`)이 쓰는 Dart 소스 분리기를 지킨다.
/// 줄 단위 정규식은 꼬리 주석 · 여러 줄 문자열 · `${}` 안의 문자열에서 틀리므로 분리기를 따로 두고, 그 분리기가 틀리지 않는지 여기서 본다.
void main() {
  List<String> texts(String source) => [for (final literal in scanStringLiterals(source)) literal.text];

  group('문자열 리터럴 뽑기', () {
    test('홑따옴표 · 쌍따옴표 문자열을 시작 줄 번호와 함께 뽑는다', () {
      final found = scanStringLiterals("final a = 'a';\nfinal b = \"나\";\n");

      expect([for (final f in found) (f.line, f.text)], [(1, 'a'), (2, '나')]);
    });

    test('줄 주석 · 문서 주석 · 중첩 블록 주석 안의 따옴표는 문자열이 아니다', () {
      const source = '''
// 가 'a'
/// 나 "b"
/* 다 'c' /* 라 'd' */ 마 'e' */
final f = 'x';
''';

      expect(texts(source), ['x']);
    });

    test('문자열 안의 // 는 주석이 아니다 — 그 뒤 문자열도 뽑힌다', () {
      expect(texts("final u = 'https://가.com'; final v = '나';"), ['https://가.com', '나']);
    });

    test('이스케이프한 따옴표는 문자열을 끝내지 않고 raw 문자열은 역슬래시를 그대로 둔다', () {
      expect(texts(r"final a = 'it\'s 가'; final b = r'\d가';"), ["it's 가", r'\d가']);
    });

    test('보간 \${} 안의 문자열은 따로 뽑히고 바깥 문자열에는 식 코드가 섞이지 않는다', () {
      final found = texts(r'''final a = '가 ${ok ? '나' : "다"} $name 라';''');

      expect(found, containsAll(['나', '다']));
      expect(found, contains('가   라'));
    });

    test('삼중 따옴표는 여러 줄을 한 문자열로 읽고 시작 줄을 기록한다', () {
      final found = scanStringLiterals("var x = 1;\nfinal a = '''가\n나''';\nfinal b = 'c';\n");

      expect([for (final f in found) (f.line, f.text)], [(2, '가\n나'), (4, 'c')]);
    });
  });

  group('한글 포함 여부와 개발자용 호출', () {
    bool hangul(String source) => scanStringLiterals(source).single.hasHangul;

    test('완성형 한글 · 자모가 있으면 한글이다, 영문 · 숫자 · 기호만이면 아니다', () {
      expect(hangul("final a = '가';"), isTrue);
      expect(hangul("final a = 'ㅋㅋ';"), isTrue);
      expect(hangul("final a = 'Abc 123 !';"), isFalse);
    });

    test('debugPrint · assert · throw · RegExp 안의 문자열은 개발자용이다', () {
      for (final source in [
        "debugPrint('가');",
        "assert(ok, '가');",
        "throw FormatException('가');",
        "throw const StateError('가');",
        r"final r = RegExp(r'가+');",
        "debugPrint('가 \${items.map((i) => 'x')}');",
      ]) {
        expect(scanStringLiterals(source).first.isDeveloperOnly, isTrue, reason: source);
      }
    });

    test('화면 문구를 만드는 호출 안의 문자열은 개발자용이 아니다', () {
      for (final source in ["Text('가');", "final a = '가';", "showToast(label('가'));", "foo(throwLater: '가');"]) {
        expect(scanStringLiterals(source).single.isDeveloperOnly, isFalse, reason: source);
      }
    });
  });

  group('l10n-ignore 마커', () {
    List<int> flagged(String source) => [for (final f in unmovedHangulLiterals(source)) f.line];

    test('마커가 없으면 한글 문자열은 모두 옮길 대상이다', () {
      expect(flagged("final a = '가';\nfinal b = '나';"), [1, 2]);
    });

    test('줄 끝 마커는 그 줄만, 윗줄 마커는 바로 아래 줄만 면제한다', () {
      const source = '''
final a = '가'; // l10n-ignore(wire): 서버 식별자
// l10n-ignore(server-text): 서버 errors.py 와 글자까지 같아야 함
final b = '나';
final c = '다';
''';

      expect(flagged(source), [4]);
    });

    test('윈도 줄바꿈(CRLF)으로 저장된 소스에서도 마커가 그대로 듣는다', () {
      const source = "final a = '가'; // l10n-ignore(wire): 서버 식별자\r\n"
          '// l10n-ignore(server-text): 서버 문구와 같아야 함\r\n'
          "final b = '나';\r\n"
          "final c = '다';\r\n";

      expect(flagged(source), [4]);
      expect(markerProblems(source), isEmpty);
    });

    test('start ~ end 마커는 그 사이 줄을 모두 면제한다', () {
      const source = '''
// l10n-ignore-start(wire): 서버 tags.py 와 완전히 같은 글자
const tags = [
  '가',
  '나',
];
// l10n-ignore-end
final c = '다';
''';

      expect(flagged(source), [7]);
    });

    test('마커 문제 — 이유가 비었거나 코드가 허용 밖이거나 짝이 없거나 한글 문자열에 안 붙은 마커', () {
      expect(markerProblems("final a = '가'; // l10n-ignore(wire):"), hasLength(1), reason: '이유 없음');
      expect(markerProblems("final a = '가'; // l10n-ignore(whatever): 이유"), hasLength(1), reason: '코드 밖');
      expect(markerProblems('// l10n-ignore-start(wire): 이유\nfinal a = 1;'), isNotEmpty, reason: 'end 없음');
      expect(markerProblems('// l10n-ignore-end'), isNotEmpty, reason: 'start 없음');
      expect(markerProblems("final a = 'abc'; // l10n-ignore(wire): 한글이 없다"), hasLength(1), reason: '낡은 마커');
      expect(markerProblems("final a = '가'; // l10n-ignore(wire): 서버 식별자"), isEmpty);
    });
  });

  group('주석 걷어내기', () {
    test('코드와 문자열은 두고 주석만 공백으로 바꾸며 줄 수는 그대로다', () {
      const source = "final a = errorFoo; // errorBar\n/* errorBaz\n*/ final b = 'errorQux';\n";

      final stripped = stripComments(source);

      expect(stripped, contains('errorFoo'));
      expect(stripped, contains("'errorQux'"));
      expect(stripped, isNot(contains('errorBar')));
      expect(stripped, isNot(contains('errorBaz')));
      expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
    });
  });
}
