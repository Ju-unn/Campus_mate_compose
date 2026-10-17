import 'dart:async';

import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/billing/view/heart_bundle_card.dart';
import 'package:campus_mate/billing/view/heart_payment_notice.dart';
import 'package:campus_mate/billing/view/heart_purchase_banner.dart';
import 'package:campus_mate/billing/view/heart_purchase_bar.dart';
import 'package:campus_mate/billing/view/heart_purchase_button.dart';
import 'package:campus_mate/billing/view/heart_purchase_sheet.dart';
import 'package:campus_mate/billing/view/heart_store_notice.dart';
import 'package:campus_mate/billing/view/heart_task_actions.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
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
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk`.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// pen `kdljs` Heart Value Scene.
const String _heroAsset = 'assets/images/heart-value-scene.png';

/// 15e 하트 상점(pen `IAy1j` · 인앱결제 시안 6b `W50VA`). 보유 하트 · 하트 번들 구매 · 무료로 모으기.
/// 입구: 홈 · 나 탭 앱바 하트 칩 "+" · 설정 보유 하트 블록 · 15b 시트 "충전하기".
///
/// 구매(안드로이드 · iOS): 카드 = 선택 → 하단 바 → 구매 확인 시트(18d) → 결제 창 → 서버 확인 → 하트. 상태는 앱 수명 동안 사는
/// [heartPurchaseViewModelProvider] 하나가 들고 있고, 이 화면은 들어올 때마다 다시 읽게 한다(가격 · 자격 · 지난 결제 복구).
/// 웹 · 데스크톱은 구매 섹션과 하단 바를 숨긴다(15e-9 `GKEM9`). 스토어 이름이 든 글자는 기기 스토어를 따른다(App Store 판은 pen 후속).
class HeartStoreScreen extends ConsumerStatefulWidget {
  const HeartStoreScreen({super.key});

  @override
  ConsumerState<HeartStoreScreen> createState() => _HeartStoreScreenState();
}

class _HeartStoreScreenState extends ConsumerState<HeartStoreScreen> {
  static const Duration _toastDuration = Duration(seconds: 2);

  HeartPurchaseToast? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    // 그리는 도중에 provider 를 바꾸지 않게 다음 차례로 미룬다. 상점에 들어왔으니 지난 배너 · 토스트는 지운다(배너 규칙).
    Future.microtask(() {
      if (mounted) unawaited(ref.read(heartPurchaseViewModelProvider.notifier).refresh(fromStore: true));
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  /// 구매 확인 시트. 결제 창 · 결과는 뷰모델이 처리하고, 여기서는 도움말만 받는다.
  Future<void> _openPurchaseSheet() async {
    final choice = await showHeartPurchaseSheet(context);
    if (mounted && choice == HeartPurchaseChoice.help) unawaited(context.push(AppRoutes.faq));
  }

  void _showToast(HeartPurchaseToast toast) {
    _toastTimer?.cancel();
    setState(() => _toast = toast);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(heartPurchaseSupportedProvider);
    if (supported) {
      ref.listen(heartPurchaseViewModelProvider.select((s) => s.toast), (_, next) {
        if (next == null) return;
        _showToast(next);
        ref.read(heartPurchaseViewModelProvider.notifier).clearToast();
      });
    }
    final state = supported ? ref.watch(heartPurchaseViewModelProvider) : null;
    final banner = state?.banner;
    final toast = state == null ? null : _toastFor(state);
    return Scaffold(
      appBar: _appBar(context),
      bottomNavigationBar: state == null ? null : _bar(state),
      body: Column(
        children: [
          // 배너는 앱바 바로 아래, 본문을 밀어 내린다(pen 15e-6 `xJ0HR` y56 · 본문 y123).
          if (banner != null) HeartPurchaseBanner(notice: banner, store: ref.watch(paymentStoreProvider)),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  // pen `eagSX` 안쪽 [8,16,32,16] · 칸 사이 24.
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                  children: [
                    // 앱 투어 6단계: 무료로 모으기는 목록 끝이라 아직 안 만들어졌을 수 있다 — 늘 있는 맨 위 그림으로 목록을 민다.
                    const TourTarget(id: TourTargetId.heartStoreTop, child: _Hero()),
                    const SizedBox(height: AppSpacing.lg),
                    const _BalanceBlock(),
                    const SizedBox(height: AppSpacing.lg),
                    if (state != null) ...[_PurchaseSection(state: state), const SizedBox(height: AppSpacing.lg)],
                    const TourTarget(id: TourTargetId.heartStoreFree, child: _FreeSection()),
                    // 6단계가 무료로 모으기를 앱바 아래 12 로 올릴 때만 늘어나는 빈자리 — 평소엔 높이 0.
                    const TourScrollRoom(id: TourTargetId.heartStoreFree),
                  ],
                ),
                // 토스트 아래 끝은 바 위 12(pen `eZlLw`). 나타날 때 나 탭 · 홈 토스트와 같이 올라온다(D4) —
                // "하트를 넣고 있어요" → "N하트가 들어왔어요" 처럼 바뀔 때는 제자리에서 글만 바뀐다.
                if (toast != null)
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.sm,
                    child: Center(child: toastEntrance(toast)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 서버 확인 중(15e-3 `H1e2id`)에는 "하트를 넣고 있어요" 가 끝날 때까지 남고, 그 밖에는 2초짜리 안내 토스트
  /// (성공 `X0G8Fz` · `ksBC8` · 이미 처리 `bs9a7` 은 circle-check, 취소 `imxbJ` · 환불(pen 후속)은 info).
  Widget? _toastFor(HeartPurchaseUiState state) {
    if (state.phase == HeartPurchasePhase.verifying) {
      return const AppToast(leading: PurchaseSpinner(size: 16, color: AppColors.onInk), label: '하트를 넣고 있어요');
    }
    final toast = _toast;
    if (toast == null) return null;
    final info = toast is NoticeToast &&
        (toast.notice == HeartPurchaseNotice.canceled || toast.notice == HeartPurchaseNotice.revoked);
    return AppToast(
      leading: Icon(info ? AppIcons.info : AppIcons.circleCheck, size: 16, color: AppColors.onInk),
      label: toast.message,
    );
  }

  /// 하단 바 버튼(pen `ipbPs`): 사기 전 primary "100하트 받기 · 5,700원" · 결제 창 대기 / 확인 중 회색 + 도는 표시 ·
  /// 지급 지연 회색 "지급 확인 중이에요" · 결제 불가 회색 "구매할 수 없어요". 스토어 연결 중(pen 에 없음)은 같은 글자의 회색.
  Widget _bar(HeartPurchaseUiState state) {
    final bundle = state.selectedBundle;
    final (label, busy) = switch (state.phase) {
      HeartPurchasePhase.purchasing => ('결제 진행 중이에요', true),
      HeartPurchasePhase.verifying => ('결제 확인 중이에요', true),
      HeartPurchasePhase.delayed => ('지급 확인 중이에요', false),
      HeartPurchasePhase.idle => (_idleLabel(state, bundle), false),
    };
    return HeartPurchaseBar(
      bundle: bundle,
      buttonLabel: label,
      busy: busy,
      onPurchase: state.canBuy(bundle.productId) ? _openPurchaseSheet : null,
    );
  }

  /// 결제 불가이거나, 스토어는 열렸는데 이 상품의 가격 · 계정 표시가 없으면 "구매할 수 없어요".
  String _idleLabel(HeartPurchaseUiState state, HeartBundle bundle) {
    final unavailable = state.availability == HeartStoreAvailability.unavailable ||
        (state.availability == HeartStoreAvailability.available && !state.canBuy(bundle.productId));
    return unavailable ? '구매할 수 없어요' : '${bundle.quantityLabel} 받기 · ${bundle.priceLabel}';
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

/// 구매하기 `zEdiV`(15e-1 `Bbp5P`): 제목 20/600 → 12 → 안내 → 12 → 번들 카드 5장(사이 16, 추천 태그가 걸치는 위 12) → 12 → 결제 안내.
class _PurchaseSection extends ConsumerWidget {
  const _PurchaseSection({required this.state});

  final HeartPurchaseUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              for (final (index, bundle) in heartBundles.map(state.priced).indexed) ...[
                if (index > 0) const SizedBox(height: AppSpacing.md),
                HeartBundleCard(
                  bundle: bundle,
                  selected: bundle.productId == state.selectedProductId,
                  bonusHearts: state.bonusFor(bundle),
                  onTap: () => ref.read(heartPurchaseViewModelProvider.notifier).select(bundle.productId),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 결제 안내 `saa1s`(PaymentNotice `bBjRD`).
        const HeartPaymentNotice(),
      ],
    );
  }
}

/// 무료로 모으기 `EsnDC`: 제목 20/600 → 16 → 줄 3개(사이 4). 줄은 18a 의 [HeartTaskRow] 와 서버 목록을 그대로 쓴다.
/// 제목 아래 보상 기준 안내(`eAKKO`)는 내부용이라 지웠다(사용자 10-16 "우리만 아는거야") — pen 은 Spacer 8 만 남았다
/// (섹션 328×243 간격 4: 제목 → 4 → 여백 8 → 4 → 첫 줄, 대장 전달 값 10-17).
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
        const SizedBox(height: AppSpacing.xxs + AppSpacing.xs + AppSpacing.xxs),
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
