import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 아바타 **결과** 화면(DESIGN.md 05-12 · 05-12b · 05-12c · 05-12d).
///
/// 그림은 04-3 에서 이미 등록됐고 서버가 뒤에서 만든다 — 이 화면은 **보는 자리**다.
/// 여기서 생성을 시작하지 않는다. 시작하면 성향 질문을 마치고 들어올 때마다 새 작업이 등록된다.
class AvatarGenerationScreen extends ConsumerStatefulWidget {
  const AvatarGenerationScreen({super.key});

  @override
  ConsumerState<AvatarGenerationScreen> createState() => _AvatarGenerationScreenState();
}

class _AvatarGenerationScreenState extends ConsumerState<AvatarGenerationScreen> {
  late final AvatarGenerationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // 화면을 닫는 순간에는 ref 를 쓸 수 없어 미리 잡아 둔다(chat_room_screen 과 같은 방식).
    _viewModel = ref.read(avatarGenerationViewModelProvider.notifier);
    Future.microtask(_viewModel.refreshStatus);
  }

  @override
  void dispose() {
    // 화면을 떠나면 그만 묻는다. 뷰모델은 화면보다 오래 살아서(04-3 과 같이 쓴다) 저절로 안 끊긴다.
    _viewModel.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(avatarGenerationViewModelProvider, (previous, next) {
      if (next.showCompensationDialog && previous?.showCompensationDialog != true) {
        _showCompensationSheet(next.compensationHearts);
      }
    });
    final state = ref.watch(avatarGenerationViewModelProvider);
    final viewModel = ref.read(avatarGenerationViewModelProvider.notifier);
    return Scaffold(
      // 여기 오는 사람은 설문까지 이미 끝냈다 — 다 찬 설문 막대를 그대로 둔다(pen 05-12).
      // 04-x 의 6점 묶음이 아니다. `_bar()` 가 (current+1)/total 이라 이 값이 정확히 1.0 이다.
      appBar: const OnboardingAppBar(current: 0, total: 1, isBar: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
          child: _content(state, viewModel),
        ),
      ),
    );
  }

  Widget _content(AvatarGenerationUiState state, AvatarGenerationViewModel viewModel) {
    return switch (state.status) {
      // idle 은 아직 한 번도 못 물어본 자리다 — 깜빡이지 않게 만드는 중과 같은 표시를 둔다.
      AvatarGenerationStatus.idle ||
      AvatarGenerationStatus.generating =>
        const Center(child: _GeneratingIndicator()),
      AvatarGenerationStatus.failed =>
        Center(child: _RetryPrompt(state: state, onRetry: viewModel.retry)),
      // 05-12d 는 따로 된 화면이 아니라 05-12c 위에 얹는 시트다(pen) —
      // 기본 아바타도 완성된 아바타와 같은 자리에 같은 문구로 보여 주고, 사정은 시트가 말한다.
      AvatarGenerationStatus.ready ||
      AvatarGenerationStatus.fallback =>
        _AvatarResult(avatarUrl: state.avatarUrl, onNext: viewModel.goToNextStep),
    };
  }

  /// 05-12d 보상 안내(pen `Q7VmU`). **시트다** — 화면을 갈아끼우면 방금 만든 아바타가 사라진다.
  void _showCompensationSheet(int hearts) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다(14f 시트와 같다).
      barrierColor: AppColors.scrim,
      builder: (sheetContext) => _CompensationSheet(
        hearts: hearts,
        onConfirm: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }
}

class _GeneratingIndicator extends StatelessWidget {
  const _GeneratingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.md),
        Text('아바타를 만들고 있어요', style: AppTypography.body.copyWith(color: AppColors.body)),
      ],
    );
  }
}

/// 05-12c(pen `tzqhO`) — 기본 아바타(05-12d)도 같은 화면을 쓴다.
class _AvatarResult extends StatelessWidget {
  const _AvatarResult({required this.avatarUrl, required this.onNext});

  final String? avatarUrl;

  /// 다음 단계로 넘어가는 유일한 길. 사람이 그림을 다 본 뒤에 스스로 누른다.
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xl),
        _AvatarCard(avatarUrl: avatarUrl),
        const SizedBox(height: AppSpacing.lg),
        Text('아바타가 완성됐어요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.body, height: 1.6),
        ),
        // 글이 길어져도 버튼은 바닥에 남는다(pen 은 하단 고정 328×56).
        const Spacer(),
        AppButton(label: '다음', onPressed: onNext),
      ],
    );
  }
}

/// 아바타 카드(pen `O4GEqx` 높이 280 · 안쪽 그림 `fuTBa` 180×180).
/// 주소는 서버가 완성해서 준 것 그대로다. 앞에 무엇도 붙이지 않는다(버킷을 바꾸면 전부 깨진다).
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 280,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: avatarUrl == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                avatarUrl!,
                width: 180,
                height: 180,
                fit: BoxFit.cover,
                // 그림만 못 받았다고 빈 화면을 두지 않는다 — 아바타는 서버에 이미 있고, 다음으로도 가야 한다.
                // 대신 띄울 문구가 pen 에 없어 카드만 비워 둔다(대장 2026-09-26 결정).
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(width: 180, height: 180),
              ),
            ),
    );
  }
}

/// 05-12d 기본 아바타 안내 시트(pen `Q7VmU`). 버튼은 "확인" 하나다 — pen 의 취소 버튼은 꺼져 있다.
class _CompensationSheet extends StatelessWidget {
  const _CompensationSheet({required this.hearts, required this.onConfirm});

  final int hearts;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '기본 아바타로 대신했어요',
              style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            // 하트 수는 서버가 준 값 그대로다 — 앱에 숫자를 박으면 규칙이 바뀔 때 앱만 거짓말을 한다.
            Text(
              '서버 오류로 하트 $hearts개 드렸어요. 설정 > 아바타 재생성 에서 다시 만들 수 있어요.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: '확인', onPressed: onConfirm),
          ],
        ),
      ),
    );
  }
}

class _RetryPrompt extends StatelessWidget {
  const _RetryPrompt({required this.state, required this.onRetry});

  final AvatarGenerationUiState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('아바타를 만들지 못했어요', style: AppTypography.body.copyWith(color: AppColors.body)),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(label: '다시 만들기', onPressed: onRetry),
      ],
    );
  }
}
