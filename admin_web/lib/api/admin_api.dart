import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:http/http.dart' as http;

/// 서버 403 본문의 이유(설계서 §6-3). D0 확정 모양(대장 전달 10-18): `{"detail": "not_admin"}` · `{"detail": "mfa_required"}`
/// — `code` 칸 없이 detail 이 바로 이유 문자열이다. 401 의 detail 은 한국어 문구라 이유로 쓰지 않는다.
abstract final class AdminReason {
  static const String notAdmin = 'not_admin';
  static const String mfaRequired = 'mfa_required';
}

/// 응답 한 벌. [statusCode] 가 null 이면 연결 실패 · 시간 초과다.
class AdminApiResponse {
  const AdminApiResponse({this.statusCode, this.body, this.reason});

  final int? statusCode;

  /// JSON 으로 읽은 본문. 비었거나 JSON 이 아니면 null.
  final Object? body;

  /// 본문 `detail` 이 문자열이면 그 값. 403 에서만 [AdminReason] 으로 비교한다.
  final String? reason;

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// 관리자 서버(`/admin/*`)를 부르는 얇은 클라이언트. 앱 ApiClient 를 줄여 옮겼다(import 하지 않는다).
/// 실패를 예외로 던지지 않고 [AdminApiResponse] 로 돌려준다 — 화면이 로딩에서 멈추지 않게.
class AdminApi {
  AdminApi(String baseUrl, this._client, this._accessToken) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  final String _baseUrl;
  final http.Client _client;
  final String? Function() _accessToken;

  /// 끝내 오지 않는 조회를 끊는 시간(앱 http_send.dart 의 readTimeout 과 같은 값). 쓰기는 끊지 않는다 —
  /// 끊었다 다시 보내면 같은 조치가 두 번 갈 수 있다.
  static const Duration readTimeout = Duration(seconds: 15);

  Future<AdminApiResponse> me() => send('GET', '/admin/me');

  // 인증샷 검수(A3) — 실패는 [AdminApiFailure] 로 던진다(409 는 [AlreadyReviewed]). 화면 상태는 컨트롤러가 정한다.

  /// 대기 건 요약(오래된 순 · 최대 50). 사진 · 지난 제출은 없다 — 줄을 고르면 [getHeartTask].
  Future<List<HeartTaskItem>> listHeartTasks({HeartTaskKind? task}) {
    return _read(send('GET', '/admin/heart-tasks', query: task == null ? null : {'task': task.code}), (body) {
      if (body case {'items': final List<Object?> items}) return [for (final row in items) HeartTaskItem.fromJson(row)];
      throw const FormatException('인증샷 목록의 모양이 아니에요');
    });
  }

  /// 한 건 — 5분 서명 사진 · 지난 제출. 디스코드 링크로 열 때와 서명이 만료돼 사진을 다시 받을 때도 쓴다.
  Future<HeartTaskDetail> getHeartTask(String id) async {
    return _read(send('GET', _heartTaskPath(id)), HeartTaskDetail.fromJson);
  }

  /// 응답 본문(처리 뒤 한 건)은 읽지 않는다 — 처리는 이미 됐는데 모양이 틀려 실패로 보이면 다시 누르게 된다.
  Future<void> approveHeartTask(String id) async {
    return _read(send('POST', '${_heartTaskPath(id)}/approve'), (_) {});
  }

  Future<void> rejectHeartTask(String id, HeartTaskRejectReason reason) async {
    return _read(send('POST', '${_heartTaskPath(id)}/reject', body: {'reason': reason.code}), (_) {});
  }

  // 신고 검수(A4) — 409 already_done 도 [AlreadyReviewed](이미 처리됨)로 던진다. 사유 · 메모는 앞뒤 공백만 떼고 그대로 보낸다.

  /// 오래된 순 · 최대 50(서버 기본). 사본 · 사진 · 신고자 수는 없다 — 줄을 고르면 [getReport].
  Future<List<ReportSummary>> listReports({ReportStatus status = ReportStatus.open, ReportTargetType? type}) {
    final query = {'status': status.code, if (type != null) 'type': type.code};
    return _read(send('GET', '/admin/reports', query: query), (body) {
      if (body case {'items': final List<Object?> items}) return [for (final row in items) ReportSummary.fromJson(row)];
      throw const FormatException('신고 목록의 모양이 아니에요');
    });
  }

  /// 한 건 — 사본(실사진은 5분 서명) · 글 상태 · 신고자 수 · 같은 대상의 다른 신고. 디스코드 링크로 열 때도 쓴다.
  Future<ReportDetail> getReport(String id) async {
    return _read(send('GET', _idPath('/admin/reports', id)), ReportDetail.fromJson);
  }

  /// 조치 완료 / 기각. [sameTarget] 이면 같은 사람의 다른 열린 신고도 같은 결과로 닫는다. 응답 본문은 읽지 않는다(W1 과 같은 이유).
  Future<void> resolveReport(String id, ReportStatus outcome, {String? note, bool sameTarget = false}) async {
    final memo = note?.trim();
    final body = {'outcome': outcome.code, 'note': memo == null || memo.isEmpty ? null : memo, 'same_target': sameTarget};
    return _read(send('POST', '${_idPath('/admin/reports', id)}/resolve', body: body), (_) {});
  }

