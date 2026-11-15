import 'package:flutter/foundation.dart' show TargetPlatform;

/// 이 앱이 올라가 있는 스토어 상세 주소 — "업데이트해 주세요" 안내 · 홈 리뷰 띠가 여는 곳.
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

  /// 홈 리뷰 띠 "리뷰 남기기" 가 여는 주소(사용자 「아이폰 , 안드로이드 각각 리뷰 작성으로 들어가게」 11-16).
  /// 아이폰은 애플 안내대로 `action=write-review` 를 붙여 리뷰 쓰기 창을 바로 연다. 플레이에는 그런 주소가 없어 상세 페이지 그대로다.
  String? reviewUrl() => switch (_platform) {
        TargetPlatform.iOS => '${url()}?action=write-review',
        _ => url(),
      };
}
