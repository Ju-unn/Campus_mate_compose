import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 목록 한 줄(서버 `_summary` 모양 — D3 계획서 UserSummary)
Map<String, Object?> userRow(
  String id, {
  String? nickname = '닉네임A',
  String? university = '서울대학교',
  String status = 'active',
  String createdAt = '2026-09-30T03:00:00+00:00',
  int reports = 0,
}) {
  return {'id': id, 'nickname': nickname, 'university': university, 'status': status, 'created_at': createdAt, 'report_count': reports};
}

/// 상세(UserDetail) — pen A5_사용자_상세 예시와 같은 값
Map<String, Object?> userDetailJson(
  String id, {
  String? nickname = '닉네임A',
  String status = 'active',
  Object? providers = const ['kakao'],
  int balance = 120,
  int reports = 2,
  int blocks = 14,
  List<Map<String, Object?>>? hearts,
  List<Map<String, Object?>>? purchases,
  List<Map<String, Object?>>? notes,
}) {
  return {
    ...userRow(id, nickname: nickname, status: status, reports: reports),
    'last_active_at': '2026-10-18T05:20:00+00:00',
    'auto_hidden_at': null,
    'avatar_url': null,
    'school_email_verified': true,
    'login_providers': providers,
    'heart_balance': balance,
    'contact_block_count': blocks,
    'hearts': hearts ??
        [
          {'id': 'h1', 'created_at': '2026-10-18T01:02:00+00:00', 'amount': 40, 'reason': 'free_task', 'balance_after': 120},
          {'id': 'h2', 'created_at': '2026-10-17T12:30:00+00:00', 'amount': -30, 'reason': 'extra_card', 'balance_after': 80},
        ],
    'purchases': purchases ??
        [
          {
            'id': 'pu1',
            'store': 'play_store',
            'product_id': 'heart_100',
            'status': 'granted',
            'is_test': false,
            'granted_hearts': 100,
            'bonus_hearts': 0,
            'clawed_back_hearts': 0,
            'purchased_at': '2026-10-10T09:20:00+00:00',
          },
          {
            'id': 'pu2',
            'store': 'app_store',
            'product_id': 'heart_50',
            'status': 'refunded',
            'is_test': false,
            'granted_hearts': 50,
            'bonus_hearts': 0,
            'clawed_back_hearts': 50,
            'purchased_at': '2026-09-30T03:05:00+00:00',
          },
        ],
    'notes': notes ??
        [
          {'id': 'n1', 'created_at': '2026-10-12T03:00:00+00:00', 'admin_user_id': 'adm1', 'text': '결제 문의, 영수증 확인함'},
          {'id': 'n2', 'created_at': '2026-10-05T03:00:00+00:00', 'admin_user_id': 'adm1', 'text': '정지 문의 접수'},
        ],
  };
}

/// 주문 한 건(서버 `_order` 모양) — pen A8 예시(환불됨 · 지급 100 · 회수 60)
Map<String, Object?> orderRow({
  String status = 'refunded',
  int clawedBack = 60,
  String storeOrderId = 'GPA.1111-2222-3333-44444',
  String store = 'play_store',
}) {
  return {
    'id': 'pu1',
    'store': store,
    'product_id': 'heart_100',
    'store_order_id': storeOrderId,
    'status': status,
    'is_test': false,
    'heart_amount': 100,
    'bonus_hearts': 0,
    'granted_hearts': 100,
    'clawed_back_hearts': clawedBack,
    'shortfall_hearts': status == 'refunded' ? 100 - clawedBack : 0,
    'price_krw': 1900,
    // 구매는 환불보다 앞선다 — 결과 카드 "시각" 이 상태에 따라 어느 쪽인지 가른다
    'purchased_at': '2026-10-09T01:00:00+00:00',
    'granted_at': '2026-10-09T01:00:00+00:00',
    'refunded_at': status == 'refunded' ? '2026-10-10T09:20:00+00:00' : null,
    'profile': {'id': 'u1', 'nickname': '닉네임A'},
  };
}

