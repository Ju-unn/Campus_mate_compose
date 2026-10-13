import 'package:campus_mate/billing/view/heart_payment_notice.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/billing/view/heart_store_notice.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 구매 확인 시트에서 고른 것. 취소 · 바깥 누름 · 결제 결과로 닫힘은 null.
enum HeartPurchaseChoice {
  /// 제목줄의 도움말 — 하트·결제 FAQ(21)로 간다.
  help,
}

/// 하트 구매 확인 시트(pen 18d — 보너스 있음 `yQ6Ae` · 없음 `HoALC` · 결제 창 대기 `XKi8Y`, 360×554).
/// 고른 번들은 구매 뷰모델이 들고 있다. 구매 버튼은 결제 창을 열고, 결제 창 결과가 오면 시트가 스스로 닫힌다 —
/// 결과(확인 중 · 성공 · 안내)는 상점 화면이 보인다.
Future<HeartPurchaseChoice?> showHeartPurchaseSheet(BuildContext context) {
  return showSafetySheet<HeartPurchaseChoice>(context, (_) => const _HeartPurchaseSheet());
}

class _HeartPurchaseSheet extends ConsumerWidget {
  const _HeartPurchaseSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heartPurchaseViewModelProvider);
    final purchasing = state.phase == HeartPurchasePhase.purchasing;
    ref.listen(heartPurchaseViewModelProvider.select((s) => s.phase), (previous, next) {
      if (previous == HeartPurchasePhase.purchasing && next != HeartPurchasePhase.purchasing) {
        Navigator.of(context).pop();
      }
    });
    return PopScope(
      // 결제 창이 떠 있는 동안(18d-3)은 뒤로 · 바깥 누름으로 닫지 않는다 — 결과가 오면 스스로 닫힌다.
      canPop: !purchasing,
      child: Container(
        // 안쪽 [12,16,32,16] · 위쪽 모서리 24 · 칸 사이 24(pen). 기기 아래 여백은 그 밑에 더한다.
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          // 글자를 크게 키워 화면보다 길어지면 안에서 스크롤한다(손잡이부터 결제 안내까지 모두 닿게).
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: SheetHandle()),
                const SizedBox(height: AppSpacing.lg),
                const _TitleRow(),
                const SizedBox(height: AppSpacing.lg),
                _ProductRow(state: state),
                const SizedBox(height: AppSpacing.lg),
                const HeartStoreNotice(),
                const SizedBox(height: AppSpacing.lg),
                _BuyButton(state: state),
                const SizedBox(height: AppSpacing.lg),
                // 취소 `IZFT1`: 같은 HE8FZ — 채움 #E5E5E5 · 글자 #222222. 결제 창 대기 중에는 글자만 #929292(`UTe5A`)로 꺼진다.
                HeartPurchaseButton(
                  expand: true,
                  neutral: true,
                  label: '취소',
                  onPressed: purchasing ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: AppSpacing.lg),
                const HeartPaymentNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 구매 `KuarM` "5,700원에 구매"(primary). 결제 창 대기(18d-3 `SjbFx`)면 회색 + 도는 표시 "결제 진행 중이에요".
class _BuyButton extends ConsumerWidget {
  const _BuyButton({required this.state});

  final HeartPurchaseUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.phase == HeartPurchasePhase.purchasing) {
      return const HeartPurchaseButton(expand: true, busy: true, label: '결제 진행 중이에요', onPressed: null);
    }
    final bundle = state.selectedBundle;
    return HeartPurchaseButton(
      expand: true,
      label: '${bundle.priceLabel}에 구매',
      onPressed: state.canBuy(bundle.productId) ? () => ref.read(heartPurchaseViewModelProvider.notifier).buy() : null,
    );
  }
}

/// 제목 `MyRj8` 24/700 + 도움말 `bzykO`(누르는 칸 48, 3D 도움말 20).
class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text('하트를 구매할까요?', style: AppTypography.headline.copyWith(color: AppColors.ink)),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: '도움말',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: () => Navigator.of(context).pop(HeartPurchaseChoice.help),
            icon: const Icon3d(AppIcon3d.help, size: 20),
          ),
        ],
      ),
    );
  }
}

/// 고른 상품 줄 `hGj15`: 그림 32 + 간격 8 + "100하트 + 보너스 50하트 · 5,700원"(보너스 없으면 "100하트 · 5,700원") 18/600.
/// 보너스는 서버 자격이 있을 때만 — 실제로 들어간 양은 성공 토스트가 서버 숫자로 다시 말한다.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.state});

  final HeartPurchaseUiState state;

  /// pen `GItUi` 18/600 은 토큰에 없다(title 20/600 · subNavTitle 18/700) — title 을 18 로. 줄높이는 pen 렌더 26.
  static final TextStyle _style = AppTypography.title.copyWith(fontSize: 18, height: 26 / 18, color: AppColors.ink);

  @override
  Widget build(BuildContext context) {
    final bundle = state.selectedBundle;
    final bonus = state.bonusFor(bundle);
    final quantity = bonus == null ? bundle.quantityLabel : '${bundle.quantityLabel} + 보너스 $bonus하트';
    return Row(
      children: [
        Image.asset(bundle.asset, width: 32, height: 32, fit: BoxFit.cover, excludeFromSemantics: true),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text('$quantity · ${bundle.priceLabel}', style: _style)),
      ],
    );
  }
}
