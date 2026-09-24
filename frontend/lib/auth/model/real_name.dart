/// 한글 완성형·영문·띄어쓰기만 허용한다(2026-09-24 사용자 결정).
/// 숫자·기호(`-` `.` `'`)·자모만 있는 글자(ㄱ, ㅏ)는 학생증에 그대로 적혀 있지 않아 OCR 대조가 어긋난다.
/// 외국인 이름은 "Jun seok" 처럼 띄어 쓴다. 서버 student_verification/router.py 의 검사와 같은 규칙이다.
final _allowedCharacters = RegExp(r'^[가-힣a-zA-Z ]+$');

/// 학생증 사진과 대조할 실명 값 객체(설계 §7.3, `profile_private.real_name`).
final class RealName {
  RealName._(this._value);

  final String _value;

  static RealName? tryParse(String raw) {
    final normalized = raw.trim();
    // 서버 student_verification/schemas.py·router.py 의 Form(min_length=2, max_length=30) 과 하한·상한을 맞춘다
    // (2026-09-20 분석담당 리뷰 제안 1 — 1글자 실명은 OCR 부분문자열 대조를 사실상 무력화한다).
    if (normalized.length < 2 || normalized.length > 30) {
      return null;
    }
    if (!_allowedCharacters.hasMatch(normalized)) {
      return null;
    }
    return RealName._(normalized);
  }

  /// 입력 도중 안내 문구를 띄울지 가르는 자리 — 길이는 보지 않고 글자만 본다.
  /// 두 글자를 채우기 전은 아직 입력 중일 뿐이라 잘못됐다고 말하지 않는다.
  static bool hasDisallowedCharacter(String raw) {
    final normalized = raw.trim();
    return normalized.isNotEmpty && !_allowedCharacters.hasMatch(normalized);
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is RealName && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
