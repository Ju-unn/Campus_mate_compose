import 'package:campus_mate/common/failure.dart';

/// 하트 구매 안내 · 오류(pen 15e-8 `JGoPI`, 계획서 7-2 표). [caption] 이 있으면 앱바 아래 배너(pen Alert `teNRJ`),
/// 없으면 잠깐 뜨는 토스트(pen Toast `I8UOWm`)다. 배너는 다시 구매를 시도하거나 상점을 나가면 사라진다(닫기 버튼 없음).
///
/// 문구는 서버 `detail` 이 아니라 pen 글자를 쓴다 — 서버 PURCHASE_INVALID 글자는 pen 과 다르다(구현 편차 기록).
enum HeartPurchaseNotice {
  /// 토스트 `imxbJ`(info) — 결제 창에서 취소.
  canceled('결제를 취소했어요'),

  /// 토스트 `bs9a7`(circle-check) — 서버 409 purchase_token_used.
  alreadyProcessed('이미 처리된 결제예요'),

  /// 배너 `Qufgn`(timer) — 결제 창 pending · 서버 202.
  pending('결제 확인을 기다리고 있어요', caption: '확인되면 하트가 들어와요'),

  /// 배너 `v2uyG1`(timer) — 서버 503 · 네트워크 실패. 구매를 끝내지 않아 다음 복구 때 이어서 들어온다.
  delayed('하트 지급이 늦어지고 있어요', caption: '앱을 다시 열면 이어서 들어와요'),

  /// 빨간 배너 `mvOHm`(triangle-alert) — 결제 창 error(카드 거절 등).
  failed('결제가 되지 않았어요', caption: '결제 수단을 확인하고 다시 시도해 주세요', isError: true),

  /// 빨간 배너 `F6cXu` — 서버 422 purchase_invalid.
  invalid('결제를 확인하지 못했어요', caption: '문제가 계속되면 appmailerl4538@gmail.com 으로 알려 주세요', isError: true),

  /// 배너 `wvbOe`(info) — 서버 409 purchase_other_account.
  otherAccount('다른 계정으로 결제한 하트예요', caption: '결제한 계정으로 로그인하면 들어와요'),

  /// 빨간 배너 `YOhKL` — 스토어를 쓸 수 없음 · 가격 0개.
  unavailable('지금은 하트를 살 수 없어요', caption: '구글 플레이에 로그인했는지 확인해 주세요', isError: true);

  const HeartPurchaseNotice(this.title, {this.caption, this.isError = false});

  final String title;
  final String? caption;

  /// 빨간 오류 배너(pen 채움 #FAEFEC · 글자 #C13515).
  final bool isError;

  bool get isBanner => caption != null;

  /// 같은 구매 토큰을 다시 보내도 서버 답이 바뀌지 않는다 — 이 앱이 켜져 있는 동안은 다시 보내지 않는다.
  bool get isFinalForToken => this == alreadyProcessed || this == invalid || this == otherAccount;

  /// POST /billing/google/verify 실패. 서버 code 로 가르고, 그 밖(503 · 네트워크 · 500 · 관문)은 모두 지급 지연이다 —
  /// 구매를 끝내지 않았으니 다음 복구(앱 시작 · 상점 진입 · 복귀)에서 다시 보낸다.
  static HeartPurchaseNotice fromVerifyFailure(Failure failure) {
    if (failure is! ServerRejectedFailure) return delayed;
    if (failure.hasCode('purchase_other_account')) return otherAccount;
    if (failure.hasCode('purchase_token_used')) return alreadyProcessed;
    if (failure.hasCode('purchase_invalid')) return invalid;
    return delayed;
  }
}
