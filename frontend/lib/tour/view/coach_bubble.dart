import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// "다음" 버튼(pen `gfoSM` Button 104×48). 글자를 키우면 같은 비율로 넓힌다 — 고정 폭이면 "시작하기" 가 두 줄로 내려가 높이 48 에 잘린다.
const double _nextWidth = 104;

/// 버튼 줄 높이(pen Footer 48) = "다음" · "건너뛰기" 높이.
const double _footerHeight = 48;

/// "건너뛰기"(pen TextButton 76×48, 글자 왼쪽 여백 12).
const double _skipWidth = 76;
const double _skipInset = 12;

/// 앱 투어 말풍선(pen `gfoSM` CoachBubble — 폭 312 · 모서리 16 · 흰 바탕). 폭은 부모가 정한다.
/// 안쪽 여백 위 16 · 좌우 16 · 아래 12, 위에서부터 단계 "n / 총"(12/600 muted) → 제목 16/700 → 설명 14/400 ink → [detail] →
/// 버튼 줄(높이 48: 왼쪽 끝 "건너뛰기", 오른쪽 끝 "다음"), 사이는 모두 8(pen 값, campus-pen 확인).
/// 마지막 장은 "다음" 이 "시작하기" 가 되고 "건너뛰기" 는 안 보이고 눌리지도 않지만 자리는 남는다 — 버튼 줄이 흔들리지 않는다.
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    required this.number,
    required this.total,
    required this.title,
    required this.body,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
    this.detail,
    super.key,
  });

  /// "건너뛰기" 칸(76×48). 시험이 자리 · 크기를 잰다.
  static const Key skipKey = ValueKey('coach-bubble-skip');

  final int number;
  final int total;
  final String title;
  final String body;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      // 단계 · 제목 · 설명 · 버튼이 각자 읽힌다(한 덩어리로 합치면 버튼 두 개가 하나로 읽힌다).
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xs,
            children: [
              Semantics(
                label: '$total단계 중 $number단계',
                excludeSemantics: true,
                child: Text(
                  '$number / $total',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
              ),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(title, style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              Text(body, style: AppTypography.bodySmall.copyWith(color: AppColors.ink)),
              ?detail,
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 왼쪽 끝 건너뛰기 · 오른쪽 끝 다음. 글자를 키워 둘이 모자라면 "다음" 이 남은 폭까지만 넓어진다.
  Widget _footer(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Visibility(
          visible: !isLast,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _SkipButton(key: skipKey, onPressed: onSkip),
        ),
        Flexible(
          child: SizedBox(
            width: MediaQuery.textScalerOf(context).scale(_nextWidth),
            child: AppButton(label: isLast ? '시작하기' : '다음', height: _footerHeight, onPressed: onNext),
          ),
        ),
      ],
    );
  }
}

/// "건너뛰기" 글자 버튼(pen TextButton 76×48, 글자 왼쪽 12). 글자 모양은 관문 화면의 조용한 글자 버튼(`MutedTextButton`, 14/600 muted)과 같다 —
/// 그 공용 위젯은 글자를 가운데 두고 폭을 못 정해 여기서 그린다. 크기는 최소값이라 글자를 키우면 넓어진다.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 말풍선 Material 위에 투명 Material 을 둬 눌림 효과가 이 칸 안에 그려진다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _skipWidth, minHeight: _footerHeight),
            child: Padding(
              padding: const EdgeInsets.only(left: _skipInset),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  '건너뛰기',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
