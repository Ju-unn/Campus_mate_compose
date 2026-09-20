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

/// 학생증 사진에서 얼굴을 찾지 못한 경우(기기 안 ML Kit 판단, 설계 §7.3).
final class NoFaceDetectedFailure extends Failure {
  const NoFaceDetectedFailure();

  @override
  String toDisplayMessage() => '얼굴이 보이는 사진으로 다시 올려주세요';
}

/// 학생증 인증 서버가 거부한 경우(예: 검토 중 재제출). 서버 메시지를 그대로 보여준다.
final class ServerRejectedFailure extends Failure {
  const ServerRejectedFailure(this._message);

  final String _message;

  @override
  String toDisplayMessage() => _message;
}
