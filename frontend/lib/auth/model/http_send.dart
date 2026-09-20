import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:http/http.dart' as http;

/// 인증 관련 HTTP Repository(A5·A6·A7)가 공유하는 요청-전송·상태코드 분류.
/// 네트워크 예외(연결 실패)와 비정상 응답 바디(파싱 실패)를 모두 [Failure] 로 감싸
/// [Result] 를 벗어나 예외가 그대로 튀는 일이 없게 한다.
Future<Result<http.Response>> sendHttpRequest(http.Client client, http.BaseRequest request) async {
  try {
    final response = await http.Response.fromStream(await client.send(request));
    return _classify(response);
  } on Exception catch (_) {
    return const FailureResult(NetworkFailure());
  }
}

Result<http.Response> _classify(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return Success(response);
  }
  if (response.statusCode == 429) {
    return const FailureResult(RateLimitedFailure());
  }
  if (response.statusCode >= 500) {
    return const FailureResult(UnknownFailure());
  }
  return FailureResult(_toRejection(response));
}

/// 4xx(429 제외) 만 여기로 온다. `detail` 이 문자열이면 서버 메시지를 그대로 보여주고,
/// 없거나 다른 모양이면 내부 사정을 새로 지어내지 않고 [UnknownFailure] 로 처리한다.
///
/// FastAPI 422(검증 실패)는 `detail` 이 문자열이 아니라 오류 목록(`List`)이다 — 이때 `as String?` 캐스트가
/// 던지는 `TypeError`는 `Exception` 이 아니라서 [sendHttpRequest] 의 `on Exception catch` 를 뚫고 앱을
/// 그대로 죽였다(2026-09-20 분석담당 리뷰). `is` 검사로 모양이 다르면 조용히 [UnknownFailure] 로 떨어뜨린다.
Failure _toRejection(http.Response response) {
  final body = jsonDecode(response.body);
  if (body is! Map<String, dynamic>) {
    return const UnknownFailure();
  }
  final detail = body['detail'];
  if (detail is! String) {
    return const UnknownFailure();
  }
  return ServerRejectedFailure(detail);
}
