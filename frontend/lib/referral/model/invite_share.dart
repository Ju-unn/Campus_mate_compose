import 'package:campus_mate/core/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart' show ShareClient;
import 'package:share_plus/share_plus.dart';

/// 휴대폰 공유 창(19 계획서 결정 5). 테스트는 받은 글을 모은다. 19 대기 화면과 16i 친구 초대 시트가 같이 쓴다.
final shareTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// 공유 글(19 결정 5). 하트 숫자 · 스토어 링크는 넣지 않는다.
/// 카카오톡 공유가 안 될 때도 이 글을 그대로 보낸다 — "추천 코드 {코드}" 모양에 친구 코드 리뷰 붙여넣기가 기댄다(friend_code_screen).
String inviteShareText(String code) => 'CampusMate 에서 같이 해요! 가입할 때 추천 코드 $code 를 넣어 줘.';

/// 카카오톡 공유 카드의 사용자 정의 템플릿 번호(카카오 디벨로퍼스 [도구] > [메시지 템플릿], 계획서 3-8).
/// 번호를 받으면 null 을 그 숫자로 바꾸기만 하면 된다. null 인 동안은 카카오를 부르지 않고 기기 공유 창으로 간다.
const int? kakaoInviteTemplateId = null;

/// 시험이 번호를 갈아 끼운다.
final kakaoInviteTemplateIdProvider = Provider<int?>((ref) => kakaoInviteTemplateId);

/// 카카오톡 공유 SDK 호출만 모은 얇은 층. [shareInviteProvider] 의 분기를 SDK 없이 시험하려고 둔다.
abstract interface class KakaoShareClient {
  /// 네이티브 앱 키가 들어 있는 빌드인지. 아니면 `KakaoSdk.init` 을 건너뛰었으니(main.dart) SDK 를 부르지 않는다.
  bool isConfigured();

  Future<bool> isKakaoTalkSharingAvailable();

  Future<void> shareCustom({required int templateId, required Map<String, String> templateArgs});
}

/// 실제 카카오 SDK(`kakao_flutter_sdk_share` 2.0.1)를 부른다.
class SdkKakaoShareClient implements KakaoShareClient {
  const SdkKakaoShareClient(this._nativeAppKey);

  final String _nativeAppKey;

  @override
  bool isConfigured() => _nativeAppKey.trim().isNotEmpty;

  @override
  Future<bool> isKakaoTalkSharingAvailable() => ShareClient.instance.isKakaoTalkSharingAvailable();

  /// SDK 2.0.1 의 `shareCustom` 은 공유 주소를 만든 뒤 카카오톡까지 연다(1.x 처럼 Uri 를 돌려주지 않는다 — share_client.dart).
  @override
  Future<void> shareCustom({required int templateId, required Map<String, String> templateArgs}) =>
      ShareClient.instance.shareCustom(templateId: templateId, templateArgs: templateArgs);
}

final kakaoShareClientProvider = Provider<KakaoShareClient>(
  (ref) => const SdkKakaoShareClient(Env.kakaoNativeAppKey),
);

/// 16i "카카오톡으로 보내기" · 19 "친구에게 초대 링크 보내기"(계획서 3-6). 카카오톡 공유 카드를 먼저 보내고,
/// 못 보내면 기기 공유 창에 [inviteShareText] 를 그대로 띄운다. 기기 공유 창 오류는 부른 화면이 안내한다.
final shareInviteProvider = Provider<Future<void> Function(String code)>((ref) {
  final templateId = ref.watch(kakaoInviteTemplateIdProvider);
  final kakao = ref.watch(kakaoShareClientProvider);
  final shareText = ref.watch(shareTextProvider);
  return (code) async {
    if (await _sentByKakao(kakao, templateId, code)) return;
    await shareText(inviteShareText(code));
  };
});

/// 카카오톡으로 보냈으면 true. 번호 없음 · 키 없는 빌드 · 카카오톡 없음 · 오류는 false — 기기 공유 창으로 넘긴다.
Future<bool> _sentByKakao(KakaoShareClient kakao, int? templateId, String code) async {
  if (templateId == null || !kakao.isConfigured()) return false;
  try {
    if (!await kakao.isKakaoTalkSharingAvailable()) return false;
    await kakao.shareCustom(templateId: templateId, templateArgs: {'code': code});
    return true;
  } catch (_) {
    // 템플릿 삭제 · 앱 키 막힘 · 인터넷 · 하루 한도(계획서 3-6) — 이유와 상관없이 기기 공유 창으로.
    return false;
  }
}
