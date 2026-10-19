import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 신고당한 사람(서버 `_summary` 의 target_profile 모양)
Map<String, Object?> targetProfile({
  String id = 'p1',
  String? nickname = '닉네임B',
  String university = '연세대학교',
  String status = 'active',
  String? autoHiddenAt,
}) {
  return {'id': id, 'nickname': nickname, 'university': university, 'status': status, 'auto_hidden_at': autoHiddenAt};
}

/// 목록 한 줄(서버 `_summary` 모양). 기본 접수 시각은 시험 시계(2026-10-18 14:20 KST) 3시간 전.
Map<String, Object?> reportRow(
  String id, {
  String type = 'message',
  String reason = 'abuse',
  String? reasonNote,
  String status = 'open',
  String createdAt = '2026-10-18T02:20:00+00:00',
  String? resolvedAt,
  Object? target = const _Default(),
  String? targetId,
  int openReporters = 1,
  String? preview,
}) {
  return {
    'id': id,
    'target_type': type,
    'target_id': targetId ?? 'c-$id',
    'reason': reason,
    'reason_note': reasonNote,
    'status': status,
    'created_at': createdAt,
    'resolved_at': resolvedAt,
    'target_profile': target is _Default ? targetProfile() : target,
    // 목록 줄에도 오는 칸(서버 D2b) — 대상 계정이 지워진 줄은 서버가 0 을 준다
    'open_reporters': openReporters,
    'preview': preview,
  };
}

class _Default {
  const _Default();
}

/// 같은 대상의 다른 신고 한 줄(서버 other_reports 모양)
Map<String, Object?> otherReport(String id, {String reason = 'abuse', String status = 'open', String createdAt = '2026-10-18T00:10:00+00:00'}) {
  return {'id': id, 'target_type': 'message', 'reason': reason, 'status': status, 'created_at': createdAt};
}

/// 채팅 앞뒤 한 줄(서버 chat-context 모양)
Map<String, Object?> chatLine(String id, String body, {bool fromTarget = false, bool reported = false}) {
  return {
    'id': id,
    'kind': 'text',
    'body': body,
    'created_at': '2026-10-18T02:00:00+00:00',
    'from_target': fromTarget,
    'reported': reported,
  };
}

/// 종류마다 기본 사본(서버가 상세에 싣는 모양 — 프로필은 경로 대신 URL)
Map<String, Object?> defaultSnapshot(String type) {
  return switch (type) {
    'profile' => {
      'nickname': '닉네임B',
      'bio': '이 자리에는 신고 당시 소개 글이 그대로 보여요.',
      'avatar_url': 'https://storage.test/object/public/avatars/p1/a.png',
      'photo_urls': ['https://storage.test/sign/p1/1.jpg?token=t'],
    },
    'poll' => {'poll_id': 'c', 'question': '학식 어때요?', 'option_a_label': '맛있어요', 'option_b_label': '별로예요', 'created_at': '2026-10-17T13:15:00+00:00'},
    'friend_review' => {'review_id': 'c', 'tags': ['친절해요', '시간 잘 지켜요'], 'comment': '이 자리에는 신고 당시 한마디가 그대로 보여요.', 'created_at': '2026-10-17T10:00:00+00:00'},
    _ => {'message_id': 'm6', 'match_id': 'room', 'body': '여기에 신고 당시 글자가 그대로 보여요.', 'created_at': '2026-10-18T02:00:00+00:00'},
  };
}

/// 서버 대신 `/admin/reports*` · `/admin/profiles/*` · `/admin/content/*` 를 답한다. 조치하면 실제 서버처럼 상태가 바뀐다.
/// 실패 상태코드 칸에 0 을 넣으면 연결 실패(ClientException)다.
class FakeReportServer {
  FakeReportServer(Iterable<Map<String, Object?>> rows) : reports = {for (final row in rows) row['id']! as String: {...row}};

  final Map<String, Map<String, Object?>> reports;
  final Map<String, Map<String, Object?>> snapshots = {};
  final Map<String, String?> contentStatus = {};
  final Map<String, int> openReporters = {};
  final Map<String, List<Map<String, Object?>>> others = {};
  List<Map<String, Object?>> chat = [];

  int? listFailure;
  int? detailFailure;

  /// 조치(닫기 · 정지 · 가림 · 글 · 채팅 보기) 실패
  int? actionFailure;

  /// 가림 해제만 실패(기각 뒤 이어 부르는 것)
  int? unhideFailure;

  /// 다른 관리자가 먼저 처리했다 — 다음 조치가 409 already_done
  bool takenElsewhere = false;
  Completer<void>? holdList;
  Completer<void>? holdDetail;
  Completer<void>? holdAction;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  int get listFetches => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/reports').length;
  int detailFetches(String id) => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/reports/$id').length;

  /// 보낸 조치 — "/admin/profiles/p1/suspend {reason: …}"
  List<String> get actions => [
    for (final r in requests.where((r) => r.method == 'POST')) '${r.url.path} ${r.body}',
  ];