  /// 신고된 채팅 앞뒤(메시지 신고만, 사유 필수). 서버가 열람을 먼저 기록한다 — 끊었다 다시 보내지 않게 쓰기처럼 시간 제한이 없다.
  Future<List<ChatLine>> chatContext(String id, String reason) async {
    return _read(send('POST', '${_idPath('/admin/reports', id)}/chat-context', body: {'reason': reason.trim()}), (body) {
      if (body case {'messages': final List<Object?> lines}) return [for (final line in lines) ChatLine.fromJson(line)];
      throw const FormatException('채팅 앞뒤의 모양이 아니에요');
    });
  }

  /// 정지 · 정지 해제 · 자동 가림 해제(그 사람의 열린 신고도 서버가 기각한다)
  Future<void> actOnProfile(String profileId, ProfileAction action, String reason) async {
    final path = '${_idPath('/admin/profiles', profileId)}/${action.name}';
    return _read(send('POST', path, body: {'reason': reason.trim()}), (_) {});
  }

  /// 투표 글 · 지인 리뷰 가림([blind]) / 해제
  Future<void> setContentStatus(ReportTargetType kind, String contentId, {required bool blind, required String reason}) async {
    final segment = kind == ReportTargetType.poll ? 'polls' : 'friend-reviews';
    final path = '${_idPath('/admin/content/$segment', contentId)}/${blind ? 'blind' : 'unblind'}';
    return _read(send('POST', path, body: {'reason': reason.trim()}), (_) {});
  }

  // 사용자(A5) · 결제(A8) — 서버 계약은 D3 계획서 표 그대로. 학교 메일 · 주문 번호는 POST 본문으로만 보낸다(주소 · 쿼리에 남기지 않음).

  /// 가입 최근 순 · 최대 50(서버 기본). [q] 는 닉네임 일부 또는 프로필 id.
  Future<List<UserSummary>> listUsers({String? q}) {
    final text = q?.trim();
    return _read(send('GET', '/admin/users', query: text == null || text.isEmpty ? null : {'q': text}), _userRows);
  }

  /// 학교 메일 정확히 일치(0 또는 1줄). 메일은 본문에만 — 서버도 기록하지 않는다.
  Future<List<UserSummary>> searchUsersBySchoolEmail(String email) {
    return _read(send('POST', '/admin/users/search', body: {'school_email': email.trim()}), _userRows);
  }

  static List<UserSummary> _userRows(Object? body) {
    if (body case {'items': final List<Object?> items}) return [for (final row in items) UserSummary.fromJson(row)];
    throw const FormatException('사용자 목록의 모양이 아니에요');
  }

  Future<UserDetail> getUser(String id) async {
    return _read(send('GET', _idPath('/admin/users', id)), UserDetail.fromJson);
  }

  /// 메모(작업 기록 한 줄). 응답 본문은 읽지 않는다 — 저장은 됐는데 모양이 틀려 실패로 보이면 두 번 남는다.
  Future<void> addUserNote(String id, String text) async {
    return _read(send('POST', '${_idPath('/admin/users', id)}/notes', body: {'text': text.trim()}), (_) {});
  }

  /// 하트 조정(+ 더하기 · − 빼기). 잔액이 모자라면 409 `insufficient_hearts`, 탈퇴 계정은 409 `account_withdrawn`.
  Future<void> adjustHearts(String id, int amount, String reason) async {
    return _read(send('POST', '${_idPath('/admin/users', id)}/hearts', body: {'amount': amount, 'reason': reason.trim()}), (_) {});
  }

  /// 전화 · 카톡 열람 — 서버가 열람을 먼저 기록한다. 쓰기처럼 시간 제한이 없다. 결과는 돌려주기만 하고 어디에도 두지 않는다.
  Future<PrivateContact> viewPrivate(String id, String reason) async {
    return _read(send('POST', '${_idPath('/admin/users', id)}/private', body: {'reason': reason.trim()}), PrivateContact.fromJson);
  }

  /// 앱 밖 탈퇴 대행. [verifiedBy] 에 "@" 가 있으면 서버가 422 로 거절한다.
  Future<CloseAccountResult> closeAccount(String id, {required String reason, required String verifiedBy}) async {
    final body = {'reason': reason.trim(), 'verified_by': verifiedBy.trim()};
    return _read(send('POST', '${_idPath('/admin/users', id)}/close-account', body: body), CloseAccountResult.fromJson);
  }

  /// 주문 번호(구글) · 거래 번호(애플) 정확히 일치. 번호는 본문에만.
  Future<List<BillingOrder>> findOrders(String order) {
    return _read(send('POST', '/admin/billing/orders/search', body: {'order': order.trim()}), (body) {
      if (body case {'items': final List<Object?> items}) return [for (final row in items) BillingOrder.fromJson(row)];
      throw const FormatException('주문 목록의 모양이 아니에요');
    });
  }

