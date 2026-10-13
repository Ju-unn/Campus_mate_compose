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
}
