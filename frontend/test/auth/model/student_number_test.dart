import 'package:campus_mate/auth/model/student_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(StudentNumber.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(StudentNumber.tryParse(' 21 ')!.toRequestValue(), '21');
  });

  test('20자를 넘으면 null', () {
    expect(StudentNumber.tryParse('1' * 21), isNull);
  });
}
