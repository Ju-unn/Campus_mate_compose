import 'package:campus_mate/community/model/data/poll.dart';
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

  test('앞뒤 떼기는 InputText 와 같다 — U+001C 는 떼고 U+FEFF 는 남긴다', () {
    expect(fitsServerText('\u001C가\u001F', 1), isTrue);
    expect(fitsServerText('가﻿', 1), isFalse);
    expect(fitsServerText('가﻿', 2), isTrue);
  });

  test('서버에 보내는 글은 서버가 잰 글과 같게 앞뒤만 뗀다', () {
    expect(serverStripped('\u001C 가 나 \u001F'), '가 나');
    expect(serverStripped('가﻿ '), '가﻿');
  });

  test('두 보기가 같은지는 서버처럼 앞뒤를 뗀 값으로 본다', () {
    expect(pollOptionsAccepted('가\u001C', '가'), isFalse);
    expect(pollOptionsAccepted('가﻿', '가'), isTrue);
  });
}
