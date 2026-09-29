import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/me/model/http_me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 편집 화면이 쓰는 새 키(계획서 2-1). 기존 13키는 그대로 온다.
const _editKeys = <String, Object?>{
  'interest_tags': ['카페가기', '여행', '요리'],
  'my_traits': ['유머러스', '성실한', '차분한'],
  'ideal_traits': ['다정한', '연락 잘하는', '솔직한'],
  'preferred_mbti_flags': {'E': true, 'N': true},
  'preferred_animal_types': ['dog', 'fox'],
  'preferred_impression_types': ['kind'],
  'photos': [
    {'id': 'p-a', 'url': 'https://img.test/1.png', 'is_avatar_source': false},
    {'id': 'p-b', 'url': 'https://img.test/2.png', 'is_avatar_source': true},
  ],
  'heart_balance': 30,
  'avatar_regen_cost': 10,
  'nickname_changeable_at': '2026-10-27T14:00:00+09:00',
};

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
  });

  HttpMeRepository buildRepository(http.Client client) => HttpMeRepository(ApiClient('https://api.test', client, auth));

  http.Response jsonResponse(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  MyProfile? profileOf(Result<MyProfile> result) => result.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);

  test('GET /me/profile 의 값을 MyProfile 로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/me/profile');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      return jsonResponse({
        'nickname': '여우',
        'age': 23,
        'university': '가나대학교',
        'major': '경영학과',
        'height_cm': 178,
        'mbti': 'ENFP',
        'avatar_url': 'https://img.test/avatar.png',
        'photo_urls': ['https://img.test/1.png', 'https://img.test/2.png'],
        'preferred_age_min': 22,
        'preferred_age_max': 27,
        'preferred_height_min': 165,
        'preferred_height_max': 180,
        'bio': '주말엔 산책해요.',
        ..._editKeys,
      });
    });

    final profile = profileOf(await buildRepository(client).fetchProfile())!;

    expect(profile.nickname, '여우');
    expect(profile.age, 23);
    expect(profile.university, '가나대학교');
    expect(profile.major, '경영학과');
    expect(profile.heightCm, 178);
    expect(profile.mbti, 'ENFP');
    expect(profile.avatarUrl, 'https://img.test/avatar.png');
    expect(profile.photoUrls, ['https://img.test/1.png', 'https://img.test/2.png']);
    expect(profile.preferredAgeMin, 22);
    expect(profile.preferredAgeMax, 27);
    expect(profile.preferredHeightMin, 165);
    expect(profile.preferredHeightMax, 180);
    expect(profile.bio, '주말엔 산책해요.');
  });

  test('null 일 수 있는 값이 비어 오면 null 로 읽는다', () async {
    final client = MockClient((_) async => jsonResponse({
          'nickname': '여우',
          'age': null,
          'university': '가나대학교',
          'major': null,
          'height_cm': null,
          'mbti': null,
          'avatar_url': null,
          'photo_urls': <String>[],
          'preferred_age_min': null,
          'preferred_age_max': null,
          'preferred_height_min': null,
          'preferred_height_max': null,
          'bio': null,
          ..._editKeys,
          'photos': <Object>[],
          'nickname_changeable_at': null,
        }));

    final profile = profileOf(await buildRepository(client).fetchProfile())!;

    expect(profile.nickname, '여우');
    expect(profile.university, '가나대학교');
    expect(
      [
        profile.age,
        profile.major,
        profile.heightCm,
        profile.mbti,
        profile.avatarUrl,
        profile.preferredAgeMin,
        profile.preferredAgeMax,
        profile.preferredHeightMin,
        profile.preferredHeightMax,
        profile.bio,
      ],
      everyElement(isNull),
    );
    expect(profile.photoUrls, isEmpty);
  });

  test('편집 화면이 쓰는 새 키를 읽는다 — 태그 3종 · 06-1 선호 · 사진 행 · 하트 · 닉네임 풀리는 때', () async {
    final client = MockClient((_) async => jsonResponse({
          'nickname': '여우',
          'age': 23,
          'university': '가나대학교',
          'major': null,
          'height_cm': null,
          'mbti': null,
          'avatar_url': null,
          'photo_urls': ['https://img.test/1.png', 'https://img.test/2.png'],
          'preferred_age_min': 22,
          'preferred_age_max': 27,
          'preferred_height_min': null,
          'preferred_height_max': null,
          'bio': null,
          ..._editKeys,
        }));

    final profile = profileOf(await buildRepository(client).fetchProfile())!;

    expect(profile.interestTags, ['카페가기', '여행', '요리']);
    expect(profile.myTraits, ['유머러스', '성실한', '차분한']);
    expect(profile.idealTraits, ['다정한', '연락 잘하는', '솔직한']);
    expect(profile.preferredMbtiFlags, {'E': true, 'N': true});
    expect(profile.preferredAnimalTypes, [AnimalType.dog, AnimalType.fox]);
    expect(profile.preferredImpressionTypes, [ImpressionType.kind]);
    expect([for (final photo in profile.photos) (photo.id, photo.url, photo.isAvatarSource)], [
      ('p-a', 'https://img.test/1.png', false),
      ('p-b', 'https://img.test/2.png', true),
    ]);
    expect(profile.heartBalance, 30);
    expect(profile.avatarRegenCost, 10);
    // 다른 날짜 칸(chat_room.dart)처럼 기기 시간대로 바꿔 둔다 — 15d-2 "M월 D일" 은 기기 날짜로 적는다.
    final changeableAt = profile.nicknameChangeableAt!;
    expect(changeableAt.isUtc, isFalse);
    expect(changeableAt.isAtSameMomentAs(DateTime.utc(2026, 10, 27, 5)), isTrue);
  });

  test('닉네임을 지금 바꿀 수 있으면(null) 풀리는 때도 null 이다', () async {
    final client = MockClient((_) async => jsonResponse({
          'nickname': '여우',
          'age': null,
          'university': '가나대학교',
          'major': null,
          'height_cm': null,
          'mbti': null,
          'avatar_url': null,
          'photo_urls': <String>[],
          'preferred_age_min': null,
          'preferred_age_max': null,
          'preferred_height_min': null,
          'preferred_height_max': null,
          'bio': null,
          ..._editKeys,
          'nickname_changeable_at': null,
        }));

    expect(profileOf(await buildRepository(client).fetchProfile())!.nicknameChangeableAt, isNull);
  });

  test('photoUrls 는 사진 행의 url 을 자리 순서 그대로 모은 것이다(화면 15 가 읽는다)', () {
    const profile = MyProfile(
      nickname: '여우',
      age: null,
      university: '가나대학교',
      major: null,
      heightCm: null,
      mbti: null,
      avatarUrl: null,
      preferredAgeMin: null,
      preferredAgeMax: null,
      preferredHeightMin: null,
      preferredHeightMax: null,
      bio: null,
      photos: [
        MyPhoto(id: 'p-a', url: 'https://img.test/a.png', isAvatarSource: true),
        MyPhoto(id: 'p-b', url: 'https://img.test/b.png', isAvatarSource: false),
      ],
    );

    expect(profile.photoUrls, ['https://img.test/a.png', 'https://img.test/b.png']);
  });

  group('updateProfile — PATCH /me/profile 는 보낸 칸만 고친다(계획서 2-5)', () {
    Future<(http.Request, Result<void>)> patch(Future<Result<void>> Function(HttpMeRepository) call) async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return jsonResponse({'ok': true});
      });
      final result = await call(buildRepository(client));
      return (sent, result);
    }

    test('15c 는 자기소개만 보낸다', () async {
      final (request, result) = await patch((repository) => repository.updateProfile(bio: '소개'));

      expect(request.method, 'PATCH');
      expect(request.url.toString(), 'https://api.test/me/profile');
      expect(request.headers['Authorization'], 'Bearer token-abc');
      expect(jsonDecode(request.body), {'bio': '소개'});
      expect(result, isA<Success<void>>());
    });

    test('15d 는 닉네임 · 키만 보낸다 — null 인 칸은 본문에서 뺀다', () async {
      final (request, _) = await patch((repository) => repository.updateProfile(nickname: '바다', heightCm: 180));

      expect(jsonDecode(request.body), {'nickname': '바다', 'height_cm': 180});
    });

    test('서버가 거절하면 실패를 돌려준다', () async {
      final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

      final result = await buildRepository(client).updateProfile(bio: '소개');

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
    });
  });

  group('fetchCardPreview — GET /me/card-preview 는 10b 카드 상세 몸통이다(계획서 2026-09-28-me-profile.md 2절)', () {
    const body = <String, Object?>{
      'profile': {
        'profile_id': 'me-1',
        'nickname': '하늘',
        'age': 24,
        'university': '서울대학교',
        'major': '컴퓨터공학과',
        'avatar_url': null,
      },
      'survey': [0.1, 0.2, 0.3, 0.4, 0.0, 0.6, 0.7, 0.8, 0.9],
      'animal_type': 'fox',
      'impression_type': 'kind',
      'religion': 'none',
      'is_smoker': false,
      'interests': ['카페가기', '여행', '요리'],
      'my_traits': ['긍정적인', '성실한', '차분한'],
      'ideal_traits': ['다정한', '연락 잘하는', '솔직한'],
      'height_cm': 178,
      'mbti': 'ENFP',
      'student_number': '22',
      'bio': '주말엔 산책해요',
      'ideal_note': null,
    };

    test('카드 상세로 읽고 card_id 자리에 내 profile_id 를 넣는다', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://api.test/me/card-preview');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        return jsonResponse(body);
      });

      final result = await buildRepository(client).fetchCardPreview();
      final detail = result.when<CardDetail?>(onSuccess: (d) => d, onFailure: (_) => null)!;

      expect(detail.cardId, 'me-1');
      expect(detail.profile.nameWithAge, '하늘, 24');
      expect(detail.profile.schoolLine, '서울대학교 · 컴퓨터공학과');
      expect(detail.animalType, AnimalType.fox);
      expect(detail.interests, ['카페가기', '여행', '요리']);
      expect(detail.bio, '주말엔 산책해요');
      expect(detail.idealNote, isNull);
    });

    test('서버 오류면 실패를 돌려준다', () async {
      final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

      final result = await buildRepository(client).fetchCardPreview();

      expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
    });
  });

  group('savePhotos — PUT /me/photos 는 칸 순서를 한 번에 보낸다(계획서 2026-09-27-me-edit.md 2-2 · U2)', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('me_photos_test'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    File photoFile(String name) => File('${tempDir.path}/$name')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);

    /// multipart 글자 칸 하나 — 이름 줄 뒤 빈 줄, 값, 줄바꿈(http 패키지가 쓰는 모양).
    String field(String name, String value) => 'name="$name"\r\n\r\n$value\r\n';

    test('남길 사진은 keep, 새 사진은 new 번호로 — layout · avatar_source · 파일 칸 photos', () async {
      late String body;
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.toString(), 'https://api.test/me/photos');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        expect(request.headers['content-type'], startsWith('multipart/form-data'));
        // 본문에 JPEG 바이트(0xFF)가 섞여 utf8 로는 못 읽는다.
        body = latin1.decode(request.bodyBytes);
        return jsonResponse({'ok': true});
      });

      final result = await buildRepository(client).savePhotos([const KeptPhoto('p-a'), NewPhoto(photoFile('new.jpg'))], 1);

      expect(result, isA<Success<void>>());
      expect(body, contains(field('layout', '[{"keep":"p-a"},{"new":0}]')));
      expect(body, contains(field('avatar_source', '1')));
      expect('name="photos"'.allMatches(body), hasLength(1));
      expect(body, contains('filename="new.jpg"'));
    });

    test('새 사진 번호는 칸 순서대로 매기고 파일도 그 순서로 새 사진 수만큼 붙인다', () async {
      late String body;
      final client = MockClient((request) async {
        body = latin1.decode(request.bodyBytes);
        return jsonResponse({'ok': true});
      });

      await buildRepository(client).savePhotos(
        [NewPhoto(photoFile('first.jpg')), const KeptPhoto('p-a'), NewPhoto(photoFile('second.jpg'))],
        0,
      );

      expect(body, contains(field('layout', '[{"new":0},{"keep":"p-a"},{"new":1}]')));
      expect('name="photos"'.allMatches(body), hasLength(2));
      expect(body.indexOf('filename="first.jpg"'), lessThan(body.indexOf('filename="second.jpg"')));
    });

    test('남길 사진만 순서를 바꾸면 파일 칸이 없다', () async {
      late String body;
      final client = MockClient((request) async {
        body = latin1.decode(request.bodyBytes);
        return jsonResponse({'ok': true});
      });

      await buildRepository(client).savePhotos(const [KeptPhoto('p-b'), KeptPhoto('p-a')], 1);

      expect(body, contains(field('layout', '[{"keep":"p-b"},{"keep":"p-a"}]')));
      expect(body, isNot(contains('name="photos"')));
    });

    test('409 PHOTOS_CHANGED 는 서버 문구를 그대로 돌려준다', () async {
      final client = MockClient((_) async => jsonResponse({'detail': '사진이 바뀌었어요, 다시 열어 주세요'}, 409));

      final result = await buildRepository(client).savePhotos(const [KeptPhoto('p-a'), KeptPhoto('p-b')], 0);

      expect(
        result.when(onSuccess: (_) => null, onFailure: (failure) => failure.toDisplayMessage()),
        '사진이 바뀌었어요, 다시 열어 주세요',
      );
    });
  });

  test('서버 오류면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'detail': 'boom'}, 500));

    final result = await buildRepository(client).fetchProfile();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<Failure>());
  });

  test('약속과 다른 모양이면 실패를 돌려준다', () async {
    final client = MockClient((_) async => jsonResponse({'nickname': 3}));

    final result = await buildRepository(client).fetchProfile();

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<UnknownFailure>());
  });
}
