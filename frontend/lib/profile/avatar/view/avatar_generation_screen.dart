import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/data/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/avatar/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/avatar/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 아바타 확인 화면 — 가입 맨 끝, 06-3 뒤 · 20 앞(2026-10-17 사용자 결정). DESIGN.md 05-12 · 05-12b · 5b 리빌 · 05-12d.
///
/// 그림은 04-3 에서 이미 등록됐고 서버가 뒤에서 만든다 — 이 화면은 **보는 자리**다. 여기서 생성을 시작하지 않는다.
/// 앱바 · 진행 막대 · 뒤로가 없다(pen `F84Alv` · `OgHRY` · `euW4T`) — 06-3 저장 순간 가입이 끝날 수 있어 되돌아갈 곳이 없다.
/// 안드로이드 시스템 뒤로는 라우터가 두른 종료 안내(BackExitScope)가 맡는다.
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
    return Scaffold(body: SafeArea(child: _content(state)));
  }

  /// 상태가 바뀌면 standard 동안 겹쳐 바꾼다(만드는 중 → 리빌). 평생 한 번 순간이지만 emphasis 는
  /// 하루 두 번(카드 등장 · 매칭 성사)만 쓰는 토큰이라 standard 다(DESIGN §7). 동작 줄이기면 바로 바뀐다.
  Widget _content(AvatarGenerationUiState state) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.standardCurve,
      // 같은 갈래(만드는 중 · 실패 · 리빌) 안에서 바뀔 때는 겹치지 않는다 — 갈래 이름이 열쇠다.
      child: KeyedSubtree(key: ValueKey(_branch(state.status)), child: _branchView(state)),
    );
  }

  static String _branch(AvatarGenerationStatus status) => switch (status) {
    AvatarGenerationStatus.idle || AvatarGenerationStatus.generating => 'generating',
    AvatarGenerationStatus.failed => 'failed',
    AvatarGenerationStatus.ready || AvatarGenerationStatus.fallback => 'result',
  };

  Widget _branchView(AvatarGenerationUiState state) {
    return switch (state.status) {
      // idle 은 아직 한 번도 못 물어본 자리다 — 깜빡이지 않게 만드는 중과 같은 표시를 둔다.
      AvatarGenerationStatus.idle ||
      AvatarGenerationStatus.generating =>
        const _GeneratingIndicator(),
      AvatarGenerationStatus.failed =>
        _RetryPrompt(state: state, onRetry: _viewModel.retry),
      // 완성이면 기다림 없이 곧바로 리빌이다. 05-12d 는 따로 된 화면이 아니라 리빌 위에 얹는 시트다(pen) —
      // 기본 아바타도 같은 자리에 같은 문구로 보여 주고, 사정은 시트가 말한다.
      AvatarGenerationStatus.ready ||
      AvatarGenerationStatus.fallback =>
        _AvatarReveal(avatarUrl: state.avatarUrl, onConfirm: _confirm),
    };
  }

  /// 리빌 "확인했어요" · 05-12d 시트 "확인". 단계를 다시 물은 뒤 20(추천 코드)으로 간다 — 06-3 과 같은 모양.
  /// 다시 묻는 순간 서버가 다 끝낸 사람의 가입을 확정한다(`GET next-step`, PR #574). 서버를 따로 부르지 않는다.
  /// 조회가 실패해 단계가 아직 avatar 면 라우터가 이 화면으로 되돌린다 — 사람은 다시 누르면 된다.
  Future<void> _confirm() async {
    await _viewModel.goToNextStep();
    if (mounted) context.go(AppRoutes.onboardingReferral);
  }

  /// 05-12d 보상 안내(pen `Q7VmU`). **시트다** — 화면을 갈아끼우면 방금 들어간 기본 아바타가 사라진다.
  /// "확인" 은 시트를 닫고 20 으로 간다(대장 전달 10-17). 바깥을 눌러 닫으면 리빌에 남아 "확인했어요" 로 간다.
  void _showCompensationSheet(int hearts) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다(14f 시트와 같다).
      barrierColor: AppColors.scrim,
      builder: (sheetContext) => _CompensationSheet(
        hearts: hearts,
        onConfirm: () {
          Navigator.of(sheetContext).pop();
          _confirm();
        },
      ),
    );
  }
}

/// 05-12 · 05-12b 의 위 여백(pen `OgHRY` · `euW4T` 제목 y64) · 리빌 바깥 위 64(`F84Alv`). 맞는 간격 토큰이 없다(xxl 48).
const double _topGap = 64;

