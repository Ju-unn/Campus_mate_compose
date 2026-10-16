import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 그림 자리(40) — 링크 칸의 [IconPlate] 와 같은 높이라 숫자 · 라벨 자리가 그대로다.
const double _artSlot = 40;

/// 6칸 그리드 위 행 통계 한 칸(pen 09b `M5hpo7` `gyzyR`, 대장 전달 확정 값 10-15). 누르지 않는다.
/// 104×96 · 모서리 14 · primaryWash 한 색 · 테두리 없음. 세로로 그림 자리 40 → 숫자 24/700 ink(33) → 라벨 12/600 muted(17) = 90, 간격 0, 세로 가운데.
/// 통합 시험(area2 E-HOME-02)이 [label] · [value] 를 그대로 읽는다 — 이름을 바꾸지 않는다.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.iconScale = 1,
    super.key,
  });

  final AppIcon3d icon;
  final String value;
  final String label;

  /// 그림 칸 크기는 그대로 두고 그림만 키우는 배율(가입 수 join 1.16 — 옛 `krua8` 값 재사용).
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    // 96 은 최소 높이다 — 글자를 키우면 늘어나고, 라벨은 줄을 바꾼다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 흰 원(IconPlate) 없이 그림만, 자리 40 은 그대로 둬 숫자 · 라벨 위치가 같다(대장 10-16 — pen 반영 대기).
          // 기본 32 × 배율이라 보이는 그림이 40 자리를 넘지 않는다(보낸 카드 40 · 가입 37 · 대화 32, 대장 결정 10-16).
          SizedBox(
            width: _artSlot,
            height: _artSlot,
            child: Center(child: Transform.scale(scale: iconScale, child: Icon3d(icon, size: 32))),
          ),
          // 숫자가 길어져도 줄을 바꾸지 않고 칸 안에서 줄인다. softWrap 을 꺼야 IntrinsicHeight 가 두 줄로 세지 않는다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              softWrap: false,
              // pen 글자 상자 33(대장 값) — headline 토큰 줄높이 1.35(32.4)와 달라 맞춘다.
              style: AppTypography.headline.copyWith(height: 33 / 24, color: AppColors.ink),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 17 / 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 6칸 그리드 링크 칸(인스타 · 이벤트)의 그림 칸: 40 원 · 흰 채움 · 안쪽 테두리 1 hairlineSoft · 그림자 없음. 통계 칸은 10-16 에 이 원을 뺐다.
/// 그림이 칸보다 커도(이벤트 선물 36 은 둘레 여백 때문에 크게 둔다) 칸 크기는 40 그대로다.
class IconPlate extends StatelessWidget {
  const IconPlate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: child,
    );
  }
}
