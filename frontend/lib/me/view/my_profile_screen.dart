import 'package:campus_mate/billing/view/heart_balance_chip.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/view/my_friend_reviews_section.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/avatar_regen_sheet.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/view/profile_hero.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 화면 15 내 프로필(pen `nkFJV`). 히어로(`l8p6X`) → 입구 두 줄(15-4 · 15-5) → 지인 리뷰 칸(20c · 20e). 실사진 · 기본 정보 · 선호 조건 ·
/// 자기소개는 15-5 프로필 편집(`profile_manage_screen.dart`)으로 옮겼다(계획서 2026-09-28-me-profile.md N1).
/// 앱바 톱니가 설정(16)으로 가는 유일한 문이다(DESIGN §9 화면 15).
///
/// 히어로 알약이 15b 시트를 열고 다시 만들기를 맡긴다. 만드는 동안 알약을 끄고(15-2) 변환 중 안내를, 실패하면 15-3
/// 안내를 띄우고, 완성되면 내 프로필을 다시 읽는다(새 그림 · 잔액 · 비용). 뷰모델은 온보딩(04-3 · 05-12)과 같이 쓴다.
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> with MeToastHost<MyProfileScreen> {
  /// 15-2 `fLkE8` — 04-3 토스트와 같은 도는 표시(loader-circle 16 자리). 만드는 동안 계속 떠 있다.
  static const _generatingToast = AppToast(
    leading: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onInk),
    label: '아바타로 변환 중이에요',
  );

  /// 15-3 `k110R`(C7) — 하트는 완성된 뒤에만 빠진다(T2).
  static const _failedToast = AppToast(
    leading: Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
    label: '아바타를 만들지 못했어요.\n하트는 차감되지 않았어요.',
  );

  /// 열려 있는 화면 15 수. 뷰모델의 폴링 타이머는 하나라, 떠난 화면이 뒤늦게 끊으면 돌아온 화면의 폴링까지 끊긴다.
  static var _openCount = 0;

  late final AvatarGenerationViewModel _avatar;

  @override
  void initState() {
    super.initState();
    _openCount++;
    // 화면을 닫는 순간에는 ref 를 쓸 수 없어 미리 잡아 둔다(05-12 와 같은 방식).
    _avatar = ref.read(avatarGenerationViewModelProvider.notifier);
    // 만드는 중에 떠났다 돌아왔으면 멈춘 폴링을 다시 잇는다(Review Focus 3). idle 에서 부르면 "기다리는 중" 으로 보고
    // 계속 묻기 시작하므로 만드는 중일 때만.
    if (ref.read(avatarGenerationViewModelProvider).isGenerating) {
      Future.microtask(_avatar.refreshStatus);
    }
  }

  @override
  void dispose() {
    _openCount--;
    // 뷰모델은 화면보다 오래 산다(온보딩과 같이 쓴다) — 떠나는 쪽이 직접 끊는다.
    _avatar.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(avatarGenerationViewModelProvider, _onAvatarChanged);
    final isGenerating = ref.watch(avatarGenerationViewModelProvider.select((state) => state.isGenerating));
    return Scaffold(
      // pen `hwVQB` — 09b 첫 화면과 같은 관례: 제목 x20, 톱니 48 뒤 오른쪽 여백 8.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('내 프로필', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        actions: [
          // 하트 잔액 칩 `MjtQA` 81×44 — 톱니 바로 왼쪽, 사이 4(`hwVQB` 칩 x219~300 · 톱니 x304). "+" 는 없다.
          const HeartBalanceChip(),
          const SizedBox(width: AppSpacing.xxs),
          IconButton(
            tooltip: '설정',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(AppIcons.settings, size: 22, color: AppColors.ink),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.me),
      // 토스트는 한 번에 하나 — 만드는 동안은 변환 중 안내가 자리를 쥔다(그동안 알약이 꺼져 다른 안내가 생길 길이 없다).
      body: MeToastLayer(toast: isGenerating ? _generatingToast : timedToast, child: _body(isGenerating)),
    );
  }

  /// 불러오는 중·실패는 pen 에 없는 상태다 — 가운데 로딩 / [MeLoadError](15-4 · 15-5 와 같은 모양, 계획서 N9).
  Widget _body(bool isGenerating) {
    void retry() => ref.invalidate(myProfileProvider);
    return ref.watch(myProfileProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MeLoadError(onRetry: retry),
          data: (result) => result.when(
            onSuccess: (profile) => _ProfileContent(
              profile: profile,
              // 15-2 `EAqjZ` — 만드는 동안 알약은 꺼진다.
              onRegenerate: isGenerating ? null : () => _openRegenSheet(profile),
            ),
            onFailure: (_) => MeLoadError(onRetry: retry),
          ),
        );
  }

  /// 만드는 중이 끝난 순간만 본다. 완성 → 새 그림 · 잔액 · 비용을 다시 읽는다. 실패 → 15-3 안내, 단 등록 자체가
  /// 거절돼 서버 문구가 있으면(402 — 시트를 연 사이 잔액이 줄었을 때 등) 그 문구를 같은 자리 · 모양으로.
  void _onAvatarChanged(AvatarGenerationUiState? previous, AvatarGenerationUiState next) {
    if (previous?.isGenerating != true || next.isGenerating) return;
    final message = next.errorMessage;
    switch (next.status) {
      case AvatarGenerationStatus.ready || AvatarGenerationStatus.fallback:
        ref.invalidate(myProfileProvider);
      case AvatarGenerationStatus.failed:
        showTimedToast(message == null ? _failedToast : _alertToast(message));
      default:
        break;
    }
  }

  static AppToast _alertToast(String message) =>
      AppToast(leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk), label: message);

  /// 15b 시트(값은 서버 `avatar_regen_cost` · `heart_balance`). 하트 상점은 아직 없어 충전은 "곧 열려요"(C5).
  Future<void> _openRegenSheet(MyProfile profile) async {
    final choice = await showAvatarRegenSheet(
      context,
      cost: profile.avatarRegenCost,
      heartBalance: profile.heartBalance,
    );
    switch (choice) {
      case AvatarRegenChoice.regenerate:
        await _regenerate();
      case AvatarRegenChoice.chargeHearts:
        showTimedToast(comingSoonToast);
      case null:
        break;
    }
  }

  /// 결과(완성 · 실패 · 서버 문구)는 [_onAvatarChanged] 가 상태 변화로 받는다 — 돌려받는 문구는 거기서 이미 보였다.
  Future<void> _regenerate() async {
    await _avatar.regenerate();
    // 등록 응답을 기다리는 사이 화면을 떠났으면 방금 걸린 폴링을 끊는다 — dispose 는 이미 지나갔다.
    // 그사이 15 를 다시 열었으면 그 화면이 폴링을 쥐고 있으니 그대로 둔다.
    if (!mounted && _openCount == 0) _avatar.stopPolling();
  }
}

