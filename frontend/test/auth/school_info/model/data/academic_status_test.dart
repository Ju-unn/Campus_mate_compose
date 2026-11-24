import 'package:campus_mate/auth/school_info/model/data/academic_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// 신분(1.0.7 1-1) — 서버 `academic_status` 문자열과 그대로 오간다.
void main() {
  test('세 값의 서버 문자열', () {
    expect({for (final status in AcademicStatus.values) status: status.wire}, {
      AcademicStatus.undergraduate: 'undergraduate',
      AcademicStatus.graduateStudent: 'graduate_student',
      AcademicStatus.alumni: 'alumni',
    });
  });

  test('서버 문자열을 읽는다 — null 은 아직 안 고름, 모르는 값도 null 이라 배지가 "학교 인증" 으로 남는다', () {
    expect(AcademicStatus.tryParse('graduate_student'), AcademicStatus.graduateStudent);
    expect(AcademicStatus.tryParse(null), isNull);
    expect(AcademicStatus.tryParse('professor'), isNull);
  });
}
