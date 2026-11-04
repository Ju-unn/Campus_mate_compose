import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(StudentNumber.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(StudentNumber.tryParse(' 21 ')!.toRequestValue(), '21');
  });

  // 서버 `student_verification/schemas.py` 의 `[0-9]{1,3}` 과 같은 규칙(10-29 사용자 결정).
  test('반각 숫자 1~3자리를 받는다', () {
    expect(StudentNumber.tryParse('1')!.toRequestValue(), '1');
    expect(StudentNumber.tryParse('21')!.toRequestValue(), '21');
    expect(StudentNumber.tryParse('123')!.toRequestValue(), '123');
  });

  test('4자리 이상이면 null', () {
    expect(StudentNumber.tryParse('1234'), isNull);
    expect(StudentNumber.tryParse('1' * 21), isNull);
  });

  test('숫자가 아닌 글자가 섞이면 null', () {
    expect(StudentNumber.tryParse('abc'), isNull);
    expect(StudentNumber.tryParse('2a'), isNull);
    expect(StudentNumber.tryParse('2 1'), isNull);
  });

  test('전각 숫자는 null — 서버가 [0-9] 로만 받는다', () {
    expect(StudentNumber.tryParse('２１'), isNull);
  });
}
