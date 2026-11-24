/// 신분(1.0.7 1-1, 사용자 「대학생 · 대학원생 · 졸업생」). [wire] 는 서버 `academic_status` 문자열 그대로다.
/// 아직 고르지 않은 것(null)은 값이 아니라 "없음" 이다 — 배지는 그때 지금처럼 "학교 인증" 을 쓴다.
enum AcademicStatus {
  undergraduate('undergraduate'),
  graduateStudent('graduate_student'),
  alumni('alumni');

  const AcademicStatus(this.wire);

  final String wire;

  /// 모르는 값 · 없는 값은 null — 서버가 값을 더해도 옛 앱이 죽지 않고 "학교 인증" 으로 보인다.
  static AcademicStatus? tryParse(Object? wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }
}
