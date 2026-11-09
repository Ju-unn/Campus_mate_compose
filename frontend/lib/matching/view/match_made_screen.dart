import 'dart:math' as math;

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 매칭 성사(DESIGN.md 화면 12, pen `UFNSi` → 성사 연출 판 `jqqaz`).
/// "대화 시작하기" 는 이제 그 방으로 바로 들어간다(조각 5).
/// 들어올 때 성사 연출(Lottie 300×250, 옛 마스코트 자리)이 0.92 → 1 로 커지며 나타나고(emphasis 420ms, 커브는 크기에만),
/// 120ms 뒤 제목 · 부제가 아래 12 에서 올라온다(standard) — DESIGN §7 의 하루 두 번 emphasis 중 하나.
/// 버튼은 움직이지 않아 처음부터 누를 수 있다. 연출은 "동작 줄이기" 면 마지막 장면에 멈춘다.
class MatchMadeScreen extends StatelessWidget {
  const MatchMadeScreen({required this.nickname, this.matchId, super.key});

  final String nickname;

  /// 방 id. 없으면 목록으로 보낸다 — 어느 방인지 모른 채로 방을 열 수는 없다.
  final String? matchId;

  /// 성사 연출 뒤 글이 나오는 간격(대장 지시 — 모션 기회 1, pen 에 없는 값)
  static const Duration _textDelay = Duration(milliseconds: 120);

  /// 화면 아래 여백 — 내용은 이 여백을 뺀 나머지 안에서 가운데다. 제목 32/700(display)일 때 360×780 에서 연출 위가
  /// pen `jqqaz` 의 y115 가 되는 값으로 역산했다(780 - 115 × 2 - 내용 532 = 18).
  static const double _bottomPadding = 18;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          // 작은 화면 · 큰 글씨에서 넘치지 않게 스크롤로 닿는다. 넘치지 않으면 가운데 그대로다.
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, _bottomPadding),
                child: _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Entrance(
          scaleFrom: 0.92,
          duration: AppMotion.emphasis,
          curve: AppMotion.emphasisCurve,
          child: const _CelebrationScene(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Entrance(
          rise: 12,
          delay: _textDelay,
          child: Column(
            children: [
              // pen 원본 12 `UFNSi` 의 `T5kQ4x` 도 32/700 — 토큰 display(매칭 성사 화면 용도).
              Text(context.l10n.matchingMatchMadeTitle, style: AppTypography.display.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.matchingMatchMadeBody(nickname: nickname),
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        AppButton(
          label: context.l10n.matchingMatchMadeStartChat,
          onPressed: () => context.go(
            matchId == null ? AppRoutes.conversations : '${AppRoutes.chatRoom}/$matchId',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: context.l10n.matchingMatchMadeLater,
          variant: AppButtonVariant.text,
          onPressed: () => context.go(AppRoutes.today),
        ),
      ],
    );
  }
}

/// 성사 연출 300×250(pen `jqqaz`). 쓸 수 있는 폭(좌우 16 뺀 값)이 300 보다 좁으면 비율 그대로 줄인다
/// (CLAUDE.md 규칙 3 — 최대는 pen 크기).
class _CelebrationScene extends StatelessWidget {
  const _CelebrationScene();

  static const double _width = 300;
  static const double _height = 250;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(_width, constraints.maxWidth);
        return AppLottieView(scene: AppLottie.matchCelebration, width: width, height: _height * width / _width);
      },
    );
  }
}
