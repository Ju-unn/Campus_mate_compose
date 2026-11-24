import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/actions/action_item.dart';
import 'package:campus_mate_admin/api/list_page.dart';
import 'package:campus_mate_admin/billing/billing_item.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:campus_mate_admin/matching/matching_item.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/server_status/server_status_models.dart';
import 'package:campus_mate_admin/unknown_domains/unknown_domain_item.dart';
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

  /// 대기 건 요약(오래된 순 · 쪽당 [pageSize]). 사진 · 지난 제출은 없다 — 줄을 고르면 [getHeartTask].
  Future<ListPage<HeartTaskItem>> listHeartTasks({HeartTaskKind? task, int page = 1}) {
    return _page('/admin/heart-tasks', {'task': ?task?.code}, page, HeartTaskItem.fromJson, '인증샷 목록');
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

  // 졸업생 검수(A10) — 서버 계약은 backend/app/admin/graduate_review.py. 실패는 [AdminApiFailure](409 already_reviewed 만 [AlreadyReviewed]).
  // 번호 · 학번은 POST 본문으로만 보내고 어디에도 남기지 않는다(예외에도 싣지 않는다).

  /// 오래된 순(먼저 낸 사람부터). 사진 · 글자 인식 · 이메일은 없다 — 줄을 고르면 [fetchGraduateRequest].
  Future<ListPage<GraduateItem>> listGraduateRequests({GraduateStatus status = GraduateStatus.pending, int page = 1}) {
    return _page('/admin/graduate-requests', {'status': status.code}, page, GraduateItem.fromJson, '졸업생 신청 목록');
  }

  /// 한 건 — 5분 서명 사진 · 글자 인식 · 이전 학교 메일 · 중복 경고 · 지난 신청. 서명이 만료돼 사진을 다시 받을 때도 쓴다.
  Future<GraduateDetail> fetchGraduateRequest(String id) async {
    return _read(send('GET', _idPath('/admin/graduate-requests', id)), GraduateDetail.fromJson);
  }

  /// 승인. 학교 · 문서확인번호는 필수, 학번은 서류에 있을 때만(비면 칸을 보내지 않는다). 응답 본문(결정된 한 건)은 읽지 않는다 —
  /// 승인은 됐는데 모양이 틀려 실패로 보이면 다시 누르게 된다.
  Future<void> approveGraduate(String id, {required String universityId, required String documentNumber, String? studentNumber}) async {
    final student = studentNumber?.trim();
    final body = {
      'university_id': universityId,
      'document_number': documentNumber.trim(),
      if (student != null && student.isNotEmpty) 'student_number': student,
    };
    return _read(send('POST', '${_idPath('/admin/graduate-requests', id)}/approve', body: body), (_) {});
  }

  Future<void> rejectGraduate(String id, GraduateRejectReason reason) async {
    return _read(send('POST', '${_idPath('/admin/graduate-requests', id)}/reject', body: {'reason': reason.code}), (_) {});
  }

  // 신고 검수(A4) — 409 already_done 도 [AlreadyReviewed](이미 처리됨)로 던진다. 사유 · 메모는 앞뒤 공백만 떼고 그대로 보낸다.

  /// 열림은 오래된 순, 닫힘은 최근 순 · 쪽당 [pageSize]. 사본 · 사진은 없다(신고자 수 · 투표 질문 · 댓글 본문 앞부분은 있다) — 줄을 고르면 [getReport].
  Future<ListPage<ReportSummary>> listReports({ReportStatus status = ReportStatus.open, ReportTargetType? type, int page = 1}) {
    return _page('/admin/reports', {'status': status.code, 'type': ?type?.code}, page, ReportSummary.fromJson, '신고 목록');
  }

  /// 한 건 — 사본(실사진은 5분 서명) · 글 상태 · 신고자 수 · 같은 대상의 다른 신고. 디스코드 링크로 열 때도 쓴다.
  Future<ReportDetail> getReport(String id) async {
    return _read(send('GET', _idPath('/admin/reports', id)), ReportDetail.fromJson);
  }

  /// 조치 완료 / 기각. [sameTarget] 이면 같은 사람의 다른 열린 신고도 같은 결과로 닫는다. 응답 본문은 읽지 않는다(W1 과 같은 이유).
  /// [sameTarget] 일 때만 [seenReportIds](운영자가 본 열린 신고 id)를 보낸다 — 서버가 그 신고만 함께 닫는다(없으면 422).
  Future<void> resolveReport(
    String id,
    ReportStatus outcome, {
    String? note,
    bool sameTarget = false,
    List<String> seenReportIds = const [],
  }) async {
    final memo = note?.trim();
    final body = {
      'outcome': outcome.code,
      'note': memo == null || memo.isEmpty ? null : memo,
      'same_target': sameTarget,
      if (sameTarget) 'seen_report_ids': seenReportIds,
    };
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
  /// 가림 해제만 [seenReportIds](운영자가 본 열린 신고 id)를 보낸다 — 서버가 그 신고만 기각한다(없으면 422).
  Future<void> actOnProfile(String profileId, ProfileAction action, String reason, {List<String> seenReportIds = const []}) async {
    final path = '${_idPath('/admin/profiles', profileId)}/${action.name}';
    final body = {'reason': reason.trim(), if (action == ProfileAction.unhide) 'seen_report_ids': seenReportIds};
    return _read(send('POST', path, body: body), (_) {});
  }

  /// 투표 글 · 지인 리뷰 · 댓글 가림([blind]) / 해제
  Future<void> setContentStatus(ReportTargetType kind, String contentId, {required bool blind, required String reason}) async {
    final segment = switch (kind) {
      ReportTargetType.poll => 'polls',
      ReportTargetType.pollComment => 'poll-comments',
      _ => 'friend-reviews',
    };
    final path = '${_idPath('/admin/content/$segment', contentId)}/${blind ? 'blind' : 'unblind'}';
    return _read(send('POST', path, body: {'reason': reason.trim()}), (_) {});
  }

  // 사용자(A5) · 결제(A8) — 서버 계약은 D3 계획서 표 그대로. 학교 메일 · 주문 번호는 POST 본문으로만 보낸다(주소 · 쿼리에 남기지 않음).

  /// [sort] 순(기본 가입 최근 순) · 쪽당 [pageSize]. [q] 는 닉네임 일부 또는 프로필 id, [school] 은 학교 이름 일부.
  /// 기본 정렬이면 sort · dir 을 보내지 않는다(정렬을 모르는 옛 서버와 같은 요청).
  Future<ListPage<UserSummary>> listUsers({String? q, String? school, UserSort sort = UserSort.newestFirst, int page = 1}) {
    final text = q?.trim() ?? '';
    final schoolText = school?.trim() ?? '';
    return _page('/admin/users', {
      if (text.isNotEmpty) 'q': text,
      if (schoolText.isNotEmpty) 'school': schoolText,
      if (sort != UserSort.newestFirst) ...{'sort': sort.column.code, 'dir': sort.ascending ? 'asc' : 'desc'},
    }, page, UserSummary.fromJson, '사용자 목록');
  }

  /// 학교 메일 정확히 일치(0 또는 1줄). 메일은 본문에만 — 서버도 기록하지 않는다.
  Future<List<UserSummary>> searchUsersBySchoolEmail(String email) {
    return _read(send('POST', '/admin/users/search', body: {'school_email': email.trim()}), _userRows);
  }

  static List<UserSummary> _userRows(Object? body) {
    if (body case {'items': final List<Object?> items}) return [for (final row in items) UserSummary.fromJson(row)];
    throw const FormatException('사용자 목록의 모양이 아니에요');
  }

  /// 성별 · 들어온 경로 인원 — 목록(q 없음)과 같은 기준(관리자 제외, 모든 상태). 개수만 온다.
  Future<UserTotals> userTotals() => _read(send('GET', '/admin/users/totals'), UserTotals.fromJson);

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

  /// 최근 결제(시험 결제 제외), 최근 순 · 쪽당 [pageSize] — 누가 결제했는지. 주문 번호는 오지 않는다.
  Future<ListPage<BillingOrder>> billingRecent({int page = 1}) {
    return _page('/admin/billing/recent', {}, page, BillingOrder.fromJson, '최근 결제 목록');
  }

  Future<ListPage<ShortfallRow>> billingShortfall({int page = 1}) {
    return _page('/admin/billing/shortfall', {}, page, ShortfallRow.fromJson, '못 거둔 하트 목록');
  }

  /// 환불이 잦은 계정, 환불 건수 많은 순 · 쪽당 [pageSize]
  Future<ListPage<ReturnedAccountRow>> billingReturnedAccounts({int page = 1}) {
    return _page('/admin/billing/frequent-returns', {}, page, ReturnedAccountRow.fromJson, '환불이 잦은 계정 목록');
  }

  // 홈(A2) · 미등록 학교 메일(A6) · 매칭(A9) · 작업 기록(A7) — 읽기만. 서버 계약은 D4 계획서 표 · D3 action_log.py 그대로.

  Future<HomeStats> homeStats() => _read(send('GET', '/admin/stats'), HomeStats.fromJson);

  /// 오래된 순 · 정확히 [days] 줄. 접수량 막대는 이 응답의 마지막 14줄을 화면이 잘라 쓴다.
  Future<List<DailyStat>> statsDaily({int days = 30}) {
    return _read(send('GET', '/admin/stats/daily', query: {'days': '$days'}), (body) {
      if (body case {'days': final List<Object?> rows}) return [for (final row in rows) DailyStat.fromJson(row)];
      throw const FormatException('일별 통계의 모양이 아니에요');
    });
  }

  /// 활성 많은 순. [includeEmpty] 면 활성 0 인 학교도(매칭 학교 고르기).
  Future<List<UniversityStatus>> universities({bool includeEmpty = false}) {
    return _read(send('GET', '/admin/universities', query: {'include_empty': '$includeEmpty'}), (body) {
      if (body case {'items': final List<Object?> rows}) return [for (final row in rows) UniversityStatus.fromJson(row)];
      throw const FormatException('학교 목록의 모양이 아니에요');
    });
  }

  Future<HealthReport> health() => _read(send('GET', '/admin/health'), HealthReport.fromJson);

  // 서버 상태(A11) · 메뉴 배지 — 서버 계약은 backend/app/admin/server_status.py · stats.py. 구글을 못 읽으면 503.

  Future<ServerStatus> serverStatus() => _read(send('GET', '/admin/server-status'), ServerStatus.fromJson);

  Future<PendingCounts> pendingCounts() => _read(send('GET', '/admin/pending-counts'), PendingCounts.fromJson);

  /// 많은 순 · 쪽당 [pageSize]
  Future<ListPage<UnknownDomain>> unknownDomains({int page = 1}) {
    return _page('/admin/unknown-domains', {}, page, UnknownDomain.fromJson, '미등록 학교 메일 목록');
  }

  Future<MatchingSummary> matchingSummary() => _read(send('GET', '/admin/matching/summary'), MatchingSummary.fromJson);

  Future<List<DailyMatching>> matchingDaily({int days = 30}) {
    return _read(send('GET', '/admin/matching/daily', query: {'days': '$days'}), (body) {
      if (body case {'days': final List<Object?> rows}) return [for (final row in rows) DailyMatching.fromJson(row)];
      throw const FormatException('매칭 일별의 모양이 아니에요');
    });
  }

  /// 최근 순 · 쪽당 [pageSize]. [status] `chatting` · `shared` · `closed`, [university] 학교 id.
  Future<ListPage<MatchPair>> matchingPairs({String? status, String? university, int page = 1}) {
    return _page('/admin/matching/pairs', {'status': ?status, 'university': ?university}, page, MatchPair.fromJson, '매칭 목록');
  }

  /// 누가 누구에게 대화를 신청했나 — 최근 순 · 쪽당 [pageSize]. [status] `waiting` · `accepted` · `rejected` · `expired`.
  Future<ListPage<MatchRequest>> matchingRequests({String? status, int page = 1}) {
    return _page('/admin/matching/requests', {'status': ?status}, page, MatchRequest.fromJson, '대화 신청 목록');
  }

  /// 작업 기록 최근 순 · 쪽당 [pageSize]. [target] 은 대상 id 정확 일치(UUID 모양 검사는 화면이 먼저 한다).
  Future<ListPage<ActionRow>> listActions({String? target, int page = 1}) {
    return _page('/admin/actions', {'target': ?target}, page, ActionRow.fromJson, '작업 기록');
  }

  // 문의 관리 — 서버 계약은 backend/app/admin/inquiry_review.py. 답장은 서버가 보내지 않는다(운영자가 메일함에서 회신).

  /// 최근 순 · 쪽당 [pageSize].
  Future<ListPage<InquiryItem>> listInquiries({InquiryStatus? status, int page = 1}) {
    return _page('/admin/inquiries', {'status': ?status?.code}, page, InquiryItem.fromJson, '문의 목록');
  }

  /// 바꿀 칸만 보낸다. [memo] 는 앞뒤 공백을 떼고 보내며, 빈 글이면 서버가 메모를 지운다. 응답은 바뀐 한 줄.
  /// 같은 값을 다시 보내도 결과가 같아(멱등) 본문 모양이 틀려 실패로 보인 뒤 다시 눌러도 안전하다.
  Future<InquiryItem> updateInquiry(String id, {InquiryStatus? status, String? memo}) async {
    final body = {'status': ?status?.code, 'admin_memo': ?memo?.trim()};
    return _read(send('PATCH', _idPath('/admin/inquiries', id), body: body), InquiryItem.fromJson);
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

  /// 목록 한 쪽의 줄 수(서버 기본과 같다 — 쪽 수는 이 값으로 나눈다)
  static const int pageSize = 20;

  /// 번호 쪽 목록 하나 — [filters] 에 `page` · `size` 를 붙여 GET 하고 `{items, total}` 을 읽는다.
  Future<ListPage<T>> _page<T>(String path, Map<String, String> filters, int page, T Function(Object? row) parse, String what) {
    final query = {...filters, 'page': '$page', 'size': '$pageSize'};
    return _read(send('GET', path, query: query), (body) => ListPage.fromJson(body, parse, what));
  }

  static const String alreadyReviewedReason = 'already_reviewed';

  /// D2 조치(신고 닫기 · 정지 · 가림 · 글)의 409 — 이미 그 상태다
  static const String alreadyDoneReason = 'already_done';

  Future<AdminApiResponse> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) {
    final request = http.Request(method, _uri(path, query));
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    return _exchange(request);
  }

  /// 토큰을 붙여 보낸다(JSON · multipart 공통). 조회(GET)만 [readTimeout] 으로 끊는다.
  Future<AdminApiResponse> _exchange(http.BaseRequest request) async {
    final token = _accessToken();
    if (token == null) {
      // 세션이 없으면 보내지 않는다 — 서버가 줄 답(401)과 같은 모양으로 돌려준다.
      return const AdminApiResponse(statusCode: 401);
    }
    request.headers
      ..['Authorization'] = 'Bearer $token'
      ..['Accept'] = 'application/json';
    try {
      final pending = _client.send(request).then(http.Response.fromStream);
      final response = await (request.method == 'GET' ? pending.timeout(readTimeout) : pending);
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
