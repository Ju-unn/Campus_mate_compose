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
}
