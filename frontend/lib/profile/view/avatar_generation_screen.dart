import 'dart:ui' show ImageFilter, TileMode;

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
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

/// 05-12 · 05-12b 공통 얼개(대장 전달 pen 값 10-15 · 10-17). 바깥 [0,16,28,16] · 위 64 → 제목 24/700 → 8 → 부제 16/400 body lh1.6
/// → 32 → 상태 틀(위 45 · 안 간격 12: 마스코트 220 → [below]) → 바닥 [action](05-12b 만). 부제가 328 폭에서 두 줄이면 마스코트가
/// y233 이다(64 + 32.4 + 8 + 51.2 + 32 + 45 ≈ 233 — 대장 값에서 계산한 자리) — 글자를 키우거나 좁은 폰이면 그만큼 내려간다.
/// 글이 길어져도 버튼은 바닥에 남고 위쪽만 스크롤한다. 한 화면 마스코트 한 마리.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
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
                    '짜잔, 매칭 전에는\n이렇게 보여요',
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
                    '매칭 전에는 AI가 그려준 아바타만 보여요. 상호 수락 후 신뢰 확인을 마치면 실제 사진이 공개돼요.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500, height: 1.5, color: AppColors.body),
                  ),
                  // 홈 레일(서버 `/home/people`)이 실제 가입자 아바타를 블러 없이 보여 준다(10-17) — 여기서 미리 알린다(PR #550 개인정보 안내).
                  // 옛 05-12c 에서 옮겼다. pen `F84Alv` 에도 같은 줄이 들어갔다(대장 전달 10-17): 설명 바로 아래 8 · 14/400 #6A6A6A ·
                  // 가운데 · 폭 312 · 줄높이 1.5(312 폭 두 줄 42).
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '내 아바타가 홈 화면에서 다른 회원에게 보일 수 있어요',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          AppButton(label: '확인했어요', onPressed: onConfirm),
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
      label: '나만 보는 실제 사진, 가려져 있어요',
      child: ExcludeSemantics(
        child: _CompareColumn(
          label: '나만 보는 실제 사진',
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
      label: '상대에게 보이는 모습',
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
              '기본 아바타로 대신했어요',
              style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            // 하트 수는 서버가 준 값 그대로다 — 앱에 숫자를 박으면 규칙이 바뀔 때 앱만 거짓말을 한다.
            Text(
              '서버 오류로 하트 $hearts개 드렸어요. 설정 > 아바타 재생성 에서 다시 만들 수 있어요.',
              style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: '확인', onPressed: onConfirm),
          ],
        ),
      ),
    );
  }
}

/// 05-12b(pen `euW4T` · `c7QuSm`) — 분홍 목도리 마스코트 아래 힌트 한 줄 13/400 muted. 서버 문구가 있으면 같은 자리 · 같은 글꼴로
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
