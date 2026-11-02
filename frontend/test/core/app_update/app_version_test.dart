import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

AppVersion version(String text) => AppVersion.tryParse(text)!;

void main() {
  group('tryParse', () {
    test('숫자.숫자.숫자 는 읽는다', () {
      expect(AppVersion.tryParse('1.0.1'), isNotNull);
      expect(AppVersion.tryParse('12.345.6789'), isNotNull);
    });

    test('형식이 다르면 null — 막지 않는 쪽으로 떨어지게', () {
      const malformed = [
        '',
        ' ',
        '1',
        '1.0',
        '1.0.1.2',
        'v1.0.1',
        '1.0.1+19',
        '1.0.x',
        '1..1',
        '-1.0.1',
        ' 1.0.1',
        '1.0.1\n',
        // 64비트 정수를 넘는 숫자 — int.parse 가 던지는 자리다.
        '99999999999999999999.0.0',
      ];
      for (final text in malformed) {
        expect(AppVersion.tryParse(text), isNull, reason: '"$text"');
      }
    });
  });

  group('isOlderThan', () {
    test('1.0.9 는 1.0.10 보다 낮다 — 글자가 아니라 숫자로 비교한다', () {
      expect(version('1.0.9').isOlderThan(version('1.0.10')), isTrue);
      expect(version('1.0.10').isOlderThan(version('1.0.9')), isFalse);
    });

    test('같은 버전은 낮지 않다', () {
      expect(version('1.0.1').isOlderThan(version('1.0.1')), isFalse);
    });

    test('앞자리가 먼저 이긴다', () {
      expect(version('1.99.99').isOlderThan(version('2.0.0')), isTrue);
      expect(version('1.0.99').isOlderThan(version('1.1.0')), isTrue);
      expect(version('2.0.0').isOlderThan(version('1.99.99')), isFalse);
    });

    test('앞에 0 이 붙어도 같은 숫자다', () {
      expect(version('1.01.1').isOlderThan(version('1.1.1')), isFalse);
    });
  });

  test('같은 숫자의 버전은 같은 값이다', () {
    expect(version('1.0.1'), version('1.0.1'));
    expect(version('1.0.1').hashCode, version('1.0.1').hashCode);
    expect(version('1.0.1'), isNot(version('1.0.2')));
  });
}
