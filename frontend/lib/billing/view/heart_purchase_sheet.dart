import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/billing/view/heart_store_notice.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 구매 확인 시트에서 고른 것. 취소 · 바깥 누름은 null.
enum HeartPurchaseChoice {
  /// 구매 버튼. 지금은 결제가 없다 — 부른 쪽이 "곧 열려요" 를 알린다.
  request,

  /// 제목줄의 도움말 — 하트·결제 FAQ(21)로 간다.
  help,
}

/// 하트 구매 확인 시트(pen `jqXSU` 18d, 360×460). 번들 카드를 고르고 하단 바의 구매 버튼을 누르면 뜬다.
/// 결제 전 사용 제한을 같은 글로 한 번 더 알린다. 시안일 뿐 실제 결제는 없다(pen 메모).
Future<HeartPurchaseChoice?> showHeartPurchaseSheet(BuildContext context, HeartBundle bundle) {
  return showSafetySheet<HeartPurchaseChoice>(context, (_) => _HeartPurchaseSheet(bundle: bundle));
}

class _HeartPurchaseSheet extends StatelessWidget {
  const _HeartPurchaseSheet({required this.bundle});

  final HeartBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 안쪽 [12,16,32,16] · 위쪽 모서리 24(pen). 기기 아래 여백은 그 밑에 더한다.
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 크게 키워 화면보다 길어지면 안에서 스크롤한다(손잡이부터 취소까지 모두 닿게).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: AppSpacing.lg),
              _TitleRow(),
              const SizedBox(height: AppSpacing.lg),
              _ProductRow(bundle: bundle),
              const SizedBox(height: AppSpacing.lg),
              const HeartStoreNotice(),
              const SizedBox(height: AppSpacing.lg),
              // 실결제를 열 때 이 버튼의 글자와 누르는 동작만 바꾼다([heartPurchaseLabel]).
              HeartPurchaseButton(
                expand: true,
                onPressed: () => Navigator.of(context).pop(HeartPurchaseChoice.request),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 취소 `KAUyy`: 같은 HE8FZ 인스턴스 — 채움 #E5E5E5 · 모서리 14 · 글자 16/700 #222222.
              HeartPurchaseButton(
                expand: true,
                label: '취소',
                textColor: AppColors.ink,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 제목 `BzsMC` 24/700 + 도움말 `Vj9If`(누르는 칸 48, 3D 도움말 20).
class _TitleRow extends StatelessWidget {
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

/// 고른 상품 줄 `HV7Hp`: 그림 32 + "100하트 · 5,700원" 20/600.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.bundle});

  final HeartBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(bundle.asset, width: 32, height: 32, fit: BoxFit.cover, excludeFromSemantics: true),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            '${bundle.quantityLabel} · ${formatWon(bundle.price)}원',
            style: AppTypography.title.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