  Map<String, Object?> lastBody(String suffix) =>
      jsonDecode(requests.lastWhere((r) => r.url.path.endsWith(suffix)).body) as Map<String, Object?>;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.pathSegments;
    if (request.url.path == '/admin/me') return _json(200, const {});
    if (request.method == 'GET' && request.url.path == '/admin/reports') {
      await holdList?.future;
      final failure = _fail(listFailure);
      if (failure != null) return failure;
      final query = request.url.queryParameters;
      final rows = reports.values
          .where((r) => r['status'] == (query['status'] ?? 'open') && (query['type'] == null || r['target_type'] == query['type']))
          .toList()
        ..sort((a, b) => (a['created_at']! as String).compareTo(b['created_at']! as String));
      return _json(200, {'items': rows});
    }
    if (request.method == 'GET' && path.length == 3 && path[1] == 'reports') {
      await holdDetail?.future;
      final failure = _fail(detailFailure);
      if (failure != null) return failure;
      final row = reports[path[2]];
      return row == null ? _json(404, const {'detail': 'not_found'}) : _json(200, _detail(row));
    }
    await holdAction?.future;
    if (takenElsewhere) return _json(409, const {'detail': 'already_done'});
    final isUnhide = path.length == 4 && path[1] == 'profiles' && path[3] == 'unhide';
    final failure = _fail(isUnhide ? (unhideFailure ?? actionFailure) : actionFailure);
    if (failure != null) return failure;
    final body = jsonDecode(request.body) as Map<String, Object?>;
    // 서버 약속(D2b): 함께 닫기 · 가림 해제는 운영자가 본 신고 id 목록이 꼭 있어야 한다
    final needsSeen = (path[1] == 'reports' && path[3] == 'resolve' && body['same_target'] == true) || isUnhide;
    if (needsSeen && body['seen_report_ids'] == null) return _json(422, const {'detail': 'seen_reports_required'});
    if (path[1] == 'reports' && path[3] == 'chat-context') return _json(200, {'messages': chat});
    if (path[1] == 'reports' && path[3] == 'resolve') return _json(200, _resolve(path[2], body));
    if (path[1] == 'profiles') return _json(200, _actOnProfile(path[2], path[3], body));
    if (path[1] == 'content') {
      final status = path[4] == 'blind' ? 'blinded' : 'visible';
      contentStatus[path[3]] = status;
      return _json(200, {'id': path[3], 'status': status});
    }
    return _json(404, const {'detail': 'Not Found'});
  }

  Map<String, Object?> _detail(Map<String, Object?> row) {
    final id = row['id']! as String;
    final target = row['target_profile'] as Map<String, Object?>?;
    final content = row['target_type'] == 'poll' || row['target_type'] == 'friend_review';
    final contentId = row['target_id'];
    return {
      ...row,
      'snapshot': snapshots[id] ?? defaultSnapshot(row['target_type']! as String),
      // 글 신고는 지금 글 상태(기본 보임, 값을 null 로 두면 지워진 글), 그 밖은 null
      'content_status': !content ? null : (contentStatus.containsKey(contentId) ? contentStatus[contentId] : 'visible'),
      'open_reporters': target == null ? 0 : (openReporters[target['id']] ?? 1),
      'other_reports': target == null ? const <Object?>[] : (others[target['id']] ?? const <Object?>[]),
    };
  }

  Map<String, Object?> _resolve(String id, Map<String, Object?> body) {
    final row = reports[id]!;
    final target = (row['target_profile'] as Map<String, Object?>?)?['id'];
    void close(Map<String, Object?> r) {
      r['status'] = body['outcome'];
      r['resolved_at'] = '2026-10-18T05:30:00+00:00';
    }

    close(row);
    if (body['same_target'] == true && target != null) {
      final seen = (body['seen_report_ids']! as List<Object?>).toSet();
      for (final other in others[target] ?? const <Map<String, Object?>>[]) {
        // 서버처럼 본 신고만 닫는다 — 상세를 연 뒤 들어온 새 신고는 열린 채
        if (other['status'] == 'open' && seen.contains(other['id'])) other['status'] = body['outcome'];
      }
    }
    return _detail(row);
  }

  Map<String, Object?> _actOnProfile(String profileId, String action, Map<String, Object?> body) {
    for (final row in reports.values) {
      final target = row['target_profile'] as Map<String, Object?>?;
      if (target?['id'] != profileId) continue;
      switch (action) {
        case 'suspend':
          target!['status'] = 'suspended';
        case 'unsuspend':
          target!['status'] = 'active';
        case 'unhide':
          target!['auto_hidden_at'] = null;
          final seen = (body['seen_report_ids']! as List<Object?>).toSet();
          if (row['status'] == 'open' && seen.contains(row['id'])) row['status'] = 'dismissed';
          for (final other in others[profileId] ?? const <Map<String, Object?>>[]) {
            if (other['status'] == 'open' && seen.contains(other['id'])) other['status'] = 'dismissed';
          }
      }
    }
    return {'id': profileId};
  }

  static http.Response? _fail(int? status) {
    if (status == null) return null;
    if (status == 0) throw http.ClientException('offline');
    return _json(status, const {});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}
