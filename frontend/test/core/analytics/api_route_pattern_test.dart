import 'dart:io';

import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/core/analytics/api_route_pattern.dart';
import 'package:campus_mate/profile/traits/viewmodel/tag_picker_kind.dart';
import 'package:flutter_test/flutter_test.dart';

/// 오류 수집에 보내는 요청 경로에는 사람을 가리키는 값(id · 토큰 · 코드)이 들어가면 안 된다.
void main() {
  String patternOf(String url) => ApiRoutePattern.of(Uri.parse(url));

  test('값이 채워진 id(UUID)는 :id 로 바뀌고 쿼리 문자열은 떨어진다', () {
    expect(
      patternOf('https://api.test/cards/3f2a9c1e-7b4d-4e8a-9c21-5d6e7f8a9b0c/decision?x=1'),
      '/cards/:id/decision',
    );
  });

  test('앱이 부르는 고정 길 낱말(목록에 든 것)은 남긴다', () {
    expect(patternOf('https://api.test/profile-onboarding/next-step'), '/profile-onboarding/next-step');
    expect(patternOf('https://api.test/cards/today'), '/cards/today');
    expect(patternOf('https://api.test/phone-verification/send'), '/phone-verification/send');
    expect(patternOf('https://api.test/phone-verification/verify'), '/phone-verification/verify');
  });

  test('채팅방 id 가 가운데에 있어도 바뀐다', () {
    expect(
      patternOf('https://api.test/chat/matches/11111111-1111-4111-8111-111111111111/messages'),
      '/chat/matches/:id/messages',
    );
  });

  test('숫자 · 대문자 · 콜론이 든 조각(푸시 토큰 · 초대 코드)도 :id 다', () {
    expect(patternOf('https://api.test/cards/push-tokens/eXaMple:APA91bH-token_123'), '/cards/push-tokens/:id');
    expect(patternOf('https://api.test/reports/12345'), '/reports/:id');
    expect(patternOf('https://api.test/referral/ABCD'), '/referral/:id');
  });

  test('소문자 값(닉네임 · 영문 코드 · 토큰 조각)은 낱말 모양이어도 :id 다', () {
    expect(patternOf('https://api.test/profiles/minji'), '/profiles/:id');
    expect(patternOf('https://api.test/friend-reviews/targets/abcdef'), '/friend-reviews/targets/:id');
    expect(patternOf('https://api.test/cards/push-tokens/abcdeftoken'), '/cards/push-tokens/:id');
  });

  test('목록에 없는 낱말은 소문자 · 하이픈 모양이어도 :id 다', () {
    expect(patternOf('https://api.test/profiles/nickname/minji'), '/profiles/:id/:id');
    expect(patternOf('https://api.test/invites/abcdef'), '/:id/:id');
  });

  test('쿼리 문자열은 어떤 값이 있어도 결과에 없다', () {
    final pattern = patternOf('https://api.test/profile-onboarding/nickname-availability?nickname=%EC%97%AC%EC%9A%B0');
    expect(pattern, '/profile-onboarding/nickname-availability');
    expect(pattern, isNot(contains('?')));
  });

  test('조각이 6개를 넘으면 앞 6개만 본다', () {
    expect(
      patternOf('https://api.test/me/profile/me/profile/me/profile/me/profile'),
      '/me/profile/me/profile/me/profile',
    );
  });

  test('경로가 없으면 /', () {
    expect(patternOf('https://api.test'), '/');
    expect(patternOf('https://api.test/'), '/');
  });

  group('고정 낱말 목록(ApiRoutePattern.routeWords)', () {
    // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    // 줄 주석은 줄 맨 앞이나 공백 뒤의 `//` 부터다 — 문자열 주소(`'https://…'`)의 `//` 는 주석이 아니다.
    final lineComment = RegExp(r'(^|\s)//.*');
    // 서버를 부르는 파일 = `ApiClient` 나 `baseUrl` 을 쓰는 파일(저장소 · 버전 확인). 폴더 이름에 기대지 않는다.
    final talksToServer = RegExp(r'\bApiClient\b|\b_?baseUrl\b');
    // 따옴표로 시작하는 글자 중 `/…` 로 시작하는 것, 또는 기본 주소 뒤에 바로 붙는 것(`'$_baseUrl/app/version'`).
    final pathLiteral = RegExp('''['"](?:\\\$_?baseUrl)?(/[^'"\\r\\n]*)['"]''');
    final interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*');
    // 경로에 `$endpoint` · `${kind.code}` 로 끼워 넣는 고정 값 — 소스에는 글자로 없어 enum 에서 읽는다.
    final pathEnumWords = [
      ...TagPickerKind.values.map((kind) => kind.endpoint),
      ...HeartTaskKind.values.map((kind) => kind.code),
    ];

    /// 경로 글자 하나(`/chat/matches/$matchId/messages`)에서 값 자리(`$…`)를 빼고 남는 고정 조각들.
    List<String> fixedWordsIn(String literal) =>
        literal.replaceAll(interpolation, '/').split('/').where((word) => word.isNotEmpty).toList();

    /// 서버를 부르는 소스 파일 → 그 파일의 경로 글자에서 나온 고정 조각들.
    Map<String, List<String>> fixedWordsBySource() {
      final result = <String, List<String>>{};
      for (final file in libFiles) {
        final lines = file.readAsLinesSync().map((line) => line.replaceFirst(lineComment, ''));
        final source = lines.join('\n');
        if (!talksToServer.hasMatch(source)) continue;
        final words = [
          for (final match in pathLiteral.allMatches(source)) ...fixedWordsIn(match.group(1)!),
        ];
        if (words.isNotEmpty) result[file.path.replaceAll(r'\', '/')] = words;
      }
      return result;
    }

    test('경로 글자 읽기: 값 자리(`\$id` · `\${…}`)는 빼고 고정 조각만 남긴다', () {
      expect(fixedWordsIn('/chat/matches/\$matchId/messages'), ['chat', 'matches', 'messages']);
      expect(fixedWordsIn('/heart-tasks/\${kind.code}/submissions'), ['heart-tasks', 'submissions']);
      expect(fixedWordsIn('/cards'), ['cards']);
    });

    test('서버를 부르는 소스의 경로 글자 고정 조각은 모두 목록에 있다 — 새 API 경로를 더하고 목록을 빼먹으면 실패', () {
      final bySource = fixedWordsBySource();
      final missing = [
        for (final entry in bySource.entries)
          for (final word in entry.value.toSet())
            if (!ApiRoutePattern.routeWords.contains(word)) '${entry.key}: $word',
      ];

      expect(
        missing,
        isEmpty,
        reason: 'ApiRoutePattern.routeWords 에 더한다(새 API 경로를 더하면 목록도):\n${missing.join('\n')}',
      );
    });

    test('훑은 소스가 비어 있지 않다 — 저장소 폴더와 앱 버전 확인(`\$_baseUrl/app/version`)을 모두 읽는다', () {
      final bySource = fixedWordsBySource();

      expect(bySource.length, greaterThan(25), reason: '서버를 부르는 소스를 못 찾았다: ${bySource.keys}');
      expect(bySource['lib/chat/model/repository/http_chat_repository.dart'], contains('messages'));
      expect(bySource['lib/core/app_update/app_version_repository.dart'], ['app', 'version']);
    });

    test('경로에 끼워 넣는 고정 값(TagPickerKind · HeartTaskKind)도 목록에 있다', () {
      expect(pathEnumWords.where((word) => !ApiRoutePattern.routeWords.contains(word)), isEmpty);
    });

    test('목록의 모든 낱말은 근거가 있다 — 소스의 경로 글자나 경로에 끼우는 고정 값(enum)에서 온 것뿐이다', () {
      final grounded = <String>{
        for (final words in fixedWordsBySource().values) ...words,
        ...pathEnumWords,
      };

      final ungrounded = ApiRoutePattern.routeWords.where((word) => !grounded.contains(word)).toList();

      expect(
        ungrounded,
        isEmpty,
        reason: '앱이 부르지 않는 낱말이다 — 목록에서 뺀다(값이 낱말로 섞여 들어오면 그 값이 그대로 나간다):\n${ungrounded.join('\n')}',
      );
    });

    test('목록 낱말은 소문자 · 하이픈 · 밑줄로만 된 짧은 글자이고 정렬돼 있다(값이 섞여 들어오지 않게)', () {
      final words = ApiRoutePattern.routeWords.toList();
      final wordShape = RegExp(r'^[a-z][a-z_-]*$');
      // 고정된 길 이름은 짧다(`profile-onboarding` 18자). 이보다 긴 글자는 낱말이 아니라 값이 잘못 들어온 것이다.
      const maxWordLength = 40;

      expect(words.where((word) => !wordShape.hasMatch(word) || word.length > maxWordLength), isEmpty);
      expect(words, [...words]..sort(), reason: '정렬해서 둔다');
    });
  });
}
