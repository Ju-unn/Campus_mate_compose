import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이벤트 매개변수에 실리는 글자는 여기 적힌 것뿐이다. 대시보드 필터와 `docs/ANALYTICS_EVENTS.md` 표가
/// 이 글자에 기대므로, 값을 고치면 이 시험과 그 표를 함께 고친다.
void main() {
  Map<String, String> wires<T extends Enum>(List<T> values, String Function(T) wire) => {
        for (final value in values) value.name: wire(value),
      };

  test('카드 출처는 free · purchased', () {
    expect(CardOrigin.values.map((v) => v.wire), ['free', 'purchased']);
  });

  test('유료 카드 칸 상태는 offered · empty', () {
    expect(PaidCardState.values.map((v) => v.wire), ['offered', 'empty']);
  });

  test('하트 상점 진입점 글자', () {
    expect(
      wires(HeartStoreEntry.values, (v) => v.wire),
      {
        'home': 'home',
        'settings': 'settings',
        'paidCard': 'paid_card',
        'avatarRegen': 'avatar_regen',
        'heartShort': 'heart_short',
        'other': 'other',
      },
    );
  });

  test('하트 결제 결과는 success · cancel · fail', () {
    expect(HeartPurchaseResult.values.map((v) => v.wire), ['success', 'cancel', 'fail']);
  });

  test('앱 투어 결과는 done · skip', () {
    expect(TourResult.values.map((v) => v.wire), ['done', 'skip']);
  });

  test('가입 단계에서 막힌 이유 글자', () {
    expect(
      wires(OnboardingBlockReason.values, (v) => v.wire),
      {
        'photoDocument': 'photo_document',
        'photoRejected': 'photo_rejected',
        'photoNoFace': 'photo_no_face',
        'rejected': 'rejected',
        'network': 'network',
        'server': 'server',
        'rateLimited': 'rate_limited',
        'session': 'session',
      },
    );
  });

  test('푸시 종류 글자는 푸시 data.route 와 같다', () {
    expect(
      PushOpenType.values.map((v) => v.wire),
      [
        'daily_card',
        'acceptances',
        'match',
        'chat',
        'friend_reviews',
        'friend_review_write',
        'heart_tasks',
        'heart_task_retry',
        'poll',
        'other',
      ],
    );
  });

  test('모든 글자는 짧은 소문자 snake_case 다 — 개인 값이 들어갈 틈이 없다', () {
    final all = [
      ...CardOrigin.values.map((v) => v.wire),
      ...PaidCardState.values.map((v) => v.wire),
      ...HeartStoreEntry.values.map((v) => v.wire),
      ...HeartPurchaseResult.values.map((v) => v.wire),
      ...TourResult.values.map((v) => v.wire),
      ...OnboardingBlockReason.values.map((v) => v.wire),
      ...PushOpenType.values.map((v) => v.wire),
    ];
    expect(all, everyElement(matches(RegExp(r'^[a-z][a-z_]{0,29}$'))));
  });
}
