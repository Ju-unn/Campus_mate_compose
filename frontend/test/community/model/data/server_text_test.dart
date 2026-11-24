import 'package:campus_mate/community/model/data/server_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 visible 과 같은 0폭 문자 다섯만 있는 글은 빈 글이다', () {
    expect(fitsServerText('​‌‍⁠﻿', 10), isFalse);
    expect(fitsServerText(' \n\t ', 10), isFalse);
    expect(fitsServerText('​가', 10), isTrue);
  });

  test('앞뒤 공백을 깎은 뒤 코드 포인트로 잰다', () {
    expect(fitsServerText('  가나  ', 2), isTrue);
    expect(fitsServerText('👍🏻', 1), isFalse);
    expect(fitsServerText('👍🏻', 2), isTrue);
  });
}
