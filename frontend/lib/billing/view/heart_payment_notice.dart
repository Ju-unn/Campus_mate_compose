import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 결제 안내(pen 마스터 `bBjRD` PaymentNotice — 15e 구매 섹션 끝 `saa1s` · 18d 시트 맨 아래 `LWg2m`).
/// 두 줄 12/400 muted + 링크 "유료 서비스 약관 ›" 12/600 primaryText, 모두 줄높이 1.5 · 줄 사이 4.
/// 두 줄은 이 기기 스토어의 글자다([PaymentStore] — App Store 판은 pen 후속).
/// 청약철회 · 환불 문구는 법률 검토 전까지 이 한 줄로 둔다(계획서 결정 I-4).
class HeartPaymentNotice extends ConsumerStatefulWidget {
  const HeartPaymentNotice({super.key});

  static const String termsLabel = '유료 서비스 약관 ›';

  @override
  ConsumerState<HeartPaymentNotice> createState() => _HeartPaymentNoticeState();
}

class _HeartPaymentNoticeState extends ConsumerState<HeartPaymentNotice> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5);
    final store = ref.watch(paymentStoreProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(store.paymentLine, style: muted),
        const SizedBox(height: AppSpacing.xxs),
        Text(store.refundLine, style: muted),
        const SizedBox(height: AppSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          // 잉크는 링크 자신의 Material 에 그린다 — 스크롤 · 시트 밖 Material 에 남지 않게(COMMON §4-2).
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _openTerms,
              child: Semantics(
                link: true,
                child: Text(
                  HeartPaymentNotice.termsLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 설정(16)의 약관 줄과 같은 방식 — 앱 안 브라우저로 열고, 못 열면 실패 토스트.
  Future<void> _openTerms() async {
    if (_opening) return; // 여는 호출이 끝나기 전에 다시 눌러도 두 번 열지 않는다
    _opening = true;
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await ref.read(openUrlProvider)(paidServiceTermsLink);
    } catch (_) {
      opened = false;
    } finally {
      _opening = false;
    }
    if (!opened) {
      showSafetyToast(messenger, const UnknownFailure().toDisplayMessage(), icon: AppIcons.alertTriangle);
    }
  }
}