/// 05-12(pen `OgHRY` → 움직이는 그림 판 `X0KAx`) — 그림 그리는 토끼 장면 344×330(아래 점 3개가 장면 안에 있다).
/// 옛 파란 목도리 마스코트 `gkWPR` 와 큰 스피너 `rcQm9` 는 이 장면이 대신한다. 제목 · 설명 아래 y268.
class _GeneratingIndicator extends StatelessWidget {
  const _GeneratingIndicator();

  /// 부제 두 줄 기준 장면 위가 y268 이 되는 상태 틀 위 간격(64 + 32.4 + 8 + 51.2 + 32 + 80 = 267.6 — 대장 전달 y268 에서 계산한 자리).
  static const double _paintingTop = 80;

  @override
  Widget build(BuildContext context) {
    return _StatusView(
      title: context.l10n.profileAvatarGeneratingTitle,
      subtitle: context.l10n.profileAvatarGeneratingSubtitle,
      visualTop: _paintingTop,
      visual: const _PaintingScene(),
    );
  }
}

/// 장면은 344 폭이라 좌우 16 여백(328)보다 넓다 — 여백 밖으로 8 씩 나와 화면 가로 가운데에 그린다(pen).
/// 위쪽 [SingleChildScrollView] 가 화면 폭 전체라 잘리지 않는다. 화면이 344+16 보다 좁으면 좌우 8 을 남기고
/// 비율 그대로 줄인다(CLAUDE.md 규칙 3 — 최대는 pen 크기 344×330).
class _PaintingScene extends StatelessWidget {
  const _PaintingScene();

  static const double _width = 344;
  static const double _height = 330;

  /// 장면이 좌우 여백(16) 밖으로 나오는 만큼(= (344 - 328) / 2, pen 화면 좌우에 남는 8).
  static const double _overflowPerSide = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(_width, constraints.maxWidth + 2 * _overflowPerSide);
        final height = _height * width / _width;
        return SizedBox(
          height: height,
          child: OverflowBox(
            minWidth: width,
            maxWidth: width,
            child: AppLottieView(scene: AppLottie.avatarPainting, width: width, height: height),
          ),
        );
      },
    );
  }
}

/// 05-12 · 05-12b 공통 얼개(대장 전달 pen 값 10-15 · 10-17). 바깥 [0,16,28,16] · 위 64 → 제목 24/700 → 8 → 부제 16/400 body lh1.6
/// → 32 → 상태 틀(위 [visualTop] · 안 간격 12: [visual] → [below]) → 바닥 [action](05-12b 만). 부제가 328 폭에서 두 줄이면 05-12b 마스코트가
/// y233 이다(64 + 32.4 + 8 + 51.2 + 32 + 45 ≈ 233 — 대장 값에서 계산한 자리) — 글자를 키우거나 좁은 폰이면 그만큼 내려간다.
/// 글이 길어져도 버튼은 바닥에 남고 위쪽만 스크롤한다. 한 화면 마스코트 한 마리.
/// 좌우 16 여백은 스크롤 안쪽 여백이라, 여백보다 넓은 [visual](05-12 장면 344)도 잘리지 않는다.
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    required this.subtitle,
    required this.visual,
    required this.visualTop,
    this.below,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget visual;

  /// 상태 틀 위에서 [visual] 까지(05-12b 마스코트 45, 05-12 장면 80).
  final double visualTop;
  final Widget? below;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: _topGap),
                  Text(title, style: AppTypography.headline.copyWith(color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: AppTypography.body.copyWith(color: AppColors.body)),
                  const SizedBox(height: AppSpacing.xl),
                  // 상태 틀 328 × 340 — 글자를 키우면 넘치지 않게 340 은 최소 높이로 둔다.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 340),
                    child: Padding(
                      padding: EdgeInsets.only(top: visualTop),
                      child: Column(
                        children: [
                          visual,
                          if (below case final below?) ...[
                            const SizedBox(height: AppSpacing.sm),
                            below,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (action case final action?)
            Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md), child: action),
        ],
      ),
    );
  }
}

/// 비교 칸(pen `F84Alv` 140×175 · 모서리 24). 좁은 폰에서는 비율을 지키며 줄어든다.
const double _cellWidth = 140;
const double _cellHeight = 175;

/// 실사진 흐림(pen "blur 14"). pen blur 값을 sigma 로 그대로 읽는다(유료 카드 잠금 미리보기와 같은 방식).
const double _photoBlur = 14;

