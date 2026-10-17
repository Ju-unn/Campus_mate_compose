/// 도메인 실패를 표현한다.
/// 실패의 내부 사정을 노출하지 않고, 사용자에게 보여줄 문구만 제공한다.
sealed class Failure {
  const Failure();

  /// 화면에 표시할 한국어 안내 문구를 돌려준다.
  String toDisplayMessage();
}

/// 네트워크 연결 자체가 실패한 경우.
final class NetworkFailure extends Failure {
  const NetworkFailure();

  @override
  String toDisplayMessage() {
    return '네트워크 연결을 확인해 주세요';
  }
}

/// 로그인 세션이 없거나 만료된 경우. FastAPI 401 과 같은 문구를 쓴다.
final class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure();

  @override
  String toDisplayMessage() {
    return '세션이 만료됐어요, 다시 로그인해 주세요';
  }
}

/// 서버가 이 로그인을 받지 않는다(401, 탈퇴 표시 없음 — 계정 삭제 · 다른 곳에서 세션을 끊음). 토큰을 새로 받지
/// 못했거나 새 토큰으로도 401 이었다. 원래 세션이 없던 [SessionExpiredFailure] 와 달리 아직 로그인 상태라
/// 로그인 화면으로 보낸다(A11) — 로그아웃 직후 늦게 나간 요청이 만료 알림을 띄우지 않게 둘을 가른다.
final class SessionRejectedFailure extends SessionExpiredFailure {
  const SessionRejectedFailure();
}

/// 요청한 리소스가 존재하지 않는 경우.
final class NotFoundFailure extends Failure {
  const NotFoundFailure();

  @override
  String toDisplayMessage() {
    return '요청한 정보를 찾을 수 없습니다';
  }
}

/// 위 어느 경우에도 해당하지 않는 예기치 못한 실패.
final class UnknownFailure extends Failure {
  const UnknownFailure();

  @override
  String toDisplayMessage() {
    return '알 수 없는 오류가 발생했습니다';
  }
}

/// 서버가 잠깐 요청을 못 받는 경우(502·503 — 배포 중이거나 뒤쪽 작업 큐 등록이 실패함).
/// 앱 쪽 잘못이 아니라서 다시 시도하면 되는 일이다(DEPLOY §4-2 와 같은 문구, 2026-09-26 사용자 결정).
final class ServerUnavailableFailure extends Failure {
  const ServerUnavailableFailure();

  @override
  String toDisplayMessage() => '잠시 뒤 다시 시도해 주세요';
}

/// 시간당 재전송·요청 한도에 걸린 경우.
final class RateLimitedFailure extends Failure {
  const RateLimitedFailure();

  @override
  String toDisplayMessage() {
    return '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요';
  }
}

/// Auth Hook이 도메인 화이트리스트·재가입 제한으로 가입을 거부한 경우.
/// 서버가 돌려준 문구를 그대로 보여준다(내부 사정을 새로 지어내지 않는다).
final class SignUpRejectedFailure extends Failure {
  const SignUpRejectedFailure(this._message);

  final String _message;

  @override
  String toDisplayMessage() => _message;
}

/// 인증코드가 틀렸거나 만료된 경우(pen `Vn6w4` 오류 문구).
final class WrongCodeFailure extends Failure {
  const WrongCodeFailure();

  @override
  String toDisplayMessage() => '코드가 맞지 않아요. 다시 확인해 주세요.';
}

/// 서버가 4xx 로 거부한 경우(예: 관문 미통과 403). 서버 메시지를 그대로 보여준다.
/// 서버가 기계용 `code` 를 함께 주면(POST /school-email/verify 등) 그것도 들고 있다 — 문구 대신 code 로 가를 수 있게.
final class ServerRejectedFailure extends Failure {
  // Dart 3.13 private named parameter: 호출부는 code: 로 넘긴다
  const ServerRejectedFailure(this._message, {this._code});

  final String _message;
  final String? _code;

  @override
  String toDisplayMessage() => _message;

