import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// "2026-09-19" … "2026-10-18" 처럼 [last] 로 끝나는 [count] 일의 서버 날짜 글자(오래된 순)
List<String> dateRange(int count, {DateTime? last}) {
  final end = last ?? DateTime.utc(2026, 10, 18);
  String two(int n) => n.toString().padLeft(2, '0');
  return [
    for (var i = 0; i < count; i++)
      () {
        final d = end.subtract(Duration(days: count - 1 - i));
        return '${d.year}-${two(d.month)}-${two(d.day)}';
      }(),
  ];
}

/// 서버 `/admin/stats/daily` 30일. 가입은 남 최대 47 · 여 최대 36(pen 눈금 0/20/40/60), 접수는 10/14 에 신고 8 · 인증샷 15(pen 말풍선).
List<Map<String, Object?>> dailyStatRows() {
  final dates = dateRange(30);
  return [
    for (final (i, date) in dates.indexed)
      {
        'date': date,
        'male_signups': i == 29 ? 47 : 20 + (i * 7) % 20,
        'female_signups': i == 29 ? 36 : 18 + (i * 5) % 15,
        'report_count': date == '2026-10-14' ? 8 : (i % 6) + 1,
        'proof_count': date == '2026-10-14' ? 15 : (i % 9) + 3,
      },
  ];
}

Map<String, Object?> universityRow(String name, int male, int female, {String? opensAt = '2026-11-01T22:00:00+00:00', String? id}) {
  return {
    'id': id ?? 'uni-$name',
    'name': name,
    'region_group': 'seoul',
    'card_opens_at': opensAt,
    'is_open': false,
    'male_active': male,
    'female_active': female,
  };
}

/// pen A2 예시(서울대 62/58 · 연세대 48/51 · 고려대 27/24), 서버 순서 = 활성 많은 순
List<Map<String, Object?>> universityRows() => [
  universityRow('서울대학교', 62, 58),
  universityRow('연세대학교', 48, 51),
  universityRow('고려대학교', 27, 24, opensAt: '2026-11-08T22:00:00+00:00'),
];

/// pen A2 가로 막대의 다섯 학교(서울대 62/58 · 연세대 48/51 · 고려대 27/24 · 성균관대 19/22 · 이화여대 4/33) — 막대 그림 높이 240
List<Map<String, Object?>> fiveUniversityRows() => [
  ...universityRows(),
  universityRow('성균관대학교', 19, 22, opensAt: '2026-11-08T22:00:00+00:00'),
  universityRow('이화여자대학교', 4, 33, opensAt: '2026-11-08T22:00:00+00:00'),
];

Map<String, Object?> healthJson({List<Map<String, Object?>>? items, List<String> unobservable = const ['refund_batch']}) {
  return {
    'checked_at': '2026-10-18T09:00:00+09:00',
    'items': items ??
        [
          {'key': 'cards_issued_today', 'status': 'ok', 'count': 0},
          {'key': 'stuck_chat_rooms', 'status': 'warn', 'count': 2},
          {'key': 'overdue_withdrawn', 'status': 'ok', 'count': 0},
          {'key': 'avatar_failures_24h', 'status': 'alert', 'count': 4},
          {'key': 'stuck_pending_pushes', 'status': 'ok', 'count': 0},
        ],
    'unobservable': unobservable,
  };
}

Map<String, Object?> matchDailyRow(String date, int accept, int match, int share) =>
    {'date': date, 'accept_count': accept, 'match_count': match, 'share_count': share};

/// 매칭 30일. 수락 최대 31(pen 눈금 0/10/20/30/40)
List<Map<String, Object?>> matchDailyRows() {
  return [
    for (final (i, date) in dateRange(30).indexed)
      matchDailyRow(date, i == 20 ? 31 : 14 + (i * 3) % 14, 5 + (i * 2) % 7, 2 + i % 5),
  ];
}

Map<String, Object?> matchSummaryJson({int? yesterday = 14, Object? shareRate = 0.62, int matches = 67, int shared = 41}) {
  return {
    'accepts_today': 18,
    'accepts_yesterday': ?yesterday,
    'accepts_total': 436,
    'accepters_total': 312,
    'matches_total': matches,
    'shared_total': shared,
    'share_rate': shareRate,
  };
}

