import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시험은 기다림을 0 으로 둔다 — 0 짜리 타이머도 한 바퀴는 돌아야 쓰이므로 [_settle] 로 한 바퀴 돌린다.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

Map<String, Object?> _identity(Map<String, Object?> data) => data;

void main() {
  late SharedPreferences preferences;
  late String? account;

  /// [fileDirectory] 는 앱 임시 폴더 자리다. 시험에서는 시스템 임시 폴더를 쓴다.
  SharedPreferencesDraftStore store({Duration debounce = Duration.zero, String? fileDirectory}) => SharedPreferencesDraftStore(
        preferences,
        accountId: () => account,
        fileDirectory: fileDirectory ?? Directory.systemTemp.path,
        debounce: debounce,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    account = 'account-a';
  });

  group('쓰고 읽기', () {
    test('쓴 값을 그대로 읽는다', () async {
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': '같이 산책할 사람'});
      await _settle();

      expect(drafts.read(DraftScreen.idealNote, _identity), {'note': '같이 산책할 사람'});
    });

    test('키는 onboarding_draft/{계정 id}/{화면 키} 이고 값은 버전 번호를 담은 JSON 이다', () async {
      store().write(DraftScreen.bio, {'bio': '안녕하세요'});
      await _settle();

      final raw = preferences.getString('onboarding_draft/account-a/bio');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['version'], SharedPreferencesDraftStore.version);
      expect(json['data'], {'bio': '안녕하세요'});
    });

    test('아무것도 안 쓴 화면은 null', () {
      expect(store().read(DraftScreen.survey, _identity), isNull);
    });

    test('새로 만든 저장소(앱을 다시 연 것)도 디스크에서 읽는다', () async {
      store().write(DraftScreen.idealNote, {'note': '다시 열어도 남는다'});
      await _settle();

      expect(store().read(DraftScreen.idealNote, _identity), {'note': '다시 열어도 남는다'});
    });

    test('로그인 전(계정 id 가 없음)에는 쓰지도 읽지도 않는다', () async {
      account = null;
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': '주인 없는 값'});
      await _settle();

      expect(preferences.getKeys(), isEmpty);
      expect(drafts.read(DraftScreen.idealNote, _identity), isNull);
    });
  });

  group('계정별 분리', () {
    test('다른 계정 id 로는 앞 계정 값이 보이지 않는다', () async {
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': 'A 가 쓰던 글'});
      await _settle();

      account = 'account-b';
      expect(drafts.read(DraftScreen.idealNote, _identity), isNull);
    });

    test('계정이 바뀌면 옛 계정 값은 지운다', () async {
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': 'A 가 쓰던 글'});
      await _settle();

      account = 'account-b';
      drafts.read(DraftScreen.bio, _identity);
      await _settle();

      expect(preferences.getKeys().where((key) => key.contains('account-a')), isEmpty);
      account = 'account-a';
      expect(drafts.read(DraftScreen.idealNote, _identity), isNull);
    });

    test('같은 계정의 다른 화면 값은 서로 섞이지 않는다', () async {
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': '글'});
      drafts.write(DraftScreen.bio, {'bio': '소개'});
      await _settle();

      expect(drafts.read(DraftScreen.idealNote, _identity), {'note': '글'});
      expect(drafts.read(DraftScreen.bio, _identity), {'bio': '소개'});
    });
  });

  group('맞지 않는 값은 조용히 버린다', () {
    test('버전이 다르면 버리고 null', () async {
      // 앱 업데이트로 모양이 바뀐 뒤 옛 값을 만난 경우다.
      await preferences.setString(
        'onboarding_draft/account-a/bio',
        jsonEncode({'version': 999, 'data': {'bio': '옛 모양'}}),
      );

      expect(store().read(DraftScreen.bio, _identity), isNull);
      expect(preferences.getString('onboarding_draft/account-a/bio'), isNull);
    });

    test('깨진 JSON 이면 버리고 null', () async {
      await preferences.setString('onboarding_draft/account-a/bio', '{not json');

      expect(store().read(DraftScreen.bio, _identity), isNull);
      expect(preferences.getString('onboarding_draft/account-a/bio'), isNull);
    });

    test('봉투 모양이 다르면(데이터가 맵이 아님) 버리고 null', () async {
      await preferences.setString(
        'onboarding_draft/account-a/bio',
        jsonEncode({'version': SharedPreferencesDraftStore.version, 'data': ['목록']}),
      );

      expect(store().read(DraftScreen.bio, _identity), isNull);
    });

    test('화면이 읽다가 모양이 안 맞아 던지면 버리고 null', () async {
      final drafts = store();
      drafts.write(DraftScreen.bio, {'bio': 42});
      await _settle();

      expect(drafts.read(DraftScreen.bio, (data) => data['bio'] as String), isNull);
      expect(preferences.getString('onboarding_draft/account-a/bio'), isNull);
    });
  });

  group('지우기', () {
    test('한 화면만 지우면 다른 화면은 남는다', () async {
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': '글'});
      drafts.write(DraftScreen.bio, {'bio': '소개'});
      await _settle();

      await drafts.clear(DraftScreen.idealNote);

      expect(drafts.read(DraftScreen.idealNote, _identity), isNull);
      expect(drafts.read(DraftScreen.bio, _identity), {'bio': '소개'});
    });

    test('전부 지우면 모든 계정의 값이 사라지고 다른 앱 설정은 남는다', () async {
      await preferences.setString('onboarding_draft/account-z/bio', 'z');
      await preferences.setString('unrelated', 'keep');
      final drafts = store();
      drafts.write(DraftScreen.idealNote, {'note': '글'});
      await _settle();

      await drafts.clearAll();

      expect(preferences.getKeys(), {'unrelated'});
    });

    test('아직 기다리는 쓰기도 지우면 취소된다 — 지운 뒤 되살아나지 않는다', () async {
      final drafts = store(debounce: const Duration(milliseconds: 20));
      drafts.write(DraftScreen.idealNote, {'note': '늦게 쓰일 글'});
      await drafts.clearAll();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(preferences.getKeys(), isEmpty);
    });

    test('한 화면 지우기도 그 화면의 기다리는 쓰기를 취소한다', () async {
      final drafts = store(debounce: const Duration(milliseconds: 20));
      drafts.write(DraftScreen.idealNote, {'note': '늦게 쓰일 글'});
      await drafts.clear(DraftScreen.idealNote);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(preferences.getKeys(), isEmpty);
    });
  });

  group('딸린 파일(사진)', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('draft_files'));
    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    File photo(String name) => File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

    test('한 화면을 지우면 그 값에 딸린 파일도 지운다', () async {
      final first = photo('a.jpg');
      final second = photo('b.jpg');
      final drafts = store();
      drafts.write(DraftScreen.photos, {'n': 2}, files: [first.path, second.path]);
      await _settle();

      await drafts.clear(DraftScreen.photos);

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    test('전부 지우면 모든 계정의 딸린 파일도 지운다', () async {
      final mine = photo('mine.jpg');
      final drafts = store();
      drafts.write(DraftScreen.photos, {'n': 1}, files: [mine.path]);
      await _settle();
      account = 'account-b';
      final theirs = photo('theirs.jpg');
      drafts.write(DraftScreen.photos, {'n': 1}, files: [theirs.path]);
      await _settle();

      await drafts.clearAll();

      expect(mine.existsSync(), isFalse);
      expect(theirs.existsSync(), isFalse);
    });

    test('아직 디스크에 안 쓰인 값의 파일도 지운다', () async {
      final pending = photo('pending.jpg');
      final drafts = store(debounce: const Duration(milliseconds: 20));
      drafts.write(DraftScreen.photos, {'n': 1}, files: [pending.path]);

      await drafts.clear(DraftScreen.photos);

      expect(pending.existsSync(), isFalse);
    });

    test('앱 임시 폴더 안의 파일은 지우고, 밖의 파일은 지우지 않고 건너뛴다', () async {
      // 저장된 경로를 그대로 믿지 않는다 — 압축이 실패해 원본 경로가 남는 길이 있다(image_compressor.dart).
      final outsideDir = Directory.systemTemp.createTempSync('draft_outside');
      addTearDown(() => outsideDir.deleteSync(recursive: true));
      final outside = File('${outsideDir.path}/original.jpg')..writeAsBytesSync([1]);
      final inside = photo('compressed.jpg');
      final drafts = store(fileDirectory: dir.path);
      drafts.write(DraftScreen.photos, {'n': 2}, files: [outside.path, inside.path]);
      await _settle();

      await drafts.clear(DraftScreen.photos);

      expect(inside.existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
    });

    test('.. 로 앱 임시 폴더를 빠져나가는 경로도 건너뛴다', () async {
      final inner = Directory('${dir.path}/app_tmp')..createSync();
      final escaped = photo('escaped.jpg');
      final drafts = store(fileDirectory: inner.path);
      drafts.write(DraftScreen.photos, {'n': 1}, files: ['${inner.path}/../escaped.jpg']);
      await _settle();

      await drafts.clearAll();

      expect(escaped.existsSync(), isTrue);
    });

    test('앱 임시 폴더와 이름만 앞부분이 같은 이웃 폴더의 파일도 건너뛴다', () async {
      final inner = Directory('${dir.path}/tmp')..createSync();
      final neighbour = Directory('${dir.path}/tmp_other')..createSync();
      final file = File('${neighbour.path}/x.jpg')..writeAsBytesSync([1]);
      final drafts = store(fileDirectory: inner.path);
      drafts.write(DraftScreen.photos, {'n': 1}, files: [file.path]);
      await _settle();

      await drafts.clear(DraftScreen.photos);

      expect(file.existsSync(), isTrue);
    });

    test('이미 없어진 파일은 건너뛴다(던지지 않는다)', () async {
      final drafts = store();
      drafts.write(DraftScreen.photos, {'n': 1}, files: ['${dir.path}/gone.jpg']);
      await _settle();

      await expectLater(drafts.clear(DraftScreen.photos), completes);
    });
  });

  group('디바운스', () {
    testWidgets('짧은 간격으로 여러 번 바꿔도 마지막 값만 한 번 저장한다', (tester) async {
      final drafts = store(debounce: SharedPreferencesDraftStore.defaultDebounce);
      final writes = <String?>[];
      drafts.write(DraftScreen.idealNote, {'note': '가'});
      await tester.pump(const Duration(milliseconds: 200));
      drafts.write(DraftScreen.idealNote, {'note': '가나'});
      await tester.pump(const Duration(milliseconds: 200));
      drafts.write(DraftScreen.idealNote, {'note': '가나다'});
      await tester.pump(const Duration(milliseconds: 200));
      writes.add(preferences.getString('onboarding_draft/account-a/ideal_note'));

      await tester.pump(SharedPreferencesDraftStore.defaultDebounce);
      writes.add(preferences.getString('onboarding_draft/account-a/ideal_note'));

      expect(writes.first, isNull, reason: '마지막 입력 뒤 500ms 가 지나기 전에는 디스크를 건드리지 않는다');
      expect(jsonDecode(writes.last!)['data'], {'note': '가나다'});
    });

    testWidgets('기다리는 동안에도 읽으면 마지막 값이 보인다', (tester) async {
      final drafts = store(debounce: SharedPreferencesDraftStore.defaultDebounce);
      drafts.write(DraftScreen.idealNote, {'note': '아직 안 쓰인 글'});

      expect(drafts.read(DraftScreen.idealNote, _identity), {'note': '아직 안 쓰인 글'});
      await tester.pump(SharedPreferencesDraftStore.defaultDebounce);
    });

    test('기다림은 약 500ms 다', () {
      expect(SharedPreferencesDraftStore.defaultDebounce, const Duration(milliseconds: 500));
    });
  });
}