  /// 서버가 이 code 를 실어 보냈는지.
  bool hasCode(String code) => _code == code;

  /// code 칸이 있었는지. 없으면 옛 서버라 문구로 가른다.
  bool hasAnyCode() => _code != null;
}

/// 정지된 계정(403 + `X-Account-Status: suspended`). 서버 `errors.py` ACCOUNT_SUSPENDED 와 같은 글자.
final class SuspendedFailure extends Failure {
  const SuspendedFailure();

  @override
  String toDisplayMessage() => '이용이 제한된 계정이에요';
}

/// 탈퇴한 계정(401 + `X-Account-Status: withdrawn`). 서버 `errors.py` ACCOUNT_WITHDRAWN 과 같은 글자.
final class WithdrawnFailure extends Failure {
  const WithdrawnFailure();

  @override
  String toDisplayMessage() => '탈퇴한 계정이에요';
}

/// 학교 메일(02)로 인증번호를 보내지 못한 경우. 한도(429) · 가입 거절(422) 말고는 원인을 가르지 않는다 —
/// GoTrue 가 다른 실패를 어떤 코드로 주는지 확실하지 않아서다.
final class CodeNotSentFailure extends Failure {
  const CodeNotSentFailure();

  // 임시 문구, 디자인 확정 대기
  @override
  String toDisplayMessage() => '인증번호를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요';
}

/// 학교 메일 인증(03)을 끝내지 못한 경우 — 503 · 네트워크 · 서버 내부 오류. 사용자가 할 일은 잠시 뒤 다시다.
final class SchoolEmailIncompleteFailure extends Failure {
  const SchoolEmailIncompleteFailure();

  // 임시 문구, 디자인 확정 대기
  @override
  String toDisplayMessage() => '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요';
}

/// 서버가 임시 토큰을 학교 메일 인증으로 읽지 못했다(403 SCHOOL_EMAIL_NOT_CONFIRMED). 문구는 [SchoolEmailIncompleteFailure]
/// 와 같지만, 다른 학교 메일로 다시 시작하는 길("다른 학교 메일 입력")을 함께 보여 줘서 따로 둔다.
final class SchoolEmailNotConfirmedFailure extends Failure {
  const SchoolEmailNotConfirmedFailure();

  // 임시 문구, 디자인 확정 대기
  @override
  String toDisplayMessage() => '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요';
}

/// 입력한 학교 메일이 지금 로그인한 소셜 계정의 메일과 같다(02, 보내기 전에 앱이 막는다). 그대로 보내면 GoTrue 가
/// 임시 계정을 만들지 않고 그 소셜 계정으로 로그인시켜 서버가 403 SCHOOL_EMAIL_NOT_CONFIRMED 로 거절한다.
final class SchoolEmailSameAsLoginFailure extends Failure {
  const SchoolEmailSameAsLoginFailure();

  // 임시 문구, 디자인 확정 대기
  @override
  String toDisplayMessage() => '로그인에 쓰는 구글·카카오 계정과 같은 메일은 쓸 수 없어요. 다른 학교 메일을 입력해 주세요';
}

/// 등록되지 않은 학교 메일 · 재가입 제한(POST /school-email/verify 422). 문구는 서버가 내려 준 것을 그대로 쓴다.
final class SchoolEmailRejectedFailure extends Failure {
  const SchoolEmailRejectedFailure(this._serverMessage);

  final String _serverMessage;

  @override
  String toDisplayMessage() => _serverMessage;
}

