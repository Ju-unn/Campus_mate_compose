import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(StudentNumber.tryParse(''), isNull);
    expect(StudentNumber.tryParse(' '), isNull);
    expect(StudentNumber.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(StudentNumber.tryParse(' 21 ')!.toRequestValue(), '21');
    expect(StudentNumber.tryParse('21 ')!.toRequestValue(), '21');
  });

  // 앱은 2자리(학부 입학 연도 끝 두 자리, 할 일 #9 A안). 서버는 옛 앱 호환으로 아직 1~3자리를 받는다.
  test('반각 숫자 2자리를 받는다', () {
    expect(StudentNumber.tryParse('21')!.toRequestValue(), '21');
    expect(StudentNumber.tryParse('05')!.toRequestValue(), '05');
  });

  test('1자리 · 3자리면 null', () {
    expect(StudentNumber.tryParse('1'), isNull);
    expect(StudentNumber.tryParse('123'), isNull);
  });

  test('4자리 이상이면 null', () {
    expect(StudentNumber.tryParse('1234'), isNull);
    expect(StudentNumber.tryParse('1' * 21), isNull);
  });

  test('숫자가 아닌 글자가 섞이면 null', () {
    expect(StudentNumber.tryParse('ab'), isNull);
    expect(StudentNumber.tryParse('2a'), isNull);
    expect(StudentNumber.tryParse('2 1'), isNull);
  });

  test('전각 숫자는 null — 서버가 [0-9] 로만 받는다', () {
    expect(StudentNumber.tryParse('２１'), isNull);
  });
}