Map<String, Object?> dayRow(String date, int revenue) => {'date': date, 'revenue_krw': revenue, 'order_count': revenue == 0 ? 0 : 1, 'refunded_krw': 0};

Map<String, Object?> shortfallRow({
  String id = 'pu1',
  String nickname = '닉네임A',
  String store = 'play_store',
  int heart = 100,
  int clawed = 60,
  String refundedAt = '2026-10-10T09:20:00+00:00',
}) {
  return {
    'purchase_id': id,
    'profile_id': 'u1',
    'nickname': nickname,
    'store': store,
    'product_id': 'heart_$heart',
    'heart_amount': heart,
    'bonus_hearts': 0,
    'clawed_back_hearts': clawed,
    'granted_hearts': heart,
    'shortfall_hearts': heart - clawed,
    'purchased_at': refundedAt,
    'refunded_at': refundedAt,
  };
}

/// 환불이 잦은 계정 한 줄(서버 `/admin/billing/frequent-returns` 모양) — 기본은 50 · 100(+보너스 50) · 800하트 세 건 환불
Map<String, Object?> returnedRow({
  String id = 'u1',
  String? nickname = '닉네임A',
  int count = 3,
  int krw = 47100,
  int granted = 1000,
  int clawed = 110,
  String lastAt = '2026-10-11T00:00:00+00:00',
}) {
  return {
    'profile_id': id,
    'nickname': nickname,
    'refund_count': count,
    'refunded_krw': krw,
    'granted_hearts': granted,
    'clawed_back_hearts': clawed,
    'shortfall_hearts': granted - clawed,
    'last_refunded_at': lastAt,
  };
}

/// 30일치 일 매출 — 마지막 날이 [lastDay]. [amounts] 가 30개보다 적으면 앞을 0 으로 채운다.
List<Map<String, Object?>> thirtyDays(List<int> amounts, {DateTime? lastDay}) {
  final end = lastDay ?? DateTime.utc(2026, 10, 18);
  final padded = [...List.filled(30 - amounts.length, 0), ...amounts];
  return [
    for (var i = 0; i < 30; i++)
      dayRow(
        (() {
          final d = end.subtract(Duration(days: 29 - i));
          return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        })(),
        padded[i],
      ),
  ];
}

/// 서버 대신 `/admin/users*` · `/admin/billing*` · `/admin/profiles/*` 를 답한다. 실패 상태코드 칸에 0 을 넣으면 연결 실패다.
class FakeUserServer {
  FakeUserServer({List<Map<String, Object?>>? users}) : users = users ?? [userRow('u1')];

  final List<Map<String, Object?>> users;
  final Map<String, Map<String, Object?>> details = {};

  /// 학교 메일 → 그 사람 번호(시험용 가짜 해시 표)
  final Map<String, String> mailOwners = {};
  Map<String, Object?> private = {'phone_number': '010-1234-5678', 'kakao_id': 'kakao_id_a'};
  Map<String, Object?> close = {
    'id': 'u1',
    'was_status': 'active',
    'status': 'withdrawn',
    'rejoin_blocked': 'two_months',
    'cleanup': {'push_tokens': 'ok', 'student_id_files': 'ok', 'kakao_unlink': 'ok'},
    'not_done': ['apple_revoke', 'logout_everywhere'],
  };

  // 결제
  Map<String, Object?> summary = {'month': '2026-10', 'revenue_krw': 1284000, 'order_count': 9, 'refunded_krw': 0};
  List<Map<String, Object?>> days = thirtyDays([90000, 130000, 170000, 132000, 166000, 285000, 150000, 175000, 195000, 137000, 152000, 165000, 189000, 110000, 120000, 55000, 70000, 88000, 30000, 145000, 84000, 36000, 75000, 112000, 75000, 113000, 244000, 117000, 155000, 190000]);
  List<Map<String, Object?>> shortfall = [
    shortfallRow(),
    shortfallRow(id: 'pu9', nickname: '닉네임F', store: 'app_store', heart: 50, clawed: 0, refundedAt: '2026-10-04T00:12:00+00:00'),
  ];
  List<Map<String, Object?>> returned = [
    returnedRow(),
    returnedRow(id: 'u7', nickname: null, count: 1, krw: 3000, granted: 50, clawed: 0, lastAt: '2026-10-04T00:12:00+00:00'),
  ];
  List<Map<String, Object?>> orders = [orderRow()];

