import 'package:campus_mate/auth/school_info/model/data/department.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../common/input_rules_cases.dart';

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

  // 서버 `is_valid_department` 와 같은 표 — 앱이 받고 서버가 거절하면 3c 에서 "다음" 이 켜진 채 막힌다.
  for (final department in inputRuleCases('department', 'reject')) {
    test('서버가 거절하는 ${Uri.encodeComponent(department)} 는 null', () {
      expect(Department.tryParse(department), isNull);
    });
  }

  for (final department in inputRuleCases('department', 'accept')) {
    test('서버가 받는 $department 는 값이 있다', () {
      expect(Department.tryParse(department)?.toRequestValue(), department);
    });
  }
}