/// 5b 아바타 리빌(pen `F84Alv`, 대장 전달 pen 값 10-17) — 기본 아바타(05-12d)도 같은 화면이다.
/// 바깥 [64,24,32,24] · 세로 간격 24 · 가운데 정렬. 제목 312 폭 두 줄 → 비교 줄 312×199 → 설명 → 바닥 "확인했어요" 312×52.
/// 글이 길어져도 버튼은 바닥에 남고 위쪽만 스크롤한다(작은 화면 · 큰 글씨).
class _AvatarReveal extends ConsumerWidget {
  const _AvatarReveal({required this.avatarUrl, required this.onConfirm});

  /// 서버가 완성해서 준 아바타 주소 그대로다. 앞에 무엇도 붙이지 않는다(버킷을 바꾸면 전부 깨진다).
  final String? avatarUrl;

  /// 다음으로 넘어가는 길. 사람이 리빌을 다 본 뒤에 스스로 누른다.
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 왼쪽은 아바타로 만든 그 사진(결정 G3 추천안 — 같은 사진의 전후). `GET /me/profile` 은 가입 중에도 열린다(인증만 본다).
    final photoUrl = ref.watch(
      myProfileProvider.select((profile) => profile.value?.when(onSuccess: _avatarSourceUrl, onFailure: (_) => null)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: _topGap),
                  // 두 줄 고정(대장 결정 10-17, pen 도 같은 줄바꿈) — 312 폭에 한 줄로 들어가도 이 자리에서 접는다.
                  Text(
                    context.l10n.profileAvatarRevealTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.headline.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // 두 칸 사이 16 — pen 은 312 줄 안 x8 · x164 다(양끝 8 은 가운데 정렬이 남긴 자리).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(child: _LockedPhoto(url: photoUrl)),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(child: _AvatarPreview(url: avatarUrl)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l10n.profileAvatarRevealBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500, height: 1.5, color: AppColors.body),
                  ),
                  // 홈 레일(서버 `/home/people`)이 실제 가입자 아바타를 블러 없이 보여 준다(10-17) — 여기서 미리 알린다(PR #550 개인정보 안내).
                  // 옛 05-12c 에서 옮겼다. pen `F84Alv` 에도 같은 줄이 들어갔다(대장 전달 10-17): 설명 바로 아래 8 · 14/400 #6A6A6A ·
                  // 가운데 · 폭 312 · 줄높이 1.5(312 폭 두 줄 42).
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.profileAvatarRevealHomeNotice,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          AppButton(label: context.l10n.profileAvatarRevealConfirm, onPressed: onConfirm),
        ],
      ),
    );
  }

  static String? _avatarSourceUrl(MyProfile me) => me.photos.where((photo) => photo.isAvatarSource).firstOrNull?.url;
}

/// 비교 칸 하나 + 아래 8 에 라벨(12, 렌더 16 — 줄 199 = 칸 175 + 8 + 16).
class _CompareColumn extends StatelessWidget {
  const _CompareColumn({required this.cell, required this.label, required this.labelStyle});

  final Widget cell;
  final String label;
  final TextStyle labelStyle;

  /// pen 라벨은 lineHeight 속성 없이 렌더 16 으로 본다(caption 토큰 1.4 면 16.8 이라 줄이 199 를 넘는다).
  static final TextStyle labelBase = AppTypography.caption.copyWith(height: 16 / 12);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _cellWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: _cellWidth / _cellHeight, child: cell),
          const SizedBox(height: AppSpacing.xs),
          Text(label, textAlign: TextAlign.center, style: labelStyle),
        ],
      ),
    );
  }
}

/// 왼쪽 "나만 보는 실제 사진" — 흐림 14 + 잠금 덮개(검정 25%) + 가운데 흰 자물쇠 28.
/// 화면 읽기는 칸과 라벨을 한 번에 "나만 보는 실제 사진, 가려져 있어요" 로 읽는다.
class _LockedPhoto extends StatelessWidget {
  const _LockedPhoto({required this.url});

  /// 아바타로 고른 내 사진(서명 주소). 없거나 아직 못 받았으면 null.
  final String? url;

