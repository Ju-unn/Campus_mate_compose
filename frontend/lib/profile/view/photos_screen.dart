import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:campus_mate/profile/view/onboarding_back.dart';
import 'package:campus_mate/profile/view/photo_example.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 설명 바로 아래 안내 한 줄(pen `F5DPI` · `EvcRf` · `SQgyO` 의 HintLine) — 실사진이 언제 상대에게 보이는지.
const photoVisibilityHint = '올린 실제 사진은 서로 수락하고 신뢰 확인을 마친 뒤에 상대방에게 보여요';

/// 사진 업로드 화면(DESIGN.md 화면 04-2, datingApp.pen `F5DPI`).
/// 최소 2장·최대 4장을 고르기만 하고, 올리기는 다음 화면 04-3 에서 아바타 원본을 정한 뒤 한 번에 한다
/// (2026-09-23 사용자 결정 — 2026-09-20 C2 의 "한 화면으로 합치기"를 되돌림).
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  /// 04-3 으로 넘어가는 중. **빠르게 두 번 누르면 04-3 이 두 장 쌓인다** —
  /// 돌아올 때까지 버튼을 꺼 둔다.
  bool _isLeaving = false;

  /// 지금 떠 있는 안내. 겹쳐 뜨지 않게 한 번에 하나만 들고 있는다(pen `EvcRf`).
  String? _toast;
  Timer? _toastTimer;

  /// pen 에 표시 시간이 없고 앱에 정해 둔 값도 없어 3초로 둔다.
  static const Duration _toastDuration = Duration(seconds: 3);

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) {
        setState(() => _toast = null);
      }
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _goToAvatarSource() async {
    setState(() => _isLeaving = true);
    ref.read(photosViewModelProvider.notifier).prepareAvatarSource();
    await context.push<void>(AppRoutes.onboardingAvatarSource);
    if (mounted) {
      setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photosViewModelProvider);
    final viewModel = ref.read(photosViewModelProvider.notifier);
    // 안내는 칸 아래 글이 아니라 버튼 위 토스트로 나간다(pen `EvcRf`).
    ref.listen(photosViewModelProvider, (previous, next) {
      if (next.errorMessage != null) {
        _showToast(next.errorMessage!);
      }
    });
    // 04-1b 로 돌아간다(04-2 는 아직 지금 단계라 고른 사진은 메모리 · 임시 저장에 남는다). 저장 중(04-3 올리기)엔 무시한다.
    // 시스템 뒤로도 같다 — 라우터는 이 화면을 두르지 않는다(두 겹이면 안내까지 뜬다). 04-3 이 위에 있으면 04-3 이 먼저 닫힌다.
    final back = onboardingBack(ref, isBusy: state.isSubmitting);
    return BackExitScope(onBack: back, child: Scaffold(
      appBar: OnboardingAppBar(current: 1, total: 6, onBack: back),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사진 칸이 158 고정이라 작은 기기·큰 글씨에서는 위쪽이 넘친다. 남는 세로(Fill)는 이 칸이 먹는다.
              // 넘치는 쪽을 스크롤로 내주고 버튼은 늘 바닥에 남긴다(3b 와 같은 얼개).
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Text('실제 사진을 올려주세요',
                          style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '얼굴이 잘 보이는 사진을 2~4장 골라주세요.',
                        style: AppTypography.body.copyWith(color: AppColors.body, height: 1.6),
                      ),
                      // pen `F5DPI` · `EvcRf` · `SQgyO`: 부제 → 12 → 공개 안내 한 줄(HintLine, 두 줄로 접힌다) → 32 → 예시.
                      const SizedBox(height: AppSpacing.sm),
                      const HintLine(photoVisibilityHint),
                      // pen 재배치(campus-pen 10-16): 좋은 사진 예시 → 16 → 안내 한 줄 → 16 → 사진 칸 → 16 → 설명 줄 둘 — 예시가 첫 화면에 온다.
                      // 안내 ↔ 예시 32 는 종전 부제 ↔ 첫 덩어리 값 그대로(이번 값표에 없음).
                      const SizedBox(height: AppSpacing.xl),
                      const PhotoExample.goodPhoto(),
                      const SizedBox(height: AppSpacing.md),
                      const _PhotoRulesNotice(),
                      const SizedBox(height: AppSpacing.md),
                      PhotoSlotGrid(
                        state: state,
                        viewModel: viewModel,
                        columnGap: AppSpacing.sm,
                        markRejectedSlot: true,
                      ),
                      if (state.documentRejected) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const PhotoDocumentNote(),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      const HintLine('갤러리에서 여러 장을 한 번에 고를 수 있어요. 최소 2장이 필요해요.'),
                      // pen `hco2A` 실측 6. 간격 토큰 xxs(4)·xs(8) 사이 값이라 토큰으로 갈음하지 않는다.
                      const SizedBox(height: 6),
                      const HintLine('사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_toast != null) ...[
                Center(
                  child: AppToast(
                    leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                    label: _toast!,
                  ),
                ),
                // 버튼과 간격 12(pen 실측).
                const SizedBox(height: AppSpacing.sm),
              ],
              AppButton(
                label: '다음',
                // 살펴보는 중에 넘어가면 늦게 끝난 검사가 04-3 이 올리는 목록에 끼거나,
                // 이미 올라간 화면 위에 '…빠졌어요' 토스트가 얹힌다.
                onPressed: state.canProceed && !state.isCheckingPhotos && !_isLeaving
                    ? _goToAvatarSource
                    : null,
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

/// 안내 한 줄(pen 04-2 Notice, campus-pen 10-16): 아이콘 · 머리 없이 본문 한 줄 12/normal, 안쪽 14 · 높이 46(글자를 키우면 늘어난다).
/// 바탕 · 모서리 · 본문 색과 줄높이 1.5 는 안내 카드 기본형(`NoticeCard`)과 같다 — 공용 카드는 아이콘 · 제목이 필수라 이 화면 안에 둔다.
class _PhotoRulesNotice extends StatelessWidget {
  const _PhotoRulesNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(12)),
      child: Text(
        '글자 많은 사진·얼굴 가린 사진은 올릴 수 없어요',
        style: AppTypography.caption.copyWith(color: AppColors.body, height: 1.5),
      ),
    );
  }
}
