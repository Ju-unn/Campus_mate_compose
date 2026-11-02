import 'package:campus_mate/core/app_update/store_listing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('안드로이드는 구글 플레이 상세 — 패키지 이름은 앱 id 와 같다', () {
    expect(
      const StoreListing(TargetPlatform.android).url(),
      'https://play.google.com/store/apps/details?id=io.github.juunn.campusmate',
    );
  });

  test('아이폰은 앱 스토어 상세 — 앱 번호는 App Store Connect 의 Apple ID 다', () {
    expect(const StoreListing(TargetPlatform.iOS).url(), 'https://apps.apple.com/app/id6821955396');
  });

  test('스토어가 없는 곳(웹 · 데스크톱)은 null 이다 — 막을 이유가 없다', () {
    expect(const StoreListing(null).url(), isNull);
    expect(const StoreListing(TargetPlatform.windows).url(), isNull);
    expect(const StoreListing(TargetPlatform.macOS).url(), isNull);
    expect(const StoreListing(TargetPlatform.linux).url(), isNull);
  });
}
