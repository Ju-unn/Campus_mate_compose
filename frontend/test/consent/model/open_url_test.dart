import 'package:campus_mate/consent/model/open_url.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final uri = Uri.parse('https://example.test/terms');
  late List<LaunchMode> modes;

  /// 가짜 launcher — 앱 안 열기가 돌려줄 값(또는 던질 예외)을 정하고, 불린 모드를 순서대로 남긴다.
  Future<bool> Function(Uri, LaunchMode) launcher(Object result) => (uri, mode) async {
        modes.add(mode);
        if (result is Exception) throw result;
        return result as bool;
      };

  setUp(() => modes = []);

  test('앱 안 브라우저로 연다 — 열리면 true, 기기 브라우저는 부르지 않는다', () async {
    final opened = await openInApp(uri, launcher(true));

    expect(opened, isTrue);
    expect(modes, [LaunchMode.inAppBrowserView]);
  });

  test('앱 안 열기가 예외면 false — 기기 브라우저로 다시 열지 않는다(iOS 로드 실패는 앱 안 화면이 이미 떠 있어 이중 열기가 된다)', () async {
    final opened = await openInApp(uri, launcher(Exception('failedToLoad')));

    expect(opened, isFalse);
    expect(modes, [LaunchMode.inAppBrowserView]);
  });

  test('앱 안 브라우저가 false 면(iOS 첫 로드 전에 닫음) 다시 열지 않고 연 것으로 친다', () async {
    final opened = await openInApp(uri, launcher(false));

    expect(opened, isTrue);
    expect(modes, [LaunchMode.inAppBrowserView]);
  });
}
