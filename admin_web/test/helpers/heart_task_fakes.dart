import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 시험 시계 — 2026-10-18 14:20 한국 시간(05:20 UTC).
final DateTime testNow = DateTime.utc(2026, 10, 18, 5, 20);

/// 목록 한 줄(서버 `_summary` 모양 — 사진 · 지난 제출 없음). 기본 제출 시각은 [testNow] 12분 전.
Map<String, Object?> taskRow(
  String id, {
  String task = 'everytime_post',
  String? nickname = '닉네임A',
  String university = '서울대학교',
  int reward = 40,
  String createdAt = '2026-10-18T05:08:00+00:00',
}) {
  return {
    'id': id,
    'task': task,
    'status': 'submitted',
    'reject_reason': null,
    'reward_hearts': reward,
    'created_at': createdAt,
    'reviewed_at': null,
    'profile': {'id': 'p-$id', 'nickname': nickname, 'university': university},
  };
}

/// 지난 제출 한 칸(서버 `_item` 의 previous 모양)
Map<String, Object?> previousPhoto(String id, {String status = 'approved', bool photo = true}) {
  return {
    'id': id,
    'status': status,
    'created_at': '2026-10-11T05:00:00+00:00',
    'photo_url': photo ? 'https://storage.test/$id.jpg?token=t' : null,
  };
}

/// 서버 대신 `/admin/heart-tasks*` 를 답한다. 승인 · 반려하면 그 건은 대기 목록에서 빠진다(실제 서버처럼).
/// 실패 상태코드 칸에 0 을 넣으면 연결 실패(ClientException)다.
class FakeHeartTaskServer {
  FakeHeartTaskServer(Iterable<Map<String, Object?>> rows) : pending = [...rows];

  final List<Map<String, Object?>> pending;

  /// 대기 목록에 없는 건(이미 처리됨 · 51번째 이후) — 한 건 조회에만 답한다. 값은 `status` 를 포함한 한 줄.
  final Map<String, Map<String, Object?>> others = {};
  final Map<String, List<Map<String, Object?>>> previous = {};
  final Set<String> noPhoto = {};

  /// 첫 조회의 사진 주소가 깨진다(서명 만료) — 다시 받으면 멀쩡한 주소
  final Set<String> brokenOnce = {};

  /// 몇 번을 받아도 깨진 주소(깨진 파일)
  final Set<String> alwaysBroken = {};

  /// 다른 관리자가 먼저 처리한 건 — 승인 · 반려가 409
  final Set<String> takenElsewhere = {};

  int? listFailure;
  int? detailFailure;
  int? reviewFailure;
  Completer<void>? holdList;
  Completer<void>? holdDetail;
  Completer<void>? holdReview;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi('https://api.test', MockClient(_handle), () => 'token-test');

  int get listFetches => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/heart-tasks').length;
  int detailFetches(String id) => requests.where((r) => r.method == 'GET' && r.url.path == '/admin/heart-tasks/$id').length;

  /// 보낸 승인 · 반려 — "approve:s1" · "reject:s1:reused"
  List<String> get reviews => [
    for (final r in requests.where((r) => r.method == 'POST'))
      [r.url.pathSegments[3], r.url.pathSegments[2], if (r.body.isNotEmpty) (jsonDecode(r.body) as Map)['reason']].join(':'),
  ];

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.pathSegments;
    if (request.url.path == '/admin/me') return _json(200, const {});
    if (path.length == 2) {
      await holdList?.future;
      final failure = _fail(listFailure);
      if (failure != null) return failure;
      final task = request.url.queryParameters['task'];
      return _json(200, {
        'items': [for (final row in pending) if (task == null || row['task'] == task) row],
      });
    }
    final id = path[2];
    if (path.length == 3) {
      await holdDetail?.future;
      final failure = _fail(detailFailure);
      if (failure != null) return failure;
      final row = _find(id) ?? others[id];
      if (row == null) return _json(404, const {'detail': 'not_found'});
      return _json(200, _detail(row));
    }
    await holdReview?.future;
    final failure = _fail(reviewFailure);
    if (failure != null) return failure;
    if (takenElsewhere.contains(id)) {
      pending.removeWhere((r) => r['id'] == id);
      return _json(409, const {'detail': 'already_reviewed'});
    }
    final row = _find(id);
    if (row == null) return _json(404, const {'detail': 'not_found'});
    pending.remove(row);
    final approved = path[3] == 'approve';
    return _json(200, {..._detail(row), 'status': approved ? 'approved' : 'rejected'});
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
    final broken = alwaysBroken.contains(id) || (brokenOnce.contains(id) && fetch == 1);
    return {
      'status': 'submitted',
      ...row,
      'photo_url': noPhoto.contains(id) ? null : 'https://storage.test/$id.jpg?v=$fetch${broken ? '&broken' : ''}',
      'previous': previous[id] ?? const <Object?>[],
    };
  }

  static http.Response? _fail(int? status) {
    if (status == null) return null;
    if (status == 0) throw http.ClientException('offline');
    return _json(status, const {});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
}

/// 사진 주소 → 시험 그림. 'broken' 이 든 주소는 불러오다 실패한다(서명 만료 · 깨진 파일).
class TestProofImage extends ImageProvider<TestProofImage> {
  const TestProofImage(this.url, this.image);

  final String url;
  final ui.Image image;

  @override
  Future<TestProofImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(TestProofImage key, ImageDecoderCallback decode) {
    if (url.contains('broken')) {
      return OneFrameImageStreamCompleter(Future<ImageInfo>.error(StateError('사진을 불러오지 못함')));
    }
    return OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone())));
  }

  @override
  bool operator ==(Object other) => other is TestProofImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// 세로로 긴 캡처(9:19)를 흉내 낸 시험 그림. 엔진 일이라 runAsync 안에서 만든다.
Future<ui.Image> portraitTestImage(WidgetTester tester) async {
  return (await tester.runAsync(() => createTestImage(width: 90, height: 190)))!;
}
