import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:campus_mate/core/app_update/installed_app_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void installedAs(String version) {
    PackageInfo.setMockInitialValues(
      appName: 'CampusMate',
      packageName: 'io.github.juunn.campusmate',
      version: version,
      buildNumber: '19',
      buildSignature: '',
    );
  }

  test('설치된 앱의 버전 이름(빌드 번호 제외)을 읽는다', () async {
    installedAs('1.0.1');

    expect(await const PackageInfoInstalledAppVersion().read(), AppVersion.tryParse('1.0.1'));
  });

  test('버전 이름이 숫자.숫자.숫자 가 아니면 null 이다', () async {
    installedAs('1.0.1-beta');

    expect(await const PackageInfoInstalledAppVersion().read(), isNull);
  });
}
