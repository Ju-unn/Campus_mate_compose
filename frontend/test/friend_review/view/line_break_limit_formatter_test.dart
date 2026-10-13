import 'package:campus_mate/friend_review/view/line_break_limit_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 줄 바꿈 상한(최대 3줄 = 줄 바꿈 2개). 엔터 한 번은 막고, 붙여넣기의 넘는 줄 바꿈은 공백으로 바꾼다.
void main() {
  final formatter = lineBreakLimitFormatter(3);

  TextEditingValue apply(String oldText, String newText, {int? cursor}) {
    return formatter.formatEditUpdate(
      TextEditingValue(text: oldText, selection: TextSelection.collapsed(offset: oldText.length)),
      TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: cursor ?? newText.length)),
    );
  }

  group('엔터 한 번', () {
    test('줄 바꿈이 2개가 될 때까지는 들어간다', () {
      expect(apply('가', '가\n').text, '가\n');
      expect(apply('가\n나', '가\n나\n').text, '가\n나\n');
    });

    test('3번째 줄 바꿈(4번째 줄)은 무시하고 글·커서는 그대로다', () {
      final old = TextEditingValue(text: '가\n나\n다', selection: const TextSelection.collapsed(offset: 5));
      final result = formatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '가\n나\n다\n', selection: TextSelection.collapsed(offset: 6)),
      );
      expect(result, old);
    });

    test('글 중간에서 엔터를 쳐도 이미 3줄이면 무시한다', () {
      const old = TextEditingValue(text: '가나\n다\n라', selection: TextSelection.collapsed(offset: 1));
      final result = formatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '가\n나\n다\n라', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(result, old);
    });

    test('줄 바꿈이 이미 2개여도 글자를 치는 건 막지 않는다', () {
      expect(apply('가\n나\n', '가\n나\n다').text, '가\n나\n다');
    });

    test('줄 바꿈만 3개 이어 쳐도 4번째 줄은 안 된다(빈 줄도 줄이다)', () {
      expect(apply('\n\n', '\n\n\n').text, '\n\n');
    });
  });

  group('붙여넣기', () {
    test('줄 바꿈 3개가 든 글은 앞 2개만 남기고 나머지는 공백으로 바꾼다 — 글은 잃지 않는다', () {
      expect(apply('', '가\n나\n다\n라').text, '가\n나\n다 라');
    });

    test('연속 줄 바꿈도 센다', () {
      expect(apply('', '가\n\n\n\n나').text, '가\n\n  나');
    });

    test('맨 앞 줄 바꿈도 줄로 센다', () {
      expect(apply('', '\n\n\n가').text, '\n\n 가');
    });

    test('맨 뒤 줄 바꿈이 넘쳐도 공백이 된다(보낼 때 trim 이 지운다)', () {
      expect(apply('', '가\n나\n다\n').text, '가\n나\n다 ');
    });

    test('Windows 줄 끝(\\r\\n)은 \\n 하나로 줄인다 — 2줄 글이 그대로 들어간다', () {
      expect(apply('', '가\r\n나\r\n다').text, '가\n나\n다');
    });

    test('\\r\\n 이 많은 글도 앞 2개만 남긴다', () {
      expect(apply('', '가\r\n나\r\n다\r\n라').text, '가\n나\n다 라');
    });

    test('낱개 \\r 도 줄 바꿈 하나로 본다', () {
      expect(apply('', '가\r나').text, '가\n나');
    });

    test('이미 1줄 있는 글에 줄 바꿈 2개 든 글을 붙이면 합쳐서 2개까지만 남는다', () {
      expect(apply('가\n', '가\n나\n다\n라').text, '가\n나\n다 라');
    });

    test('줄 바꿈이 없으면 그대로 둔다', () {
      final value = apply('', '가나다');
      expect(value.text, '가나다');
      expect(value.selection, const TextSelection.collapsed(offset: 3));
    });

    test('커서는 바뀐 글 안에서 같은 자리를 가리킨다(\\r\\n 이 줄어든 만큼 당겨진다)', () {
      final value = apply('', '가\r\n나', cursor: 4);
      expect(value.text, '가\n나');
      expect(value.selection, const TextSelection.collapsed(offset: 3));
    });
  });

  group('3줄 상한은 인자다', () {
    test('1줄이면 줄 바꿈을 못 넣는다', () {
      expect(lineBreakLimitFormatter(1).formatEditUpdate(
        const TextEditingValue(text: '가', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(text: '가\n', selection: TextSelection.collapsed(offset: 2)),
      ).text, '가');
    });
  });
}
