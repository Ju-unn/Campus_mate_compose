import 'package:campus_mate/auth/school_info/model/data/academic_status.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카드 계열 응답의 상대 프로필(1.0.7 1-1 신분 배지 재료).
void main() {
  CardProfile read(Map<String, Object?> extra) => CardProfile.fromJson({'nickname': '여우비', 'age': 23, ...extra});

  test('academic_status 를 읽는다 — null 이거나 키가 없으면(옛 서버) null 이라 배지는 "학교 인증"', () {
    expect(read({'academic_status': 'graduate_student'}).academicStatus, AcademicStatus.graduateStudent);
    expect(read({'academic_status': null}).academicStatus, isNull);
    expect(read(const {}).academicStatus, isNull);
  });
}
