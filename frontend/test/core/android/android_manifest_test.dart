import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 안드로이드 백업은 끈다(2026-10-12 보안 점검 #15). 켜 두면 로그인 토큰 · 온보딩 임시 저장(shared_preferences)이
/// 구글 드라이브 백업이나 `adb backup` 으로 기기 밖에 나간다.
void main() {
  test('AndroidManifest 의 application 이 백업을 끈다', () {
    // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest);

    expect(application, isNotNull, reason: 'AndroidManifest.xml 에서 <application> 을 찾지 못했다');
    expect(application!.group(0), contains('android:allowBackup="false"'));
  });

  // 앱은 주소로 화면을 열 일이 없다(푸시 이동은 앱 안 router.go). 켜 두면 MainActivity 로 온 VIEW 인텐트의 주소가
  // 그대로 라우터 경로가 된다(2026-10-18 보안 검사 중간 2). 카카오 복귀는 AuthCodeHandlerActivity 가 따로 받는다.
  test('MainActivity 가 Flutter 기본 딥링크 라우팅을 끈다', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = RegExp(r'<activity\s+android:name="\.MainActivity".*?</activity>', dotAll: true).firstMatch(manifest);

    expect(mainActivity, isNotNull, reason: 'AndroidManifest.xml 에서 .MainActivity 를 찾지 못했다');
    expect(
      mainActivity!.group(0),
      matches(RegExp(r'android:name="flutter_deeplinking_enabled"\s+android:value="false"')),
    );
  });
}