  Future<BillingSummary> billingSummary() => _read(send('GET', '/admin/billing/summary'), BillingSummary.fromJson);

  /// 오래된 순 · 정확히 [days] 줄(없는 날은 0)
  Future<List<DailyRevenue>> billingDaily({int days = 30}) {
    return _read(send('GET', '/admin/billing/daily', query: {'days': '$days'}), (body) {
      if (body case {'days': final List<Object?> rows}) return [for (final row in rows) DailyRevenue.fromJson(row)];
      throw const FormatException('일 매출의 모양이 아니에요');
    });
  }

  Future<List<ShortfallRow>> billingShortfall() {
    return _read(send('GET', '/admin/billing/shortfall'), (body) {
      if (body case {'items': final List<Object?> items}) return [for (final row in items) ShortfallRow.fromJson(row)];
      throw const FormatException('못 거둔 하트 목록의 모양이 아니에요');
    });
  }

  /// 경로에 넣는 번호로 받는 글자: 영숫자와 하이픈(서버 번호는 UUID). 주소창 링크의 `..%2Fme` 를 go_router 가 `../me` 로
  /// 풀어 넘겨도 `/` · `.` · `%` 가 경로에 들어가 다른 관리자 API(`/admin/me` 등)를 부르지 못하게 한다(검토 10-18).
  /// UUID 꼴 자체(8-4-4-4-12)는 서버가 422 로 거른다. 신고 · 사람 · 글 번호도 같은 규칙이다.
  static bool isTaskId(String id) => _taskId.hasMatch(id);
  static final RegExp _taskId = RegExp(r'^[0-9A-Za-z-]+$');

  /// 꼴이 틀린 번호는 보내지 않고 없는 건(404)과 같이 실패한다.
  static String _heartTaskPath(String id) => _idPath('/admin/heart-tasks', id);

  static String _idPath(String prefix, String id) {
    if (!isTaskId(id)) throw const AdminApiFailure(404);
    return '$prefix/$id';
  }

  /// 성공이면 본문을 [parse] 로 읽고, 아니면 실패 예외를 낸다. 본문 모양이 틀린 것([FormatException])도
  /// 그 상태코드의 실패로 바꾼다 — 화면은 실패 한 가지만 다룬다.
  static Future<T> _read<T>(Future<AdminApiResponse> pending, T Function(Object? body) parse) async {
    final response = await pending;
    final already = response.reason == alreadyReviewedReason || response.reason == alreadyDoneReason;
    if (response.statusCode == 409 && already) throw const AlreadyReviewed();
    if (!response.isSuccess) throw AdminApiFailure(response.statusCode, response.reason);
    try {
      return parse(response.body);
    } on FormatException {
      throw AdminApiFailure(response.statusCode);
    }
  }

  static const String alreadyReviewedReason = 'already_reviewed';

  /// D2 조치(신고 닫기 · 정지 · 가림 · 글)의 409 — 이미 그 상태다
  static const String alreadyDoneReason = 'already_done';

  Future<AdminApiResponse> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final token = _accessToken();
    if (token == null) {
      // 세션이 없으면 보내지 않는다 — 서버가 줄 답(401)과 같은 모양으로 돌려준다.
      return const AdminApiResponse(statusCode: 401);
    }
    final request = http.Request(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    try {
      final pending = _client.send(request).then(http.Response.fromStream);
      final response = await (method == 'GET' ? pending.timeout(readTimeout) : pending);
      final decoded = _decode(response.bodyBytes);
      return AdminApiResponse(statusCode: response.statusCode, body: decoded, reason: _reasonOf(decoded));
    } on Exception {
      // 연결 실패 · 시간 초과. 서버 500 은 CORS 헤더가 없어 브라우저에선 이쪽(ClientException)으로 온다(D0 안내).
      return const AdminApiResponse();
    }
  }

  Uri _uri(String path, Map<String, String>? query) {
    final url = Uri.parse('$_baseUrl$path');
    return query == null ? url : url.replace(queryParameters: query);
  }

  /// 서버가 charset 없이 JSON 을 보내도 한글이 깨지지 않게 바이트를 UTF-8 로 읽는다.
  static Object? _decode(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  static String? _reasonOf(Object? body) {
    if (body is! Map) return null;
    final detail = body['detail'];
    return detail is String ? detail : null;
  }
}

/// 관리자 서버가 실패로 답했다. [statusCode] 가 null 이면 연결 실패 · 시간 초과다.
class AdminApiFailure implements Exception {
  const AdminApiFailure(this.statusCode, [this.reason]);

  final int? statusCode;

  /// 본문 `detail` 이 문자열이면 그 값(409 `insufficient_hearts` · `account_withdrawn` 을 가르는 데 쓴다)
  final String? reason;

  /// 토큰 거절 · 관리자 해제 · 2단계 풀림 — 관문이 다시 판정해야 한다
  bool get isGateProblem => statusCode == 401 || statusCode == 403;
}

/// 다른 관리자가 먼저 처리했다(409 `{"detail": "already_reviewed"}` · D2 조치는 `already_done`)
class AlreadyReviewed extends AdminApiFailure {
  const AlreadyReviewed() : super(409);
}