/// 이 학교 메일을 다른 계정이 이미 인증했다(POST /school-email/verify 409).
/// 문구가 아니라 서버가 함께 주는 기계용 `provider`(쥔 계정의 가입 방식)로 가른다. 모르는 값이면 서버 문구를 그대로 쓴다.
/// [myProvider] 는 지금 로그인한 소셜(`auth.currentUser.appMetadata['provider']`)이다 — 같으면 "그 소셜로 로그인하라" 가
/// 틀린 안내라(이미 그 소셜로 로그인 중) 빌려 쓰기 문구로 바꾼다(설계 5-3 · 5-4, 10-17 학생증 제거 B안).
/// 서버 문구(`errors.py` "이 메일은 {provider}로 가입돼 있어요")는 옛 앱이 읽으므로 바꾸지 않고 앱이 새 문구를 정한다.
final class SchoolEmailTakenFailure extends Failure {
  // Dart 3.13 private named parameter: 호출부는 myProvider: 로 넘긴다
  const SchoolEmailTakenFailure(this._serverMessage, this._provider, {this._myProvider});

  final String _serverMessage;
  final String _provider;
  final String? _myProvider;

  static const _providerLabels = <String, String>{'kakao': '카카오', 'google': '구글', 'apple': '애플'};

  /// `provider == email` — 소셜이 아닌 이메일 방식 계정이 이 메일을 쥐고 있다(서버 `SCHOOL_EMAIL_TAKEN_BY_EMAIL_ACCOUNT` 와 같은 글자).
  static const _emailAccountProvider = 'email';
  static const takenByEmailAccountMessage = '이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요';

  /// [myProvider] 를 붙인 사본 — 서버 응답(http_send)에는 내 소셜이 없어 저장소가 덧붙인다.
  SchoolEmailTakenFailure withMyProvider(String? myProvider) =>
      SchoolEmailTakenFailure(_serverMessage, _provider, myProvider: myProvider);

  /// 소셜(카카오 · 구글 · 애플) 계정이 쥐었는가 — 03 오류 변형(코드 칸 없이 안내 두 줄 + 단추)을 그린다.
  bool isTakenBySocial() => _providerLabels.containsKey(_provider);

  bool get _isMine => _provider == _myProvider;

  /// 다른 소셜이 쥐었을 때만 그 소셜 이름. 같은 소셜 · 이메일 방식 · 모르는 수단이면 null.
  String? get _otherSocialLabel => _isMine ? null : _providerLabels[_provider];

  @override
  String toDisplayMessage() {
    if (_provider == _emailAccountProvider) {
      return takenByEmailAccountMessage;
    }
    if (!isTakenBySocial()) {
      return _serverMessage;
    }
    final label = _otherSocialLabel;
    return label == null ? '이미 가입된 학교 메일이에요' : '이미 $label로 가입된 학교 메일이에요';
  }

  /// 오류 첫 줄 아래 둘째 줄. 소셜이 쥔 메일이 아니면 없다.
  String? toHintMessage() {
    if (!isTakenBySocial()) {
      return null;
    }
    final label = _otherSocialLabel;
    return label == null ? '한 학교 메일로는 계정 하나만 만들 수 있어요' : '$label로 로그인해 주세요';
  }

  /// 03 주 단추 글자("카카오로 다시 로그인"). 다른 소셜이 쥐었을 때만 있다.
  String? reloginLabel() {
    final label = _otherSocialLabel;
    return label == null ? null : '$label로 다시 로그인';
  }

  /// 다시 로그인 단추를 눌러 로그아웃한 뒤 시작 화면 토스트(`LoginNotice`)에 남길 문구.
  String? reloginNotice() {
    final label = _otherSocialLabel;
    return label == null ? null : '이 학교 메일은 $label로 가입돼 있어요. $label로 로그인해 주세요';
  }
}

/// 사용자가 소셜 로그인 창을 닫거나 취소한 경우(시작 화면 토스트, 대장 지시문 07).
final class LoginCancelledFailure extends Failure {
  const LoginCancelledFailure();

  @override
  String toDisplayMessage() => '로그인이 취소됐어요';
}

/// 소셜 로그인이 취소 말고 다른 이유(네트워크 · 키 없음 · ID 토큰 없음 · Supabase 거절)로 끝난 경우.
/// 사유는 사용자에게 나누어 보이지 않는다(대장 지시문 07).
final class SocialLoginFailure extends Failure {
  const SocialLoginFailure();

  @override
  String toDisplayMessage() => '로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요';
}
