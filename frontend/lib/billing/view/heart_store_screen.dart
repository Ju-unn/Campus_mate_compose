import 'dart:async';

import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/view/heart_bundle_card.dart';
import 'package:campus_mate/billing/view/heart_purchase_bar.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/billing/view/heart_purchase_sheet.dart';
import 'package:campus_mate/billing/view/heart_store_notice.dart';
import 'package:campus_mate/billing/view/heart_task_actions.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk`.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// pen `kdljs` Heart Value Scene.
const String _heroAsset = 'assets/images/heart-value-scene.png';

/// pen `cVVgB` 12/normal #6A6A6A 줄높이 1.4.
const String _rewardNotice = '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트';

/// 18 하트 스토어(pen `IAy1j`). 보유 하트 · 하트 번들 구매 · 무료로 모으기. 설정의 보유 하트와 15b 시트의 "충전하기"가 연다.
///
/// 구매는 아직 열리지 않았다 — 번들 카드는 고르기만 하고, 하단 바의 회색 "곧 열려요" 가 구매 확인 시트를 연다(pen 시안).
class HeartStoreScreen extends ConsumerStatefulWidget {
  const HeartStoreScreen({super.key});

  @override
  ConsumerState<HeartStoreScreen> createState() => _HeartStoreScreenState();
}

class _HeartStoreScreenState extends ConsumerState<HeartStoreScreen> {
  static const Duration _toastDuration = Duration(seconds: 2);

  int _selected = defaultHeartBundleIndex;
  bool _toast = false;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  /// 구매 확인 시트를 열고 고른 것을 처리한다. 실결제를 열 때 [HeartPurchaseChoice.request] 줄만 바꾸면 된다.
  Future<void> _openPurchaseSheet() async {
    final choice = await showHeartPurchaseSheet(context, heartBundles[_selected]);
    if (!mounted) return;
    switch (choice) {
      case HeartPurchaseChoice.request:
        _showComingSoon();
      case HeartPurchaseChoice.help:
        unawaited(context.push(AppRoutes.faq));
      case null:
        break;
    }
  }

  void _showComingSoon() {
    _toastTimer?.cancel();
    setState(() => _toast = true);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bundle = heartBundles[_selected];
    return Scaffold(
      appBar: _appBar(context),
      bottomNavigationBar: HeartPurchaseBar(bundle: bundle, onPurchase: _openPurchaseSheet),
      body: Stack(
        children: [
          ListView(
            // pen `eagSX` 안쪽 [8,16,32,16] · 칸 사이 24.
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
            children: [
              const _Hero(),
              const SizedBox(height: AppSpacing.lg),
              const _BalanceBlock(),
              const SizedBox(height: AppSpacing.lg),
              _PurchaseSection(selected: _selected, onSelect: (index) => setState(() => _selected = index)),
              const SizedBox(height: AppSpacing.lg),
              const _FreeSection(),
            ],
          ),
          if (_toast)
            const Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
              child: Center(child: _ComingSoonToast()),
            ),
        ],
      ),
    );
  }

  /// pen `RRpV8`(AppBar · Sub 360×56): 안쪽 [0,12], 뒤로 48 (x12), 제목 "하트" 18/700 (x64), 오른쪽 3D 도움말 24 (누름 48, x300).
  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      leadingWidth: 60,
      titleSpacing: AppSpacing.xxs,
      leading: Navigator.of(context).canPop()
          ? Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
              ),
            )
          : null,
      title: Text('하트', style: AppTypography.subNavTitle.copyWith(color: AppColors.ink)),
      actions: [
        IconButton(
          tooltip: '도움말',
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: () => context.push(AppRoutes.faq),
          icon: const Icon3d(AppIcon3d.help, size: 24),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

/// 히어로 `LbUx1` — 그림 180×180 가운데, 모서리 14.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.asset(_heroAsset, width: 180, height: 180, fit: BoxFit.cover, excludeFromSemantics: true),
      ),
    );
  }
}

/// 보유 하트 `p9CUb`(HeartBalance · Large): "보유 하트" 14/600 muted, 아래 하트 44 + "320개" 32/700. 숫자는 서버 `heart_balance`.
/// 읽는 중 · 실패는 pen 에 없다 — 숫자 자리에 "-" 를 둔다.
class _BalanceBlock extends ConsumerWidget {
  const _BalanceBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(
      myProfileProvider.select(
        (profile) => profile.value?.when(onSuccess: (value) => value.heartBalance, onFailure: (_) => null),
      ),
    );
    return Semantics(
      label: balance == null ? '보유 하트를 불러오는 중' : '보유 하트 $balance개',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            Text('보유 하트', style: AppTypography.labelSmall.copyWith(color: AppColors.muted)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(_heartAsset, width: 44, height: 44, excludeFromSemantics: true),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  balance == null ? '-' : '${formatWon(balance)}개',
                  style: AppTypography.display.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 구매하기 `zEdiV`: 제목 20/600 → 12 → 안내 → 12 → 번들 카드 5장(사이 16, 추천 태그가 걸치는 위 12).
class _PurchaseSection extends StatelessWidget {
  const _PurchaseSection({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('구매하기', style: AppTypography.title.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.sm),
        const HeartStoreNotice(),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            children: [
              for (final (index, bundle) in heartBundles.indexed) ...[
                if (index > 0) const SizedBox(height: AppSpacing.md),
                HeartBundleCard(bundle: bundle, selected: index == selected, onTap: () => onSelect(index)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 무료로 모으기 `EsnDC`: 제목 20/600 → 4 → 안내 12 → 줄 3개(사이 4). 줄은 18a 의 [HeartTaskRow] 와 서버 목록을 그대로 쓴다.
/// 읽는 중 · 실패는 pen 에 없다 — 도는 표시 / 문구 + "다시 시도".
class _FreeSection extends ConsumerWidget {
  const _FreeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heartTasksViewModelProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('무료로 모으기', style: AppTypography.title.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xxs),
        Text(_rewardNotice, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.errorMessage case final message?)
          _LoadError(message: message, onRetry: () => ref.invalidate(heartTasksViewModelProvider))
        else
          for (final (index, task) in state.tasks.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xxs),
            HeartTaskRow(task: task, onTap: heartTaskOnTap(context, task)),
          ],
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
      ],
    );
  }
}

/// "곧 열려요" — 구매 확인 시트의 구매 버튼을 눌렀을 때(실결제는 아직 없다).
class _ComingSoonToast extends StatelessWidget {
  const _ComingSoonToast();

  @override
  Widget build(BuildContext context) {
    return const AppToast(
      leading: Icon(AppIcons.clock3, size: 16, color: AppColors.onInk),
      label: heartPurchaseLabel,
    );
  }
}
