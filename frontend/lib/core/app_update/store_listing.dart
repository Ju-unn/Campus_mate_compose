import 'package:flutter/foundation.dart' show TargetPlatform;

/// 이 앱이 올라가 있는 스토어 상세 주소 — "업데이트해 주세요" 안내가 여는 곳.
class StoreListing {
  const StoreListing(this._platform);

  /// 앱이 도는 플랫폼. 웹이면 null(웹은 [TargetPlatform] 이 브라우저 기기를 따라가서 부르는 쪽이 따로 거른다).
  final TargetPlatform? _platform;

  /// `android/app/build.gradle.kts` 의 applicationId 와 같다.
  static const String _androidPackage = 'io.github.juunn.campusmate';

  /// App Store Connect 의 Apple ID(앱 번호, 2026-11-02). 비밀이 아니라 빌드 설정(dart-define)이 아니라 상수로 둔다 —
  /// 빌드에서 빠뜨려 안내에 주소가 없는 일이 없게.
  static const String _appStoreId = '6821955396';

  /// 스토어 주소. 스토어가 없는 곳(웹 · 데스크톱)은 null — 올릴 곳이 없으니 막지도 않는다.
  String? url() => switch (_platform) {
        TargetPlatform.android => 'https://play.google.com/store/apps/details?id=$_androidPackage',
        TargetPlatform.iOS => 'https://apps.apple.com/app/id$_appStoreId',
        _ => null,
      };
}
