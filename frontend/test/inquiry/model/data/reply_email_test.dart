import 'package:campus_mate/inquiry/model/data/reply_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  prefillTests();

  group('isValidReplyEmail — 서버 REPLY_EMAIL(reasons.py)과 같은 모양', () {
    test('흔한 주소는 통과한다', () {
      for (final email in ['hello@example.com', 'a.b+c@mail.school.ac.kr', 'x@y.z']) {
        expect(isValidReplyEmail(email), isTrue, reason: email);
      }
    });

    test('앞뒤 공백은 서버처럼 잘라서 본다', () {
      expect(isValidReplyEmail('  hello@example.com \n'), isTrue);
    });

    test('골뱅이나 점이 없거나 비어 있으면 막는다', () {
      for (final email in ['', 'hello', 'hello@', '@example.com', 'hello@example', 'hello@.com', 'a@b@c.com']) {
        expect(isValidReplyEmail(email), isFalse, reason: email);
      }
    });

    test('가운데 공백 · 쉼표 · 꺾쇠 · 따옴표 · 한글은 막는다 — Reply-To 에 주소가 둘 이상 들어가지 않게', () {
      for (final email in ['a b@example.com', 'a@exa mple.com', 'a@b.com,c@d.com', 'a@b.com;c@d.com', 'Name <a@b.com>', 'a"b@c.com', '메일@example.com']) {
        expect(isValidReplyEmail(email), isFalse, reason: email);
      }
    });

    test('앞부분과 도메인에 쉼표 · 세미콜론 · 꺾쇠가 있으면 막는다', () {
      for (final email in ['a,b@c.com', 'a;b@c.com', '<a>@c.com', 'a@b,c.com', 'a@b;c.d']) {
        expect(isValidReplyEmail(email), isFalse, reason: email);
      }
    });

    test('254자까지는 되고 255자부터는 막는다', () {
      final local = 'a' * (254 - '@b.co'.length);
      expect(isValidReplyEmail('$local@b.co'), isTrue);
      expect(isValidReplyEmail('a$local@b.co'), isFalse);
    });
  });
}

void prefillTests() {
  group('prefillReplyEmail — 계정 메일을 칸에 미리 채울지', () {
    test('모양이 맞는 계정 메일은 그대로 채운다', () {
      expect(prefillReplyEmail('me@gmail.com'), 'me@gmail.com');
    });

    test('없거나 비었거나 모양이 틀리면 채우지 않는다', () {
      expect(prefillReplyEmail(null), isNull);
      expect(prefillReplyEmail(''), isNull);
      expect(prefillReplyEmail('이상한값'), isNull);
    });

    test('애플 가림 주소는 운영팀 답장이 전달되지 않을 수 있어 채우지 않는다', () {
      expect(prefillReplyEmail('abc123@privaterelay.appleid.com'), isNull);
    });
  });
}
