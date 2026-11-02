import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:campus_mate/core/app_update/app_version_repository.dart';
import 'package:campus_mate/core/app_update/installed_app_version.dart';
import 'package:campus_mate/core/app_update/store_listing.dart';
import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/env.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 서버의 최소 앱 버전 조회. 시험이 [AppVersionRepository] 를 가짜 HTTP 로 바꿔 끼운다.
final appVersionRepositoryProvider = Provider<AppVersionRepository>(
  (ref) => AppVersionRepository(Env.apiBaseUrl, http.Client()),
);

/// 지금 설치된 앱 버전. 시험이 가짜로 바꿔 끼운다.
final installedAppVersionProvider = Provider<InstalledAppVersion>(
  (ref) => const PackageInfoInstalledAppVersion(),
);

/// 이 빌드가 올라가는 스토어. 웹은 브라우저 기기(아이폰 사파리도 iOS) 대신 null 로 둔다 — 웹은 올릴 스토어가 없다.
final storeListingProvider = Provider<StoreListing>(
  (ref) => StoreListing(kIsWeb ? null : defaultTargetPlatform),
);

/// 시작 때 한 번: 설치된 앱이 서버가 정한 최소 버전보다 낮은가. **어떤 실패도 [UpdateNotRequired]** 로 끝나고 오류 상태로
/// 번지지 않는다 — 안내 화면이 이 값을 읽다 오류 처리를 빠뜨려도, 서버 장애가 앱 잠금이 될 길이 없게 한다.
final updateRequirementProvider = FutureProvider<UpdateRequirement>((ref) async {
  final storeUrl = ref.watch(storeListingProvider).url();
  if (storeUrl == null) return const UpdateNotRequired(); // 스토어가 없으면 올릴 곳이 없다 — 서버에 묻지도 않는다.
  // await 앞에서 모두 가져온다 — await 뒤의 ref.watch 는 의존을 놓칠 수 있다.
  final installedVersion = ref.watch(installedAppVersionProvider);
  final repository = ref.watch(appVersionRepositoryProvider);
  try {
    final installed = await installedVersion.read();
    final minimum = await repository.fetchMinimum();
    return _decide(installed, minimum, storeUrl);
  } on Object catch (_) {
    // 플랫폼 채널 오류 등 예상 밖 실패. 막는 쪽으로 틀리는 것이 막지 않는 쪽으로 틀리는 것보다 훨씬 나쁘다.
    return const UpdateNotRequired();
  }
});

/// 둘 중 하나라도 모르면 견줄 수 없으니 막지 않는다.
UpdateRequirement _decide(AppVersion? installed, AppVersion? minimum, String storeUrl) {
  if (installed == null || minimum == null) return const UpdateNotRequired();
  return installed.isOlderThan(minimum) ? UpdateRequired(storeUrl) : const UpdateNotRequired();
}
