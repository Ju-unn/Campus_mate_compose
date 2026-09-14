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
