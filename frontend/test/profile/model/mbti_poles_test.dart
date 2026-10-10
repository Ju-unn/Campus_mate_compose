import 'package:campus_mate/profile/model/mbti_poles.dart';
import 'package:flutter_test/flutter_test.dart';

/// 04-1 "내 MBTI" 와 15-6 "내 MBTI" 가 같이 쓰는 축 규칙(축마다 하나만 고른다).
void main() {
  group('toggle', () {
    test('다른 극을 고르면 같은 축의 옛 극이 꺼진다', () {
      expect(MbtiPoles.toggle({'E', 'N'}, 'I'), {'I', 'N'});
    });

    test('켜 둔 극을 다시 누르면 그 축이 비는 대신 다른 축은 그대로다', () {
      expect(MbtiPoles.toggle({'E', 'N'}, 'E'), {'N'});
    });

    test('빈 곳에 고르면 더해진다', () {
      expect(MbtiPoles.toggle(const {}, 'T'), {'T'});
    });
  });

  group('code · fromCode', () {
    test('네 축을 다 고르면 E/I N/S T/F J/P 순서의 네 글자다', () {
      expect(MbtiPoles.code({'P', 'F', 'N', 'E'}), 'ENFP');
    });

    test('하나라도 비면 null 이다', () {
      expect(MbtiPoles.code({'E', 'N', 'F'}), isNull);
    });

    test('네 글자를 극으로 푼다 — null 은 빈 집합', () {
      expect(MbtiPoles.fromCode('INTJ'), {'I', 'N', 'T', 'J'});
      expect(MbtiPoles.fromCode(null), isEmpty);
    });

    test('isComplete 는 네 축이 다 찼는지', () {
      expect(MbtiPoles.isComplete({'E', 'N', 'F', 'P'}), isTrue);
      expect(MbtiPoles.isComplete({'E', 'N', 'F'}), isFalse);
    });
  });
}
