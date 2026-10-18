import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

/// W4 가 부르는 서버 경로 · 쿼리(D4 계획서 표, D3 action_log.py)
void main() {
  late FakeStatsServer server;
  late AdminApi api;

  setUp(() {
    server = FakeStatsServer();
    api = server.api();
  });

  Uri lastUrl() => server.requests.last.url;

  group('홈', () {
    test('GET /admin/stats', () async {
      final stats = await api.homeStats();
      expect(lastUrl().path, '/admin/stats');
      expect(stats.openReports, 5);
    });

    test('GET /admin/stats/daily?days=30', () async {
      final days = await api.statsDaily();
      expect(lastUrl().path, '/admin/stats/daily');
      expect(lastUrl().queryParameters, {'days': '30'});
      expect(days.length, 30);
    });

    test('GET /admin/universities — 기본은 빈 학교 빼고, includeEmpty 면 include_empty=true', () async {
      await api.universities();
      expect(lastUrl().queryParameters, {'include_empty': 'false'});
      final all = await api.universities(includeEmpty: true);
      expect(lastUrl().queryParameters, {'include_empty': 'true'});
      expect(all.first.name, '서울대학교');
    });

    test('GET /admin/health', () async {
      final health = await api.health();
      expect(lastUrl().path, '/admin/health');
      expect(health.items.length, 5);
    });

    test('실패는 AdminApiFailure(상태코드)', () async {
      server.statsFailure = 500;
      await expectLater(api.homeStats(), throwsA(isA<AdminApiFailure>().having((f) => f.statusCode, 'status', 500)));
    });

    test('모양이 틀린 본문도 그 상태코드의 실패', () async {
      server.stats = {'wrong': 1};
      await expectLater(api.homeStats(), throwsA(isA<AdminApiFailure>()));
    });
  });

  test('GET /admin/unknown-domains', () async {
    final rows = await api.unknownDomains();
    expect(lastUrl().path, '/admin/unknown-domains');
    expect(rows.map((r) => r.attemptCount), [12, 7, 3]);
  });

  group('매칭', () {
    test('summary · daily?days=30', () async {
      final summary = await api.matchingSummary();
      expect(lastUrl().path, '/admin/matching/summary');
      expect(summary.acceptsTotal, 436);
      final days = await api.matchingDaily();
      expect(lastUrl().path, '/admin/matching/daily');
      expect(lastUrl().queryParameters, {'days': '30'});
      expect(days.length, 30);
    });

    test('pairs: 필터가 없으면 쿼리도 없다', () async {
      final page = await api.matchingPairs();
      expect(lastUrl().path, '/admin/matching/pairs');
      expect(lastUrl().queryParameters, isEmpty);
      expect(page.items.length, 7);
      expect(page.nextBefore, isNull);
    });

    test('pairs: status · university · before 가 그대로 쿼리로 — before 의 | · + 는 퍼센트 인코딩', () async {
      await api.matchingPairs(status: 'shared', university: 'uni-서울대학교', before: '2026-10-18T05:02:00+00:00|m1');
      expect(lastUrl().queryParameters, {'status': 'shared', 'university': 'uni-서울대학교', 'before': '2026-10-18T05:02:00+00:00|m1'});
      expect(lastUrl().query, contains('%2B00%3A00%7Cm1'));
    });

    test('before 는 서버가 준 next_before 글자 그대로(소수 초 · Z 꼴도 다시 만들지 않는다) — 인코딩만 Uri 가 한다', () async {
      for (final cursor in ['2026-10-18T05:02:00.123456+00:00|m1', '2026-10-18T05:02:00Z|m1']) {
        await api.matchingPairs(before: cursor);
        expect(lastUrl().queryParameters['before'], cursor);
        await api.listActions(before: cursor);
        expect(lastUrl().queryParameters['before'], cursor);
      }
    });

    test('pairs: next_before 를 돌려준다', () async {
      server.pageSize = 3;
      final page = await api.matchingPairs();
      expect(page.items.length, 3);
      expect(page.nextBefore, '2026-10-17T12:10:00+00:00|m3');
    });
  });

  group('작업 기록', () {
    test('GET /admin/actions — 필터가 없으면 쿼리 없이', () async {
      final page = await api.listActions();
      expect(lastUrl().path, '/admin/actions');
      expect(lastUrl().queryParameters, isEmpty);
      expect(page.items.length, 3);
    });

    test('target · before 를 쿼리로(서버 이름 그대로)', () async {
      await api.listActions(target: 'a0000000-0000-4000-8000-000000000001', before: '2026-10-18T05:30:00+00:00|a1');
      expect(lastUrl().queryParameters, {'target': 'a0000000-0000-4000-8000-000000000001', 'before': '2026-10-18T05:30:00+00:00|a1'});
    });
  });

  test('읽기만 한다 — 어떤 경로도 GET 이외를 보내지 않는다', () async {
    await api.homeStats();
    await api.matchingPairs();
    await api.listActions();
    await api.unknownDomains();
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
  });
}
