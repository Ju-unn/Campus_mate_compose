import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/avatar_regen_sheet.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/avatar_regen_pick_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/view/avatar_source_tile.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15b-4 / 15b-5 아바타 다시 만들기 · 사진 고르기(pen `nN9EC` 고르기 전 · `J4qtZj` 고른 뒤). 화면 15 히어로의 "다시 만들기 · 10"
/// (`R5Quru`)이 연다. 갤러리에서 새 사진 한 장을 먼저 고르면 그 사진이 지금 아바타 원본 사진을 **대신한다**(사용자 결정 2026-10-08).
///
/// 순서: 사진 고르기 → "이 사진으로 아바타 만들기" → 하트 확인 시트(15b · 15b-2 · 15b-3, 문구는 그대로) → 사진 교체 → 아바타 등록 →
/// 15 로 돌아가 "아바타로 변환 중이에요"(15-2). 하트가 모자라면 시트에서 막히고 이때는 사진도 바꾸지 않는다.
/// 가입 04-3 의 사진 칸 · 안내 카드 · 버튼을 그대로 쓰고, 새로 지은 글은 상단 막대 제목과 부제뿐이다.
class AvatarRegenPickScreen extends ConsumerStatefulWidget {
  const AvatarRegenPickScreen({super.key});

  @override
  ConsumerState<AvatarRegenPickScreen> createState() => _AvatarRegenPickScreenState();
}

class _AvatarRegenPickScreenState extends ConsumerState<AvatarRegenPickScreen> {
  /// 사진 칸 158×158(pen `I7hYbr` · `BWH9J`).
  static const double _tileSize = 158;

  @override
  Widget build(BuildContext context) {
    ref.listen(avatarRegenPickViewModelProvider, (previous, next) {
      // 등록까지 끝났다 — 15 로 돌아가면 15 가 만드는 중 안내를 보인다.
      if (next.completed && previous?.completed != true && mounted) {
        context.pop();
      }
    });
    final state = ref.watch(avatarRegenPickViewModelProvider);
    final viewModel = ref.read(avatarRegenPickViewModelProvider.notifier);
    return Scaffold(
      appBar: const EditAppBar(title: '아바타 다시 만들기'),
      body: SafeArea(
        top: false,
        // pen `Q4Rry` 안쪽 [0,16,28,16].
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사진 칸이 158 고정이라 작은 기기 · 큰 글씨에서는 위쪽이 넘친다 — 넘치는 쪽을 스크롤로 내주고 버튼은 늘 바닥에 남긴다
              // (04-3 과 같은 얼개).
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Text('아바타로 만들 사진을 골라주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '고른 사진 한 장이 새 아바타로 변환돼요.',
                        style: AppTypography.body.copyWith(color: AppColors.body, height: 1.6),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox.square(dimension: _tileSize, child: _tile(state, viewModel)),
                      const SizedBox(height: AppSpacing.md),
                      const NoticeCard(
                        icon: AppIcons.lock,
                        title: '상호 수락 전에는 아바타만 보여요',
                        body: '올린 실제 사진은 서로 수락하고 신뢰 확인을 마친 뒤에 공개돼요.',
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          state.errorMessage!,
                          style: AppTypography.caption.copyWith(color: AppColors.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: '이 사진으로 아바타 만들기',
                isLoading: state.isSubmitting,
                onPressed: state.canSubmit ? _confirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 고르기 전 = 빈 "사진 추가" 칸(15b-4), 살펴보는 중 = 도는 칸, 고른 뒤 = 사진 + "아바타로 선택" 배지(15b-5).
  /// 고른 뒤에 칸을 다시 누르면 다른 사진으로 바꾼다.
  Widget _tile(AvatarRegenPickUiState state, AvatarRegenPickViewModel viewModel) {
    final photo = state.photo;
    if (state.isChecking) {
      return const CheckingTile();
    }
    if (photo == null) {
      return AddPhotoTile(onTap: viewModel.pick);
    }
    return AvatarSourceTile(image: FileImage(photo), isSelected: true, onTap: state.isSubmitting ? null : viewModel.pick);
  }

  /// 하트 확인 시트를 먼저 보이고, 만들기를 고르면 사진 교체 → 아바타 등록을 한다. 충전을 고르면 하트 스토어로 간다(사진은 안 바꾼다).
  Future<void> _confirm() async {
    final profile = ref.read(myProfileProvider).value?.when(onSuccess: (value) => value, onFailure: (_) => null);
    if (profile == null) return;
    final choice = await showAvatarRegenSheet(
      context,
      cost: profile.avatarRegenCost,
      heartBalance: profile.heartBalance,
    );
    if (!mounted) return;
    switch (choice) {
      case AvatarRegenChoice.regenerate:
        await ref.read(avatarRegenPickViewModelProvider.notifier).submit();
      case AvatarRegenChoice.chargeHearts:
        await context.push(AppRoutes.heartStore);
      case null:
        break;
    }
  }
}
