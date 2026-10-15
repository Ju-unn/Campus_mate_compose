import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
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

  /// 상태가 바뀌면 standard 동안 겹쳐 바꾼다(만드는 중 → 완성). 평생 한 번 순간이지만 emphasis 는
  /// 하루 두 번(카드 등장 · 매칭 성사)만 쓰는 토큰이라 standard 다(DESIGN §7). 동작 줄이기면 바로 바뀐다.
  Widget _content(AvatarGenerationUiState state, AvatarGenerationViewModel viewModel) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.standardCurve,
      // 같은 갈래(만드는 중 · 실패 · 완성) 안에서 바뀔 때는 겹치지 않는다 — 갈래 이름이 열쇠다.
      child: KeyedSubtree(key: ValueKey(_branch(state.status)), child: _branchView(state, viewModel)),
    );
  }

  static String _branch(AvatarGenerationStatus status) => switch (status) {
    AvatarGenerationStatus.idle || AvatarGenerationStatus.generating => 'generating',
    AvatarGenerationStatus.failed => 'failed',
    AvatarGenerationStatus.ready || AvatarGenerationStatus.fallback => 'result',
  };

  Widget _branchView(AvatarGenerationUiState state, AvatarGenerationViewModel viewModel) {
    return switch (state.status) {
      // idle 은 아직 한 번도 못 물어본 자리다 — 깜빡이지 않게 만드는 중과 같은 표시를 둔다.
      AvatarGenerationStatus.idle ||
      AvatarGenerationStatus.generating =>
        const _GeneratingIndicator(),
      AvatarGenerationStatus.failed =>
        _RetryPrompt(state: state, onRetry: viewModel.retry),
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

/// 05-12(pen `OgHRY`) — 파란 목도리 마스코트 아래 도는 표시 28(lucide loader-circle 자리, muted).
class _GeneratingIndicator extends StatelessWidget {
  const _GeneratingIndicator();

  @override
  Widget build(BuildContext context) {
    return const _StatusView(
      title: '아바타를 만들고 있어요',
      subtitle: '선택한 사진으로 아바타를 만드는 중이에요. 잠시만 기다려 주세요.',
      mascotAsset: 'assets/images/mascot-male-waiting.png',
      below: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.muted),
      ),
    );
  }
}

