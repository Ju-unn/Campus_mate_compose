import 'package:campus_mate/auth/model/department.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(Department.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(Department.tryParse(' 컴퓨터공학과 ')!.toRequestValue(), '컴퓨터공학과');
  });

  test('30자를 넘으면 null', () {
    expect(Department.tryParse('가' * 31), isNull);
  });
}
