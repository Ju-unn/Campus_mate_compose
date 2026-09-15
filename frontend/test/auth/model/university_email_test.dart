import 'package:campus_mate/auth/model/university_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UniversityEmail.tryParse', () {
    test('형식이 올바른 이메일은 인스턴스를 만든다', () {
      final email = UniversityEmail.tryParse('student@snu.ac.kr');

      expect(email, isNotNull);
      expect(email!.toRequestValue(), 'student@snu.ac.kr');
    });

    test('앞뒤 공백을 지우고 소문자로 정규화한다', () {
      final email = UniversityEmail.tryParse('  Student@SNU.ac.kr  ');

      expect(email!.toRequestValue(), 'student@snu.ac.kr');
    });

    test('@ 가 없으면 null 이다', () {
      expect(UniversityEmail.tryParse('student.snu.ac.kr'), isNull);
    });

    test('도메인에 점이 없으면 null 이다', () {
      expect(UniversityEmail.tryParse('student@snu'), isNull);
    });

    test('공백을 포함하면 null 이다', () {
      expect(UniversityEmail.tryParse('student @snu.ac.kr'), isNull);
    });

    test('빈 문자열은 null 이다', () {
      expect(UniversityEmail.tryParse(''), isNull);
    });

    // 학교 도메인 화이트리스트 대조(university_email_domains)는 서버(FastAPI Auth Hook)
    // 몫이다 — 여기서는 일반적인 이메일 형식만 검증한다 (ERD.md §3, 대장 결정 2026-09-15).
  });

  test('같은 문자열이면 동등하다', () {
    final a = UniversityEmail.tryParse('student@snu.ac.kr');
    final b = UniversityEmail.tryParse('STUDENT@snu.ac.kr');

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });
}
