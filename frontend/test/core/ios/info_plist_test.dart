import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS 연락처 권한 창 문구(NSContactsUsageDescription)는 앱 안 안내(8a · 8d · 06-4)와 같은 사실을 말한다
/// (2026-10-14 사용자 결정 "연락처 안내 문구 정정"). 서버는 고른 사람 번호의 해시(되돌릴 수 없음)만 저장하므로
/// '암호화'(풀 수 있는 변환)라고 쓰지 않는다.
void main() {
  test('NSContactsUsageDescription 은 사실 문장이고 "암호화" 라고 쓰지 않는다', () {
    // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final usage = RegExp(r'<key>NSContactsUsageDescription</key>\s*<string>([^<]*)</string>').firstMatch(plist);

    expect(usage, isNotNull, reason: 'Info.plist 에서 NSContactsUsageDescription 을 찾지 못했다');
    expect(
      usage!.group(1),
      '차단할 지인을 연락처에서 고르기 위해 사용해요. '
      '고른 분의 전화번호만 원래 번호로 되돌릴 수 없는 형태로 바꿔 서버에 저장해요. '
      '이름과 연락처 목록은 서버로 보내지 않아요.',
    );
  });

  // 학생증 인증은 2026-10-17 에 없앴다. 사진은 프로필 · 하트 인증샷 · 졸업생 졸업증명서(10-19 되살림)에만 쓴다.
  test('NSPhotoLibraryUsageDescription 은 지금 사진을 쓰는 곳만 말하고 학생증을 말하지 않는다', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final usage = RegExp(r'<key>NSPhotoLibraryUsageDescription</key>\s*<string>([^<]*)</string>').firstMatch(plist);

    expect(usage, isNotNull, reason: 'Info.plist 에서 NSPhotoLibraryUsageDescription 을 찾지 못했다');
    expect(
      usage!.group(1),
      '프로필 사진, 하트 무료로 모으기 인증 사진, 졸업생 인증용 졸업증명서 사진을 고르기 위해 사진 보관함에 접근해요. '
      '고른 사진만 쓰고 다른 사진은 보지 않아요.',
    );
    expect(plist, isNot(contains('학생증')));
  });

  // 앱은 주소로 화면을 열 일이 없다(2026-10-18 보안 검사 중간 2). 꺼도 카카오 복귀 스킴은 플러그인이 먼저 받는다
  // (엔진 FlutterSceneLifeCycle: 플러그인이 안 받은 주소만 이 값을 보고 라우터로 넘긴다).
  test('FlutterDeepLinkingEnabled 는 false 다', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')));
  });

  // 사용 통계 · 오류 수집 · 성능 측정은 약관 동의 전에는 꺼 둔다(2026-10-20). 키 이름이 틀리면 Firebase 는 조용히 무시하고
  // 동의 전에도 수집한다 — 성능 측정 키는 다른 둘과 달리 **소문자**다(https://firebase.google.com/docs/perf-mon/disable-sdk?platform=ios).
  test('수집 도구 세 개는 Info.plist 에서 꺼져 있고 성능 측정 키는 공식 소문자 이름이다', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    for (final key in ['firebase_performance_collection_enabled', 'FIREBASE_ANALYTICS_COLLECTION_ENABLED', 'FirebaseCrashlyticsCollectionEnabled']) {
      expect(plist, matches(RegExp('<key>$key</key>\\s*<false/>')), reason: key);
    }
    expect(plist, isNot(contains('<key>FIREBASE_PERFORMANCE_COLLECTION_ENABLED</key>')), reason: '없는 키 이름(대문자)');
    // 끄기 전용 키는 앱에서 다시 켤 수 없다.
    expect(plist, isNot(contains('<key>firebase_performance_collection_deactivated</key>')));
    expect(plist, isNot(contains('<key>FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED</key>')));
  });
}