Map<String, Object?> pairRow(
  String id,
  String matchedAt,
  String status, {
  String? sharedAt,
  Map<String, Object?>? a,
  Map<String, Object?>? b,
}) {
  return {
    'id': id,
    'matched_at': matchedAt,
    'status': status,
    'shared_at': sharedAt,
    'a': a ?? {'id': '$id-a', 'nickname': '닉네임A', 'university': '서울대학교'},
    'b': b ?? {'id': '$id-b', 'nickname': '닉네임B', 'university': '서울대학교'},
  };
}

/// pen A9 예시 7줄(10/18 14:02 대화 중 … 10/16 15:31 대화 중). 시각은 UTC 로 적어 화면(KST)과 9시간 어긋난다.
List<Map<String, Object?>> pairRows() => [
  pairRow('m1', '2026-10-18T05:02:00+00:00', 'chatting'),
  pairRow('m2', '2026-10-18T02:25:00+00:00', 'shared', sharedAt: '2026-10-18T03:40:00+00:00',
      a: {'id': 'm2-a', 'nickname': '닉네임C', 'university': '연세대학교'}, b: {'id': 'm2-b', 'nickname': '닉네임D', 'university': '연세대학교'}),
  pairRow('m3', '2026-10-17T12:10:00+00:00', 'chatting',
      a: {'id': 'm3-a', 'nickname': '닉네임E', 'university': '고려대학교'}, b: {'id': 'm3-b', 'nickname': '닉네임F', 'university': '고려대학교'}),
  pairRow('m4', '2026-10-17T09:44:00+00:00', 'shared', sharedAt: '2026-10-17T10:30:00+00:00',
      a: {'id': 'm4-a', 'nickname': '닉네임G', 'university': '서울대학교'}, b: {'id': 'm4-b', 'nickname': '닉네임H', 'university': '서울대학교'}),
  pairRow('m5', '2026-10-17T00:12:00+00:00', 'closed',
      a: {'id': 'm5-a', 'nickname': '닉네임I', 'university': '연세대학교'}, b: {'id': 'm5-b', 'nickname': '닉네임J', 'university': '연세대학교'}),
  pairRow('m6', '2026-10-16T13:03:00+00:00', 'shared', sharedAt: '2026-10-16T23:15:00+00:00',
      a: {'id': 'm6-a', 'nickname': '닉네임K', 'university': '고려대학교'}, b: {'id': 'm6-b', 'nickname': '닉네임L', 'university': '고려대학교'}),
  pairRow('m7', '2026-10-16T06:31:00+00:00', 'chatting',
      a: {'id': 'm7-a', 'nickname': '닉네임M', 'university': '성균관대학교'}, b: {'id': 'm7-b', 'nickname': '닉네임N', 'university': '성균관대학교'}),
];

Map<String, Object?> domainRow(String domain, int attempts, String lastSeen) =>
    {'domain': domain, 'attempt_count': attempts, 'first_seen_at': '2026-10-01T00:00:00+00:00', 'last_seen_at': lastSeen};

Map<String, Object?> actionRow(
  String id,
  String createdAt,
  String action, {
  String? targetType,
  String? targetId,
  String? nickname,
  String? reason,
  String? email = 'admin@example.com',
  Map<String, Object?>? after,
}) {
  return {
    'id': id,
    'created_at': createdAt,
    'admin_user_id': 'adm1',
    'admin_email': email,
    'action': action,
    'target_type': targetType,
    'target_id': targetId,
    'target_nickname': nickname,
    'before': null,
    'after': after,
    'reason': reason,
    'ip': '203.0.113.9',
  };
}

/// pen A7 예시 3줄
List<Map<String, Object?>> actionRows() => [
  actionRow('a1', '2026-10-18T05:30:00+00:00', 'heart_task_approve', targetType: 'heart_task_submission', targetId: 'e4100000-0000-4000-8000-000000000001'),
  actionRow('a2', '2026-10-18T05:21:00+00:00', 'profile_suspend', targetType: 'profile', targetId: 'b0000000-0000-4000-8000-000000000002', nickname: '닉네임B', reason: '불쾌한 사진 3건'),
  actionRow('a3', '2026-10-18T04:55:00+00:00', 'hearts_adjust', targetType: 'profile', targetId: 'a0000000-0000-4000-8000-000000000001', nickname: '닉네임A', reason: '오류 보상', after: {'heart_balance': 170, 'amount': 50}),
];