  @override
  Widget build(BuildContext context) {
    final photo = url;
    return Semantics(
      container: true,
      image: true,
      label: context.l10n.profileAvatarRevealLockedSemantics,
      child: ExcludeSemantics(
        child: _CompareColumn(
          label: context.l10n.profileAvatarRevealLockedLabel,
          labelStyle: _CompareColumn.labelBase.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
          cell: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo == null)
                  const _EmptyCell()
                else
                  ImageFiltered(
                    // clamp — 가장자리를 투명하게 바래지 않고 끝 색으로 채운다(모서리 안에 흐린 테두리가 비치지 않게).
                    imageFilter: ImageFilter.blur(sigmaX: _photoBlur, sigmaY: _photoBlur, tileMode: TileMode.clamp),
                    child: Image.network(
                      photo,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) => const _EmptyCell(),
                    ),
                  ),
                // 잠금 덮개 140×175(모서리 24 는 위 ClipRRect 가 자른다) — 검정 25% 로 밝은 사진 위에서도 흰 자물쇠가 보이게
                // (대장 전달 pen 값 10-17 `#000000` 25%). 맞는 색 토큰이 없어 값을 둔다(scrim 은 50%).
                const ColoredBox(color: Color(0x40000000)),
                const Center(child: Icon(AppIcons.lock, size: 28, color: AppColors.onInk)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 오른쪽 "상대에게 보이는 모습" — 흐림 없는 내 아바타, 분홍(primary) 테두리 2.
class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final avatar = url;
    return _CompareColumn(
      label: context.l10n.profileAvatarRevealPreviewLabel,
      labelStyle: _CompareColumn.labelBase.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
      // 테두리는 그림 위에 그린다 — 아래에 깔면 cover 그림이 선을 덮는다.
      cell: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: avatar == null
              ? const _EmptyCell()
              : Image.network(
                  avatar,
                  fit: BoxFit.cover,
                  frameBuilder: _reveal,
                  // 그림만 못 받았다고 빈 화면을 두지 않는다 — 아바타는 서버에 이미 있고, 다음으로도 가야 한다.
                  // 남의 예시 그림을 "내 모습" 자리에 두지 않고 칸만 비워 둔다(대장 2026-09-26 결정 계승).
                  errorBuilder: (context, error, stackTrace) => const _EmptyCell(),
                ),
        ),
      ),
    );
  }

  /// 그림이 도착하면 투명 · 0.96 에서 standard 동안 제자리로(transform · opacity 만 — 칸 140×175 는 처음부터 그대로).
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

/// 그림을 못 받았거나 아직 없는 칸 — 같은 크기 바탕만 둔다.
class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: AppColors.surfaceSoft);
}

/// 05-12d 기본 아바타 안내 시트(pen `Q7VmU` 360 폭, 대장 전달 pen 값 10-17) — 채움 흰색 · 위 모서리 24 · 안쪽 [12,20,28,20] ·
/// 간격 16. 버튼은 "확인" 하나다(pen 의 취소 버튼은 꺼져 있다).
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
      // 좌우 20 은 카드 안쪽 토큰(`AppSpacing.card`)과 같은 값이다. 바닥 28 은 화면 바닥 버튼 여백과 같다(토큰 없음).
      padding: const EdgeInsets.fromLTRB(AppSpacing.card, AppSpacing.sm, AppSpacing.card, 28),
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
              context.l10n.profileAvatarCompensationTitle,
              style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            // 하트 수는 서버가 준 값 그대로다 — 앱에 숫자를 박으면 규칙이 바뀔 때 앱만 거짓말을 한다.
            Text(
              context.l10n.profileAvatarCompensationBody(hearts: hearts),
              style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: context.l10n.commonConfirm, onPressed: onConfirm),
          ],
        ),
      ),
    );
  }
}

/// 05-12b(pen `euW4T` · `c7QuSm`) — 분홍 목도리 마스코트 아래 힌트 한 줄 14/400 muted. 실패 종류가 있으면 같은 자리 · 같은 글꼴로
/// 그 글자를 둔다. 부제 · 버튼 "다시 시도" 는 pen 원문 그대로다(대장 전달 10-15 — "시도해주세요" 붙여 쓰기도 원문).
class _RetryPrompt extends StatelessWidget {
  const _RetryPrompt({required this.state, required this.onRetry});

  final AvatarGenerationUiState state;
  final Future<void> Function() onRetry;

  /// 상태 틀 위에서 마스코트까지(pen 05-12b `euW4T`).
  static const double _mascotTop = 45;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = state.error;
    return _StatusView(
      title: l10n.profileAvatarRetryTitle,
      subtitle: l10n.profileAvatarRetrySubtitle,
      visualTop: _mascotTop,
      visual: Image.asset('assets/images/mascot-female-sad.png', width: 220, height: 220, fit: BoxFit.contain, excludeFromSemantics: true),
      below: Text(
        // 힌트 숫자는 서버 규칙(`MAX_CONSECUTIVE_FAILURES` 5 — 연속 실패 5번까지 무료, 5번째에 기본 아바타 + 하트)과 같다.
        // 종전 pen 원문 "3번까지" 는 서버와 달라 사용자 결정(10-15 "추천")으로 고쳤다(pen 도 함께 정정).
        error == null ? l10n.profileAvatarRetryFreeHint : context.errorText(error),
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
      action: AppButton(label: l10n.commonRetry, onPressed: onRetry),
    );
  }
}
