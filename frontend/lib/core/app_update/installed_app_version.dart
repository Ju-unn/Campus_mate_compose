import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 지금 설치된 앱의 버전. 시험이 가짜로 바꿔 끼울 수 있게 인터페이스로 둔다.
abstract interface class InstalledAppVersion {
  /// 읽지 못하거나 숫자.숫자.숫자 가 아니면 null.
  Future<AppVersion?> read();
}

/// `package_info_plus` 로 읽는다 — 안드로이드 versionName · iOS CFBundleShortVersionString(빌드 번호는 버린다).
class PackageInfoInstalledAppVersion implements InstalledAppVersion {
  const PackageInfoInstalledAppVersion();

  @override
  Future<AppVersion?> read() async => AppVersion.tryParse((await PackageInfo.fromPlatform()).version);
}
