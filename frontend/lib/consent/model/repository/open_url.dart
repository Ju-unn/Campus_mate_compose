import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 노션 문서(약관 동의 02-c "보기" · 설정 16 약관 줄 · 유료 서비스 약관)는 **앱 안 브라우저**로 연다
/// (안드로이드 커스텀 탭 · iOS SFSafariViewController). 사용자 결정 2026-10-16 으로
/// 계획서 Q6 "기기 브라우저"를 바꿨다. canLaunchUrl 을 쓰지 않아 AndroidManifest `<queries>` 가 필요 없다.
/// 못 열면 false 거나 예외다 — 부르는 쪽이 안내한다.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => openInApp(uri, (uri, mode) => launchUrl(uri, mode: mode)),
);

/// 다른 앱으로 넘기는 주소(인스타그램 · 스토어 리뷰 · mailto)는 기기 앱 · 브라우저로 연다 —
/// 앱 안 브라우저는 그 앱으로 넘겨 주지 않고, mailto 는 받지도 않는다.
final openExternalUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// 앱 안 브라우저로 연다. 예외면 false — 기기 브라우저로 다시 열지 않는다: iOS 첫 로드 실패는 SFSafariViewController 를
/// 이미 띄운 채 예외를 던져 다시 열면 이중 열기가 되고, 안드로이드는 커스텀 탭을 받는 브라우저가 없으면 url_launcher 가
/// 스스로 앱 안 웹뷰(WebViewActivity)로 열어 예외까지 가지 않는다. 안내는 부르는 쪽이 한다.
/// shortcut: 앱 안 열기의 false 는 url_launcher 6.x 에서 사실상 iOS 첫 로드 전에 사용자가 닫은 경우뿐이라(안드로이드는
/// 자체 웹뷰 폴백) 연 것으로 친다(실패 안내를 띄우지 않는다). 7.x 로 올리면 false · 예외의 뜻을 다시 본다.
Future<bool> openInApp(Uri uri, Future<bool> Function(Uri, LaunchMode) launch) async {
  try {
    await launch(uri, LaunchMode.inAppBrowserView);
    return true;
  } catch (_) {
    return false;
  }
}