/// 서버 대신 홈 · 매칭 · 미등록 학교 메일 · 작업 기록 경로(D4 · D3 계약)를 답한다. 실패 칸에 0 을 넣으면 연결 실패다.
class FakeStatsServer {
  FakeStatsServer();

  Map<String, Object?> stats = {
    'profiles': {'pending': 3, 'active': 311, 'suspended': 2, 'withdrawn': 9},
    'open_reports': 5,
    'pending_proofs': 12,
    'signups_today': 38,
    'signups_7d': 210,
  };
  List<Map<String, Object?>> daily = dailyStatRows();
  List<Map<String, Object?>> universities = fiveUniversityRows();
  Map<String, Object?> health = healthJson();
  List<Map<String, Object?>> domains = [
    domainRow('example-univ.ac.kr', 12, '2026-10-18T04:40:00+00:00'),
    domainRow('sample-college.ac.kr', 7, '2026-10-17T09:12:00+00:00'),
    domainRow('demo-univ.ac.kr', 3, '2026-10-16T00:05:00+00:00'),
  ];
  Map<String, Object?> matchSummary = matchSummaryJson();
  List<Map<String, Object?>> matchDaily = matchDailyRows();
  List<Map<String, Object?>> pairs = pairRows();
  List<Map<String, Object?>> actions = actionRows();

  /// 쪽 크기(서버 기본은 50). 작게 줘서 "더 보기"를 시험한다.
  int pageSize = 50;

  int? statsFailure;
  int? healthFailure;
  int? matchingFailure;
  int? pairsFailure;
  int? domainsFailure;
  int? actionsFailure;
  Completer<void>? holdPairs;
  Completer<void>? holdActions;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  Iterable<http.Request> to(String path) => requests.where((r) => r.url.path == path);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final query = request.url.queryParameters;
    return switch (path) {
      '/admin/me' => _json(200, const {}),
      '/admin/stats' => _failOr(statsFailure, stats),
      '/admin/stats/daily' => _failOr(statsFailure, {'days': daily}),
      '/admin/universities' => _failOr(statsFailure, {'items': universities}),
      '/admin/health' => _failOr(healthFailure, health),
      '/admin/unknown-domains' => _failOr(domainsFailure, {'items': domains}),
      '/admin/matching/summary' => _failOr(matchingFailure, matchSummary),
      '/admin/matching/daily' => _failOr(matchingFailure, {'days': matchDaily}),
      '/admin/matching/pairs' => await _page(pairs, pairsFailure, holdPairs, query, (row) => '${row['matched_at']}|${row['id']}', (row) {
        final status = query['status'];
        final university = query['university'];
        final names = {for (final u in universities) u['id']: u['name']};
        return (status == null || row['status'] == status) &&
            (university == null || [row['a'], row['b']].any((p) => (p! as Map)['university'] == names[university]));
      }),
      '/admin/actions' => await _page(actions, actionsFailure, holdActions, query, (row) => '${row['created_at']}|${row['id']}', (row) {
        final target = query['target'];
        return target == null || row['target_id'] == target;
      }),
      _ => _json(404, const {'detail': 'Not Found'}),
    };
  }

  Future<http.Response> _page(
    List<Map<String, Object?>> rows,
    int? failure,
    Completer<void>? hold,
    Map<String, String> query,
    String Function(Map<String, Object?>) cursorOf,
    bool Function(Map<String, Object?>) keep,
  ) async {
    await hold?.future;
    if (failure != null) return _failOr(failure, const {});
    final matching = rows.where(keep).toList();
    final before = query['before'];
    var from = 0;
    if (before != null) from = matching.indexWhere((row) => cursorOf(row) == before) + 1;
    final slice = matching.skip(from).take(pageSize).toList();
    final more = from + slice.length < matching.length;
    return _json(200, {'items': slice, 'next_before': more ? cursorOf(slice.last) : null});
  }

  static http.Response _failOr(int? status, Object body) {
    if (status == null) return _json(200, body);
    if (status == 0) throw http.ClientException('offline');
    return _json(status, const {});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}