/// 05-12 · 05-12b 공통 얼개(대장 전달 pen 값 10-15). 위 24 → 제목 24/700 → 8 → 부제 16/400 body lh1.6 → 32 → 상태 틀
/// (위 45 · 안 간격 12: 마스코트 220 → [below]) → 바닥 [action](05-12b 만). pen 부제는 328 폭에서 두 줄이라 마스코트가
/// y249 다(56 + 24 + 32.4 + 8 + 51.2 + 32 + 45 ≈ 249) — 글자를 키우거나 좁은 폰이면 그만큼 내려간다.
/// 글이 길어져도 버튼은 바닥에 남고 위쪽만 스크롤한다(05-12c 와 같은 얼개). 한 화면 마스코트 한 마리.
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    required this.subtitle,
    required this.mascotAsset,
    required this.below,
    this.action,
  });

  final String title;
  final String subtitle;
  final String mascotAsset;
  final Widget below;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: AppTypography.headline.copyWith(color: AppColors.ink)),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: AppTypography.body.copyWith(color: AppColors.body)),
                const SizedBox(height: AppSpacing.xl),
                // 상태 틀 328 × 340 — 글자를 키우면 넘치지 않게 340 은 최소 높이로 둔다.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 340),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 45),
                    child: Column(
                      children: [
                        Image.asset(mascotAsset, width: 220, height: 220, fit: BoxFit.contain, excludeFromSemantics: true),
                        const SizedBox(height: AppSpacing.sm),
                        below,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ?action,
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
    final bodyStyle = AppTypography.body.copyWith(color: AppColors.body, height: 1.6);
    return Column(
      children: [
        // 글이 길어져도 버튼은 바닥에 남는다(pen 은 하단 고정 328×56) — 작은 화면 · 큰 글씨에서는 위쪽을 스크롤로 내준다.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                _AvatarCard(avatarUrl: avatarUrl),
                const SizedBox(height: AppSpacing.lg),
                Text('아바타가 완성됐어요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                const SizedBox(height: AppSpacing.xs),
                Text('마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.', textAlign: TextAlign.center, style: bodyStyle),
                // 5b 아바타 공개 안내(pen `FXQlf` 설명 문구)를 따로 된 화면 없이 한 줄로 합쳤다(사용자 요청 10-15). 제목 "짜잔, …" 과
                // 실사진 · 흐림 비교 카드 둘은 넣지 않는다. 글자 · 간격은 위 부제와 같게 둔다(pen 확인 대상).
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '매칭 전에는 AI가 그려준 아바타만 보여요. 상호 수락 후 신뢰 확인을 마치면 실제 사진이 공개돼요.',
                  textAlign: TextAlign.center,
                  style: bodyStyle,
                ),
              ],
            ),
          ),
        ),
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
                frameBuilder: _reveal,
                // 그림만 못 받았다고 빈 화면을 두지 않는다 — 아바타는 서버에 이미 있고, 다음으로도 가야 한다.
                // 대신 띄울 문구가 pen 에 없어 카드만 비워 둔다(대장 2026-09-26 결정).
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(width: 180, height: 180),
              ),
            ),
    );
  }

  /// 그림이 도착하면 투명 · 0.96 에서 standard 동안 제자리로(transform · opacity 만 — 자리 180×180 은 처음부터 그대로).
  /// 캐시에 있어 바로 그려지면 효과 없이 둔다. 동작 줄이기면 시간 0.
  static Widget _reveal(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
    if (wasSynchronouslyLoaded) return child;
    final arrived = frame != null;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard;
    return AnimatedOpacity(
      opacity: arrived ? 1 : 0,
      duration: duration,
      curve: AppMotion.standardCurve,
      child: AnimatedScale(
        scale: arrived ? 1 : _revealScaleFrom,
        duration: duration,
        curve: AppMotion.standardCurve,
        child: child,
      ),
    );
  }
}

/// 그림이 나타나기 시작하는 크기(대장 지시 10-14 — pen 에 모션 값은 없다).
const double _revealScaleFrom = 0.96;

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

/// 05-12b(pen `c7QuSm`) — 분홍 목도리 마스코트 아래 힌트 한 줄 13/400 muted. 서버 문구가 있으면 같은 자리 · 같은 글꼴로
/// 그 문구를 둔다. 부제 · 버튼 "다시 시도" 는 pen 원문 그대로다(대장 전달 10-15 — "시도해주세요" 붙여 쓰기도 원문).
class _RetryPrompt extends StatelessWidget {
  const _RetryPrompt({required this.state, required this.onRetry});

  final AvatarGenerationUiState state;
  final Future<void> Function() onRetry;

  /// 서버 규칙(`MAX_CONSECUTIVE_FAILURES` 5 — 연속 실패 5번까지 무료, 5번째에 기본 아바타 + 하트)과 같은 숫자다.
  /// 종전 pen 원문 "3번까지" 는 서버와 달라 사용자 결정(10-15 "추천")으로 고쳤다(pen 도 함께 정정).
  static const String _freeRetryHint = '5번까지는 무료로 다시 시도할 수 있어요';

  @override
  Widget build(BuildContext context) {
    return _StatusView(
      title: '아바타 생성에 실패했어요',
      subtitle: '사진이 흐릿하거나 서버가 혼잡했을 수 있어요. 다른 사진으로 다시 시도해주세요.',
      mascotAsset: 'assets/images/mascot-female-sad.png',
      below: Text(
        state.errorMessage ?? _freeRetryHint,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(fontSize: 13, color: AppColors.muted),
      ),
      action: AppButton(label: '다시 시도', onPressed: onRetry),
    );
  }
}
