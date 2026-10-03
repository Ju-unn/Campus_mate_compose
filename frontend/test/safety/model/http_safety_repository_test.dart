import 'dart:convert';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/safety/model/http_safety_repository.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpSafetyRepository buildRepository(http.Client client) {
    return HttpSafetyRepository(ApiClient('https://api.test', client, auth));
  }

  http.Response jsonResponse(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// 요청 하나를 붙잡아 두고 [response] 를 돌려주는 가짜 서버.
  (MockClient, List<http.Request>) recording(http.Response response) {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return response;
    });
    return (client, seen);
  }

  group('신고', () {
    test('프로필 신고는 profile 대상으로 보내고, 기타가 아니면 메모를 싣지 않는다', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}, 201));

      final result = await buildRepository(client).report(
        target: const ReportTarget.profile('p2'),
        reason: ReportReason.abuse,
        // 기타에서 쓰다가 사유를 바꾼 경우 — 서버가 무시하더라도 애초에 보내지 않는다.
        note: '남은 메모',
      );

      expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.test/reports');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      expect(jsonDecode(request.body), {
        'target_type': 'profile',
        'target_id': 'p2',
        'reason': 'abuse',
      });
    });

    test('메시지 신고는 말풍선 id 를 target_id 로, 기타 메모는 다듬어서 싣는다', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}, 201));

      await buildRepository(client).report(
        target: const ReportTarget.message('msg-7'),
        reason: ReportReason.other,
        note: '  외부 링크를 계속 보내요 ',
      );

      expect(jsonDecode(seen.single.body), {
        'target_type': 'message',
        'target_id': 'msg-7',
        'reason': 'other',
        'reason_note': '외부 링크를 계속 보내요',
      });
    });

    test('투표 글 신고는 글 id 를 target_id 로, 대상은 poll(A16 · 서버 #191)', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}, 201));

      await buildRepository(client).report(target: const ReportTarget.poll('poll-3'), reason: ReportReason.spam);

      expect(jsonDecode(seen.single.body), {'target_type': 'poll', 'target_id': 'poll-3', 'reason': 'spam'});
    });

    test('기타여도 메모가 공백뿐이면 reason_note 를 싣지 않는다', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}, 201));

      await buildRepository(client).report(
        target: const ReportTarget.profile('p2'),
        reason: ReportReason.other,
        note: '   ',
      );

      expect((jsonDecode(seen.single.body) as Map).containsKey('reason_note'), isFalse);
    });

    test('중복 신고 409 는 서버 문구를 담은 실패로 돌려준다', () async {
      final (client, _) = recording(jsonResponse({'detail': '이미 신고한 사용자예요'}, 409));

      final result = await buildRepository(client).report(
        target: const ReportTarget.profile('p2'),
        reason: ReportReason.spam,
      );

      final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
      expect(failure!.toDisplayMessage(), '이미 신고한 사용자예요');
    });

    test('하루 상한 429 는 RateLimitedFailure 로 온다', () async {
      final (client, _) = recording(jsonResponse({'detail': '너무 많이 신고했어요'}, 429));

      final result = await buildRepository(client).report(
        target: const ReportTarget.profile('p2'),
        reason: ReportReason.fake,
      );

      expect(result.when(onSuccess: (_) => null, onFailure: (failure) => failure),
          isA<RateLimitedFailure>());
    });
  });

  group('차단', () {
    test('차단은 POST /blocks/{profileId}', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}));

      final result = await buildRepository(client).block('p2');

      expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
      expect(seen.single.method, 'POST');
      expect(seen.single.url.toString(), 'https://api.test/blocks/p2');
    });

    test('해제는 DELETE /blocks/{profileId}', () async {
      final (client, seen) = recording(jsonResponse({'ok': true}));

      final result = await buildRepository(client).unblock('p2');

      expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
      expect(seen.single.method, 'DELETE');
      expect(seen.single.url.toString(), 'https://api.test/blocks/p2');
    });

    test('차단 목록을 읽고 차단일은 기기 시간대로 바꾼다', () async {
      final (client, seen) = recording(jsonResponse({
        'blocks': [
          {
            'profile_id': 'p2',
            'nickname': '여우비',
            'avatar_url': 'https://cdn.test/a.png',
            'blocked_at': '2026-09-27T05:00:00+00:00',
          },
          {
            'profile_id': 'p3',
            'nickname': '소나기',
            'avatar_url': null,
            'blocked_at': '2026-09-26T05:00:00+00:00',
          },
        ],
      }));

      final result = await buildRepository(client).fetchBlocks();

      expect(seen.single.method, 'GET');
      expect(seen.single.url.toString(), 'https://api.test/blocks');
      final blocks = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
      expect(blocks.map((user) => user.profileId), ['p2', 'p3']);
      expect(blocks.first.nickname, '여우비');
      expect(blocks.first.avatarUrl, 'https://cdn.test/a.png');
      expect(blocks.last.avatarUrl, isNull);
      expect(blocks.first.blockedAt, DateTime.utc(2026, 9, 27, 5).toLocal());
      expect(blocks.first.blockedAt.isUtc, isFalse);
    });
  });

  group('상대 프로필(14c)', () {
    /// `GET /cards/{card_id}` 와 같은 키에 card_id 대신 match_id. 게이트 전 모양이다.
    Map<String, dynamic> partnerJson() => {
          'match_id': 'm-1',
          'profile': {
            'profile_id': 'p2',
            'nickname': '여우비',
            'age': 23,
            'university': '서울대학교',
            'major': '컴퓨터공학과',
            'avatar_url': 'https://cdn.test/a.png',
          },
          'survey': List.filled(9, 0.5),
          'animal_type': 'cat',
          'impression_type': 'chic',
          'religion': 'none',
          'is_smoker': false,
          'interests': ['등산'],
          'my_traits': ['유머러스'],
          'ideal_traits': ['다정한'],
          'height_cm': 170,
          'mbti': 'INFP',
          'student_number': '22',
          'bio': '안녕하세요',
          'ideal_note': null,
        };

    test('GET /profiles/{profileId} 를 부른다', () async {
      final (client, seen) = recording(jsonResponse(partnerJson()));

      await buildRepository(client).fetchPartnerProfile('p2');

      expect(seen.single.method, 'GET');
      expect(seen.single.url.toString(), 'https://api.test/profiles/p2');
    });

    test('게이트 전에는 카톡 · 실사진 키가 없어 가려진 프로필로 읽는다', () async {
      final (client, _) = recording(jsonResponse(partnerJson()));

      final result = await buildRepository(client).fetchPartnerProfile('p2');

      final profile = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
      expect(profile.matchId, 'm-1');
      expect(profile.detail.profile.nickname, '여우비');
      expect(profile.detail.mbti, 'INFP');
      expect(profile.isRevealed, isFalse);
      expect(profile.kakaoId, isNull);
      expect(profile.photoUrls, isNull);
    });

    test('게이트 뒤에는 카톡 아이디와 실사진 URL 을 읽는다', () async {
      final (client, _) = recording(jsonResponse({
        ...partnerJson(),
        'kakao_id': 'foxrain',
        'photo_urls': ['https://cdn.test/1.jpg', 'https://cdn.test/2.jpg'],
      }));

      final result = await buildRepository(client).fetchPartnerProfile('p2');

      final profile = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
      expect(profile.isRevealed, isTrue);
      expect(profile.kakaoId, 'foxrain');
      expect(profile.photoUrls, ['https://cdn.test/1.jpg', 'https://cdn.test/2.jpg']);
    });

    test('게이트 뒤라도 카톡 아이디를 안 적은 사람이면 kakao_id 가 null 이다', () async {
      final (client, _) = recording(jsonResponse({
        ...partnerJson(),
        'kakao_id': null,
        'photo_urls': <String>[],
      }));

      final result = await buildRepository(client).fetchPartnerProfile('p2');

      final profile = result.when(onSuccess: (value) => value, onFailure: (_) => null)!;
      expect(profile.isRevealed, isTrue);
      expect(profile.kakaoId, isNull);
      expect(profile.photoUrls, isEmpty);
    });

    test('404 는 서버 문구를 담은 실패로 온다', () async {
      final (client, _) = recording(jsonResponse({'detail': '프로필을 찾을 수 없어요'}, 404));

      final result = await buildRepository(client).fetchPartnerProfile('p2');

      final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure)!;
      expect(failure.toDisplayMessage(), '프로필을 찾을 수 없어요');
    });
  });
}
