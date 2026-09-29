import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// "보기"는 기기 브라우저로 연다(웹뷰 아님, 계획서 Q6). canLaunchUrl 을 쓰지 않아
/// AndroidManifest `<queries>` 가 필요 없다. 못 열면 false 거나 예외다 — 부르는 쪽이 안내한다.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
