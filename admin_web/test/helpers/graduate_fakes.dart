import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 목록 한 줄(서버 `_summary` 모양 — 사진 · 글자 인식 · 이메일 없음, 닉네임 · 학교 이름은 탈퇴 계정이면 null). 기본 제출 시각은 2026-10-19 11:20(한국) = 02:20 UTC.
Map<String, Object?> graduateRow(
  String id, {
  int attemptNo = 1,
  String createdAt = '2026-10-19T02:20:00+00:00',
  String? profileId,
  String? nickname = '닉네임A',
  String? universityName = '서울대학교',
}) {
  return {
    'id': id,
    'status': 'pending',
    'reason': null,
    'created_at': createdAt,
    'decided_at': null,
    'attempt_no': attemptNo,
    'nickname': nickname,
    'university_name': universityName,
    'profile_id': profileId ?? 'aaaaaaaa-0000-0000-0000-$id'.padRight(36, '0'),
  };
}

Map<String, Object?> graduateWarning(String code, {String? profileId, String? profileStatus}) {
  return {'code': code, 'profile_id': ?profileId, 'profile_status': ?profileStatus};
}

Map<String, Object?> graduateHistory(String status, {String? reason, String decidedAt = '2026-10-17T02:20:00+00:00'}) {
  return {'status': status, 'reason': reason, 'decided_at': decidedAt};
}

/// 서버 대신 `/admin/graduate-requests*` 와 `/admin/universities` 를 답한다. 승인 · 반려하면 그 건은 대기 목록에서 빠진다.
/// 상태코드 칸에 0 을 넣으면 연결 실패(ClientException)다.
class FakeGraduateServer {
  FakeGraduateServer(Iterable<Map<String, Object?>> rows) : pending = [...rows];

  final List<Map<String, Object?>> pending;

  /// 건별 상세 덮어쓰기(ocr · previous_school_email · warnings · history · photo_url). 없으면 "글자 인식 성공 + 서울대" 기본값.
  final Map<String, Map<String, Object?>> detailOverrides = {};

  /// 대기 목록에 없는 건(이미 처리됨) — 한 건 조회에만 답한다. 값은 상세 한 건(status 포함).
  final Map<String, Map<String, Object?>> others = {};

  /// 승인 · 반려가 이 409 이유로 거절된다(건 id → detail 이유)
  final Map<String, String> conflicts = {};

  /// 첫 조회의 사진 주소가 깨진다(서명 만료)
  final Set<String> brokenOnce = {};

  final List<Map<String, Object?>> universities = [
    {'id': 'u-snu', 'name': '서울대학교', 'male_active': 0, 'female_active': 0, 'card_opens_at': null},
    {'id': 'u-yonsei', 'name': '연세대학교', 'male_active': 0, 'female_active': 0, 'card_opens_at': null},
    {'id': 'u-korea', 'name': '고려대학교', 'male_active': 0, 'female_active': 0, 'card_opens_at': null},
  ];

  int? listFailure;
  int? detailFailure;
  int? reviewFailure;
  int? universitiesFailure;
  Completer<void>? holdList;
  Completer<void>? holdDetail;
  Completer<void>? holdReview;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  int detailFetches(String id) => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/graduate-requests/$id').length;

  /// 보낸 승인 본문들(해석한 JSON)
  List<Map<String, Object?>> get approvals => [
    for (final r in requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/approve')))
      (jsonDecode(r.body) as Map).cast<String, Object?>(),
  ];

  /// 보낸 승인 · 반려 — "approve:g1" · "reject:g1:unreadable"
  List<String> get reviews => [
    for (final r in requests.where((r) => r.method == 'POST'))
      [r.url.pathSegments[3], r.url.pathSegments[2], if (r.url.path.endsWith('/reject')) (jsonDecode(r.body) as Map)['reason']].join(':'),
  ];

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.pathSegments;
    if (request.url.path == '/admin/me') return _json(200, const {});
    if (request.url.path == '/admin/universities') {
      final failure = _fail(universitiesFailure);
      return failure ?? _json(200, {'items': universities});
    }
    if (path.length == 2) {
      await holdList?.future;
      final failure = _fail(listFailure);
      if (failure != null) return failure;
      return _json(200, {'items': pending});
    }
    final id = path[2];
    if (path.length == 3) {
      await holdDetail?.future;
      final failure = _fail(detailFailure);
      if (failure != null) return failure;
      final row = _find(id);
      if (row == null) {
        final other = others[id];
        return other == null ? _json(404, const {'detail': 'not_found'}) : _json(200, other);
      }
      return _json(200, _detail(row));
    }
    await holdReview?.future;
    final failure = _fail(reviewFailure);
    if (failure != null) return failure;
    final conflict = conflicts[id];
    if (conflict != null) {
      if (conflict == 'already_reviewed') pending.removeWhere((r) => r['id'] == id);
      return _json(409, {'detail': conflict});
    }
    final row = _find(id);
    if (row == null) return _json(404, const {'detail': 'not_found'});
    pending.remove(row);
    final approved = path[3] == 'approve';
    return _json(200, {
      ...row,
      'status': approved ? 'approved' : 'rejected',
      'photo_url': null,
      'ocr': null,
      'previous_school_email': null,
      'warnings': const <Object?>[],
      'history': const <Object?>[],
    });
  }

  Map<String, Object?>? _find(String id) {
    for (final row in pending) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  Map<String, Object?> _detail(Map<String, Object?> row) {
    final id = row['id']! as String;
    final fetch = detailFetches(id);
    final broken = brokenOnce.contains(id) && fetch == 1;
    return {
      ...row,
      'photo_url': 'https://storage.test/$id.jpg?v=$fetch${broken ? '&broken' : ''}',
      'ocr': {
        'state': 'read',
        'document_number': 'A12B-3456-78CD',
        'school_text': '서울대학교',
        'suggested_university_ids': ['u-snu'],
      },
      'previous_school_email': null,
      'warnings': const <Object?>[],
      'history': const <Object?>[],
      ...?detailOverrides[id],
    };
  }

  static http.Response? _fail(int? status) {
    if (status == null) return null;
    if (status == 0) throw http.ClientException('offline');
    return _json(status, const {});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}
