import 'package:campus_mate/core/app_update/app_version.dart';
import 'package:campus_mate/core/app_update/app_version_repository.dart';
import 'package:campus_mate/core/app_update/installed_app_version.dart';
import 'package:campus_mate/core/app_update/store_listing.dart';
import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeInstalledAppVersion implements InstalledAppVersion {
  FakeInstalledAppVersion(this._read);

  /// 값을 주거나 던진다 — 던지는 쪽은 플랫폼 채널 오류 흉내다.
  final Future<AppVersion?> Function() _read;

  @override
  Future<AppVersion?> read() => _read();
}

const _playUrl = 'https://play.google.com/store/apps/details?id=io.github.juunn.campusmate';

/// 서버가 [minimum] 을 알려 주는 상태에서, 설치된 앱이 [installed] 일 때의 판정. [asks] 에 서버를 몇 번 불렀는지 남는다.
Future<UpdateRequirement> decide({
  required String installed,
  String? minimum,
  int status = 200,
  StoreListing store = const StoreListing(TargetPlatform.android),
  List<int>? asks,
  Future<AppVersion?> Function()? installedRead,
}) {
  final client = MockClient((request) async {
    asks?.add(1);
    return http.Response(minimum == null ? '{"min_version":null}' : '{"min_version":"$minimum"}', status);
  });
  final container = ProviderContainer(overrides: [
    appVersionRepositoryProvider.overrideWithValue(AppVersionRepository('https://api.test', client)),
    installedAppVersionProvider.overrideWithValue(
      FakeInstalledAppVersion(installedRead ?? () async => AppVersion.tryParse(installed)),
    ),
    storeListingProvider.overrideWithValue(store),
  ]);
  addTearDown(container.dispose);
  return container.read(updateRequirementProvider.future);
}

void main() {
  test('설치 1.0.1 · 최소 1.0.2 면 업데이트가 필요하다 — 스토어 주소를 함께 준다', () async {
    final result = await decide(installed: '1.0.1', minimum: '1.0.2');

    expect(result, isA<UpdateRequired>().having((required) => required.storeUrl, 'storeUrl', _playUrl));
  });

  test('아이폰이면 앱 스토어 상세 주소를 준다', () async {
    const url = 'https://apps.apple.com/app/id6821955396';

    final result = await decide(
      installed: '1.0.1',
      minimum: '1.0.2',
      store: const StoreListing(TargetPlatform.iOS),
    );

    expect(result, isA<UpdateRequired>().having((required) => required.storeUrl, 'storeUrl', url));
  });

  test('최소 버전과 같으면 막지 않는다', () async {
    expect(await decide(installed: '1.0.1', minimum: '1.0.1'), isA<UpdateNotRequired>());
  });

  test('최소 버전보다 높으면 막지 않는다 — 1.0.10 은 1.0.9 보다 높다', () async {
    expect(await decide(installed: '1.0.10', minimum: '1.0.9'), isA<UpdateNotRequired>());
    expect(await decide(installed: '1.1.0', minimum: '1.0.9'), isA<UpdateNotRequired>());
  });

  test('서버가 최소 버전을 안 정했으면(null) 막지 않는다', () async {
    expect(await decide(installed: '1.0.0'), isA<UpdateNotRequired>());
  });

  test('서버가 오류로 답하면 막지 않는다 — 장애 때 앱이 잠기지 않게', () async {
    expect(await decide(installed: '1.0.0', minimum: '9.9.9', status: 500), isA<UpdateNotRequired>());
  });

  test('설치된 버전을 읽지 못하면(null) 막지 않는다', () async {
    expect(await decide(installed: 'banana', minimum: '9.9.9'), isA<UpdateNotRequired>());
  });

  test('설치된 버전을 읽다 플랫폼 오류가 나도 막지 않고 오류로 번지지 않는다', () async {
    final result = await decide(
      installed: '',
      minimum: '9.9.9',
      installedRead: () async => throw StateError('platform channel'),
    );

    expect(result, isA<UpdateNotRequired>());
  });

  test('스토어가 없는 웹 · 데스크톱은 서버에 묻지도 않고 막지 않는다', () async {
    final asks = <int>[];

    final result = await decide(
      installed: '1.0.0',
      minimum: '9.9.9',
      store: const StoreListing(null),
      asks: asks,
    );

    expect(result, isA<UpdateNotRequired>());
    expect(asks, isEmpty);
  });
}
