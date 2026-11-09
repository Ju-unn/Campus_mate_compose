import 'package:campus_mate/billing/store/model/data/heart_purchase_notice.dart';
import 'package:campus_mate/billing/store/model/data/heart_unavailable.dart';
import 'package:campus_mate/billing/store/model/data/payment_store.dart';
import 'package:campus_mate/billing/store/view/heart_store_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// 하트 상점 앱바 바로 아래 배너(pen Alert 마스터 `teNRJ` — 15e-6 `xJ0HR` · 15e-7 `b8MFOu` · 15e-8 여섯 개).
/// 폭 전체 · 안쪽 [12,16] · 아이콘 20 · 간격 10 · 제목 14/600 · 설명 12/400 muted(둘 다 줄높이 1.5, 사이 2). 닫기 버튼은 없다 —
/// 다시 구매하거나 상점을 나가면 사라진다(대장 결정 10-13).
/// 기본은 분홍(#FFF0F2 · 아이콘 #C4224B · 제목 #222222), 오류는 빨강(#FAEFEC · 아이콘 · 제목 #C13515).
class HeartPurchaseBanner extends StatelessWidget {
  const HeartPurchaseBanner({required this.notice, required this.store, this.unavailable, super.key});

  final HeartPurchaseNotice notice;

  /// 이 기기 스토어 — 스토어 이름이 든 설명(결제 불가)을 맞춰 그린다.
  final PaymentStore store;

  /// 결제 불가의 원인 — App Store 에서만 설명 글자를 원인별로 바꾼다(없으면 원인 중립 글자).
  final HeartUnavailable? unavailable;

  /// pen 실측 아이콘 ↔ 글자 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다(18b-2 알림과 같다).
  static const double _iconGap = 10;

  IconData get _icon => switch (notice) {
        HeartPurchaseNotice.pending || HeartPurchaseNotice.delayed => AppIcons.timer,
        HeartPurchaseNotice.otherAccount => AppIcons.info,
        _ => AppIcons.alertTriangle,
      };

  String _caption(AppLocalizations l10n) {
    final cause = unavailable;
    if (notice == HeartPurchaseNotice.unavailable && store == PaymentStore.appStore && cause != null) {
      return cause.appStoreCaption(l10n);
    }
    return notice.captionOn(l10n, store) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = notice.isError;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        color: error ? AppColors.errorWash : AppColors.primaryWash,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(_icon, size: 20, color: error ? AppColors.error : AppColors.primaryText),
            const SizedBox(width: _iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title(l10n),
                    style: AppTypography.labelSmall.copyWith(color: error ? AppColors.error : AppColors.ink, height: 1.5),
                  ),
                  // pen Texts gap 2 — 토큰(4)보다 작은 pen 값.
                  const SizedBox(height: 2),
                  Text(
                    _caption(l10n),
                    style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