/// 본문 — 히어로 자리 `nrcYh`(위 8 · 좌우 16) → 히어로 → 44 → 입구 두 줄(`sx7MA`, 사이 12) → 32 → 지인 리뷰 칸(`Cux1p`) → 아래 40.
class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile, required this.onRegenerate});

  final MyProfile profile;
  final VoidCallback? onRegenerate;

  /// 히어로 ↔ 입구 줄 = 히어로 자리 아래 20 + 본문 `rcsgx` 위 24.
  static const double _heroToEntries = 20 + AppSpacing.lg;

  /// 본문 `rcsgx` 아래 40(간격 토큰 xl 32 · xxl 48 사이).
  static const double _bottomPadding = 40;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, _bottomPadding),
      children: [
        ProfileHero(profile: profile, onRegenerate: onRegenerate),
        const SizedBox(height: _heroToEntries),
        ProfileEntryRow(
          icon: AppIcon3d.mascotPeek,
          iconSize: 32, // pen `I5Dw4` 32 · 원 안 6,6
          title: '남이 보는 내 프로필 카드',
          note: '상대에게 보이는 모습을 미리 봐요',
          onTap: () => context.push(AppRoutes.myCardPreview),
        ),
        const SizedBox(height: AppSpacing.sm),
        ProfileEntryRow(
          icon: AppIcon3d.pencil,
          title: '프로필 편집',
          note: '사진·기본 정보·선호 조건·자기소개',
          onTap: () => context.push(AppRoutes.myProfileManage),
        ),
        const SizedBox(height: AppSpacing.xl), // 입구 줄 아래 32(N3)
        const MyFriendReviewsSection(), // 지인 리뷰 `Cux1p` → 20c · 20e
      ],
    );
  }
}
