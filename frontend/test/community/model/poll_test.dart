import 'package:campus_mate/community/model/poll.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? myChoice, int a = 5, int b = 3, String optionA = '찬성'}) => {
      'id': 'p1',
      'question': '첫 데이트 더치페이',
      'option_a_label': optionA,
      'option_b_label': '반대',
      'created_at': '2026-09-27T05:00:00+00:00',
      'a_count': a,
      'b_count': b,
      'my_choice': myChoice,
      'is_mine': false,
    };

void main() {
  test('서버 칸을 읽는다', () {
    final poll = Poll.fromJson(_json(myChoice: 'b'));
    expect(poll.id, 'p1');
    expect(poll.myChoice, PollChoice.b);
    expect(poll.total, 8);
    expect(poll.createdAt.isUtc, isFalse);
  });

  test('아직 투표 안 했으면 myChoice 는 null', () {
    expect(Poll.fromJson(_json()).myChoice, isNull);
  });

  test('퍼센트는 반올림하고 두 쪽 합이 100 이다', () {
    final poll = Poll.fromJson(_json(a: 2, b: 1));
    expect(poll.aPercent, 67);
    expect(poll.bPercent, 33);
  });

  test('아무도 투표하지 않았으면 0 · 0', () {
    final poll = Poll.fromJson(_json(a: 0, b: 0));
    expect(poll.aPercent, 0);
    expect(poll.bPercent, 0);
  });

  test('라벨이 둘 다 기본값일 때만 O·X 아이콘을 쓴다', () {
    expect(Poll.fromJson(_json()).usesDefaultLabels, isTrue);
    expect(Poll.fromJson(_json(optionA: '짜장')).usesDefaultLabels, isFalse);
  });
}
