import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/graduate_fakes.dart';

/// 졸업생 검수(A10) API — 서버 계약은 backend/app/admin/graduate_review.py
void main() {
  late List<http.Request> requests;

  AdminApi apiWith(http.Response Function(http.Request) respond) {
    requests = <http.Request>[];
    return AdminApi('https://api.test/', MockClient((request) async {
      requests.add(request);
      return respond(request);
    }), () => 'tok');
  }

  http.Response json(int status, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  test('목록은 기본이 대기(pending)이고 status 쿼리로 보낸다', () async {
    final api = apiWith((_) => json(200, {'items': [graduateRow('g1'), graduateRow('g2', attemptNo: 2)]}));

    final items = await api.listGraduateRequests();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/admin/graduate-requests');
    expect(requests.single.url.queryParameters, {'status': 'pending'});
    expect(items.map((i) => (i.id, i.attemptNo)), [('g1', 1), ('g2', 2)]);
  });

  test('다른 상태와 개수 한도도 보낼 수 있다', () async {
    final api = apiWith((_) => json(200, {'items': const <Object?>[]}));

    await api.listGraduateRequests(status: GraduateStatus.rejected, limit: 100);

    expect(requests.single.url.queryParameters, {'status': 'rejected', 'limit': '100'});
  });

  test('목록 모양이 틀리면 그 상태코드의 실패', () async {
    final api = apiWith((_) => json(200, {'rows': const <Object?>[]}));

    await expectLater(api.listGraduateRequests(), throwsA(isA<AdminApiFailure>()));
  });

  test('한 건은 GET /admin/graduate-requests/{id}', () async {
    final api = apiWith((_) => json(200, {
      ...graduateRow('g1'),
      'photo_url': 'https://storage.test/g1.jpg',
      'ocr': null,
      'previous_school_email': null,
      'warnings': const <Object?>[],
      'history': const <Object?>[],
    }));

    final detail = await api.fetchGraduateRequest('g1');

    expect(requests.single.url.path, '/admin/graduate-requests/g1');
    expect(detail.photoUrl, 'https://storage.test/g1.jpg');
  });

  test('꼴이 틀린 번호(경로 탈출)는 보내지 않고 404 처럼 실패한다', () async {
    final api = apiWith((_) => json(200, {}));

    for (final bad in ['../me', 'a/b', 'a%2Fb', '']) {
      await expectLater(api.fetchGraduateRequest(bad), throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'code', 404)));
      await expectLater(api.approveGraduate(bad, universityId: 'u', documentNumber: 'ABCD'), throwsA(isA<AdminApiFailure>()));
      await expectLater(api.rejectGraduate(bad, GraduateRejectReason.unreadable), throwsA(isA<AdminApiFailure>()));
    }
    expect(requests, isEmpty);
  });

  test('승인: POST …/approve 본문 키는 university_id · document_number · student_number', () async {
    final api = apiWith((_) => json(200, {}));

    await api.approveGraduate('g1', universityId: 'u-snu', documentNumber: ' A12B-3456-78CD ', studentNumber: ' 2021-0001 ');

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/admin/graduate-requests/g1/approve');
    expect(jsonDecode(request.body), {'university_id': 'u-snu', 'document_number': 'A12B-3456-78CD', 'student_number': '2021-0001'});
  });

  test('승인: 학번이 없거나 비면 student_number 칸을 보내지 않는다', () async {
    final api = apiWith((_) => json(200, {}));

    await api.approveGraduate('g1', universityId: 'u-snu', documentNumber: 'ABCD');
    await api.approveGraduate('g1', universityId: 'u-snu', documentNumber: 'ABCD', studentNumber: '   ');

    for (final request in requests) {
      expect(jsonDecode(request.body), {'university_id': 'u-snu', 'document_number': 'ABCD'});
    }
  });

  test('승인 응답 본문(결정된 한 건)은 읽지 않는다 — 모양이 틀려도 성공', () async {
    final api = apiWith((_) => json(200, {'weird': true}));

    await api.approveGraduate('g1', universityId: 'u', documentNumber: 'ABCD');
  });

  test('반려: POST …/reject 본문은 reason 코드 하나', () async {
    final api = apiWith((_) => json(200, {}));

    await api.rejectGraduate('g1', GraduateRejectReason.schoolUnsupported);

    expect(requests.single.url.path, '/admin/graduate-requests/g1/reject');
    expect(jsonDecode(requests.single.body), {'reason': 'school_unsupported'});
  });

  test('409 already_reviewed 는 AlreadyReviewed, 나머지 5개는 이유를 단 AdminApiFailure', () async {
    for (final code in ['already_verified', 'account_withdrawn', 'document_reused', 'student_reused', 'rejoin_blocked']) {
      final api = apiWith((_) => json(409, {'detail': code}));
      await expectLater(
        api.approveGraduate('g1', universityId: 'u', documentNumber: 'ABCD'),
        throwsA(isA<AdminApiFailure>().having((f) => (f.statusCode, f.reason), 'status+reason', (409, code))),
        reason: code,
      );
    }
    final api = apiWith((_) => json(409, {'detail': 'already_reviewed'}));
    await expectLater(api.rejectGraduate('g1', GraduateRejectReason.unreadable), throwsA(isA<AlreadyReviewed>()));
  });

  test('실패 예외에는 입력한 번호 · 학번이 실리지 않는다', () async {
    final api = apiWith((_) => json(422, {'detail': 'invalid_input'}));

    try {
      await api.approveGraduate('g1', universityId: 'u', documentNumber: 'SECRET-DOC-1', studentNumber: 'SECRET-STU-1');
      fail('실패해야 한다');
    } on AdminApiFailure catch (failure) {
      expect('${failure.statusCode} ${failure.reason}', isNot(contains('SECRET')));
    }
  });
}