  int? listFailure;
  int? detailFailure;
  int? billingFailure;
  int? returnedFailure;
  int? searchFailure;
  int? actionFailure;
  String? actionReason;
  Completer<void>? holdList;
  Completer<void>? holdSearch;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  /// 보낸 쓰기 요청 — "POST /admin/users/u1/hearts {…}"
  List<String> get writes => [for (final r in requests.where((r) => r.method == 'POST')) '${r.url.path} ${r.body}'];

  Iterable<http.Request> posts(String suffix) => requests.where((r) => r.method == 'POST' && r.url.path.endsWith(suffix));

  int detailFetches(String id) => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/users/$id').length;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/admin/me') return _json(200, const {});
    if (path.startsWith('/admin/billing')) return _billing(request);
    if (request.method == 'GET' && path == '/admin/users') {
      await holdList?.future;
      final failure = _fail(listFailure);
      if (failure != null) return failure;
      final q = request.url.queryParameters['q'];
      return _json(200, {
        'items': [for (final u in users) if (q == null || q.isEmpty || '${u['nickname']}'.contains(q) || u['id'] == q) u],
      });
    }
    if (request.method == 'POST' && path == '/admin/users/search') {
      await holdSearch?.future;
      final failure = _fail(searchFailure);
      if (failure != null) return failure;
      final mail = (jsonDecode(request.body) as Map)['school_email'] as String;
      final owner = mailOwners[mail];
      return _json(200, {'items': [for (final u in users) if (u['id'] == owner) u]});
    }
    final segments = request.url.pathSegments;
    if (request.method == 'GET' && segments.length == 3 && segments[1] == 'users') {
      final failure = _fail(detailFailure);
      if (failure != null) return failure;
      final detail = details[segments[2]];
      return detail == null ? _json(404, const {'detail': 'not_found'}) : _json(200, detail);
    }
    final failure = _fail(actionFailure);
    if (failure != null) return failure;
    if (actionReason != null) return _json(409, {'detail': actionReason});
    if (segments[1] == 'profiles') {
      final detail = details[segments[2]];
      if (detail != null) detail['status'] = segments[3] == 'suspend' ? 'suspended' : 'active';
      return _json(200, {'id': segments[2]});
    }
    if (segments[3] == 'close-account') details[segments[2]]?['status'] = 'withdrawn';
    return switch (segments[3]) {
      'hearts' => _json(200, {'id': segments[2], 'amount': 0, 'heart_balance': 0, 'action_id': 'a'}),
      'notes' => _json(200, const {'saved': true}),
      'private' => _json(200, private),
      'close-account' => _json(200, close),
      _ => _json(404, const {'detail': 'Not Found'}),
    };
  }

  Future<http.Response> _billing(http.Request request) async {
    final failure = _fail(billingFailure);
    final path = request.url.path;
    if (path == '/admin/billing/orders/search') {
      await holdSearch?.future;
      final searchFail = _fail(searchFailure);
      if (searchFail != null) return searchFail;
      final order = (jsonDecode(request.body) as Map)['order'] as String;
      return _json(200, {'items': [for (final o in orders) if (o['store_order_id'] == order) o]});
    }
    if (failure != null) return failure;
    if (path == '/admin/billing/frequent-returns') return _fail(returnedFailure) ?? _json(200, {'items': returned});
    return switch (path) {
      '/admin/billing/summary' => _json(200, summary),
      '/admin/billing/daily' => _json(200, {'days': days}),
      _ => _json(200, {'items': shortfall}),
    };
  }

  static http.Response? _fail(int? status) {
    if (status == null) return null;
    if (status == 0) throw http.ClientException('offline');
    return _json(status, const {});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}
