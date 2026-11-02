import 'package:campus_mate/core/analytics/api_route_pattern.dart';

/// 앱이 버틴 API 오류(서버 5xx · 연결 실패 · 시간 초과) 한 건. 오류 수집(Crashlytics)에 **비치명**으로 보낸다.
///
/// 담는 것은 **오류 종류 · 상태 코드 · 요청 경로 패턴** 셋뿐이다. 예외 메시지 · 응답 본문 · 쿼리 문자열 · 값이 채워진 id 는
/// 만들 때 버려지므로 이 클래스를 거치면 새어 나갈 길이 없다(`CrashReporter.recordHandledError` 가 이 타입만 받는다).
class HandledApiError implements Exception {
  const HandledApiError._({required this.kind, required this.route, this.status});

  /// 연결 실패 · 시간 초과 등 예외로 끝난 요청. [error] 에서는 **타입 이름만** 쓴다.
  factory HandledApiError.fromException(Object error, Uri url) =>
      HandledApiError._(kind: _typeName(error), route: ApiRoutePattern.of(url));

  /// 서버가 5xx 로 답한 요청.
  factory HandledApiError.fromStatus(int status, Uri url) =>
      HandledApiError._(kind: serverErrorKind, status: status, route: ApiRoutePattern.of(url));

  /// 5xx 응답에는 예외가 없어 종류를 이 이름으로 둔다.
  static const String serverErrorKind = 'ServerError';

  /// 타입 이름의 길이 상한. Crashlytics 제목이 한 줄에 들어가게 짧게 둔다.
  static const int _maxKindLength = 40;

  static final RegExp _outsideName = RegExp(r'[^A-Za-z0-9_]');

  /// 예외 타입 이름(`SocketException`) 또는 [serverErrorKind].
  final String kind;

  /// 서버가 준 상태 코드. 예외로 끝나 응답이 없으면 null.
  final int? status;

  /// 요청 경로 패턴(`/chat/matches/:id/messages`) — [ApiRoutePattern].
  final String route;

  /// 같은 오류를 같은 것으로 세는 열쇠(`HandledErrorReporter` 가 폭주를 막는 데 쓴다).
  String get key => '$kind|${status ?? 0}|$route';

  @override
  String toString() => 'HandledApiError(kind: $kind, status: ${status ?? '-'}, route: $route)';

  /// `_Odd<List<int>>` 같은 이름에서 꺾쇠 · 공백 따위를 빼고 [_maxKindLength] 자로 자른다.
  static String _typeName(Object error) {
    final name = error.runtimeType.toString().replaceAll(_outsideName, '');
    if (name.isEmpty) return 'Unknown';
    return name.length <= _maxKindLength ? name : name.substring(0, _maxKindLength);
  }
}
