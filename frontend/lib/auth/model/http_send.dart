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

/// 4xx(429 제외) 만 여기로 온다. `detail` 이 있으면 서버 메시지를 그대로 보여주고,
/// 없으면 내부 사정을 새로 지어내지 않고 [UnknownFailure] 로 처리한다.
Failure _toRejection(http.Response response) {
  final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'] as String?;
  if (detail == null) {
    return const UnknownFailure();
  }
  return ServerRejectedFailure(detail);
}
