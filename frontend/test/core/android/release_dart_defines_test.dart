import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 최종 점검 ⑧: `--dart-define` 이 한 줄 빠져도 릴리스 빌드가 성공해, 서버를 못 부르거나 구글 로그인이 죽은 앱이 만들어졌다.
/// 카카오 복귀 키(2026-10-20 vc13 ~ vc17 폐기)처럼 `android/app/build.gradle.kts` 가 릴리스 빌드에서 막는다 — 그 목록이
/// 앱 코드가 읽는 필수 값과 어긋나지 않는지 본다. iOS 는 TestFlight 워크플로의 `ios_testflight.py check-secrets` 가 같은 값을 막는다.
void main() {
  // 비어도 되는 값 — 비면 홈의 "리뷰 남기기" 가 "곧 열려요" 만 보여 준다(lib/core/env.dart).
  const optional = {'STORE_REVIEW_URL'};

  /// 앱 코드가 `String.fromEnvironment` 로 읽는 이름 전부. 경로는 `frontend/` 에서 돌릴 때 기준이다.
  Set<String> namesReadByApp() {
    final sources = ['lib/core/env.dart', 'lib/core/supabase/supabase_config.dart'].map((path) => File(path).readAsStringSync());
    return {
      for (final source in sources)
        for (final match in RegExp(r"String\.fromEnvironment\('(\w+)'\)").allMatches(source)) match.group(1)!,
    };
  }

  /// [text] 안 `<start>( "A", "B" )` 꼴 목록의 이름들. 못 찾으면 null.
  Set<String>? listedAfter(String text, String start) {
    final list = RegExp('${RegExp.escape(start)}\\s*\\(([^)]*)\\)').firstMatch(text);
    return list == null ? null : {for (final name in RegExp(r'"(\w+)"').allMatches(list.group(1)!)) name.group(1)!};
  }

  test('앱 코드가 읽는 필수 값은 Env · Supabase 설정 다섯 개다', () {
    expect(namesReadByApp().difference(optional), {
      'API_BASE_URL',
      'SUPABASE_URL',
      'SUPABASE_ANON_KEY',
      'KAKAO_NATIVE_APP_KEY',
      'GOOGLE_WEB_CLIENT_ID',
    });
  });

  test('안드로이드 릴리스 빌드는 필수 dart-define 이 비면 실패한다 — 목록이 앱 코드와 같다', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final required = listedAfter(gradle, 'val requiredDartDefines = listOf');

    expect(required, isNotNull, reason: 'build.gradle.kts 에서 requiredDartDefines 목록을 찾지 못했다');
    expect(required, namesReadByApp().difference(optional));
    // 카카오 키 검사와 같은 자리(릴리스 시작 작업)에서 막는다.
    expect(gradle, contains('if (isReleaseBuild && missingDartDefines.isNotEmpty())'));
  });

  test('iOS TestFlight 스크립트가 넘기고 검사하는 dart-define 도 같은 목록이다', () {
    final script = File('../.github/scripts/ios_testflight.py').readAsStringSync();

    expect(listedAfter(script, 'DART_DEFINES ='), namesReadByApp().difference(optional));
  });
}
