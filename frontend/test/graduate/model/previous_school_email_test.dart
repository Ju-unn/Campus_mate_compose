import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 입력은 값 없음(null)', () {
    expect(PreviousSchoolEmail.tryParse(''), isNull);
    expect(PreviousSchoolEmail.tryParse('   '), isNull);
  });

  test('모양이 맞으면 값이 된다 — 도메인은 따지지 않는다', () {
    expect(PreviousSchoolEmail.tryParse('a@b.ac.kr'), isNotNull);
    expect(PreviousSchoolEmail.tryParse('hong+old@univ.edu'), isNotNull);
  });

  test('모양이 틀리면 null', () {
    for (final bad in ['a@', '@b.kr', 'a@b', 'a b@c.kr', 'a@b .kr', 'plain']) {
      expect(PreviousSchoolEmail.tryParse(bad), isNull, reason: bad);
    }
  });

  test('너무 긴 값은 null — 서버 상한 254 와 같다', () {
    final tooLong = '${'a' * 250}@b.kr';

    expect(PreviousSchoolEmail.tryParse(tooLong), isNull);
  });

  test('요청에 실을 값은 앞뒤 공백을 떼고 소문자다', () {
    expect(PreviousSchoolEmail.tryParse('  Hong@Univ.AC.kr ')!.toRequestValue(), 'hong@univ.ac.kr');
  });

  test('같은 값은 같다', () {
    expect(PreviousSchoolEmail.tryParse('a@b.kr'), PreviousSchoolEmail.tryParse(' A@B.kr '));
  });
}
