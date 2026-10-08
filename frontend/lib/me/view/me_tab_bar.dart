import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 밑줄 탭 바(pen `p9s0G` Tab Bar, 15-4 `O9ZIzO` · 15-4b `g1rDs`) — 알약 세그먼트가 아니라 TabBar 모양이다(사용자 지시).
/// 보이는 모양은 360×44, 흰 바탕, 아래 선 1px #EBEBEB. 탭은 같은 폭으로 나눠 갖는다(기존 Tab `H2Qyx`: 위 12 · 밑줄이 맨 아래).
/// 고른 탭은 글자 #C4224B 14/700 + 밑줄 2px #C4224B, 안 고른 탭은 글자 #6A6A6A 14/500 + 밑줄 투명.
/// 탭 전환 움직임은 pen 에 없다 — 바로 바뀐다. 나 탭 밖에서도 쓸 수 있게 라벨 목록을 받는다.
///
/// 누르는 칸은 48 이다(보이는 44 + 아래 4). 보이는 모양은 pen 그대로이고, 모자란 4 는 아래 선 밑으로 투명하게 늘렸다 — 부르는 쪽이
/// 본문 위 여백을 [extraHitHeight] 만큼 줄여 화면의 보이는 자리는 그대로 둔다(faq_screen.dart `_Tabs` 와 같은 방식).
class MeTabBar extends StatelessWidget {
  const MeTabBar({required this.labels, required this.selected, required this.onSelected, super.key});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  /// pen 바 높이 44(보이는 줄).
  static const double height = 44;

  /// 누르는 칸에만 더한 높이 — 누르는 칸 = [height] + 이 값 = 48.
  static const double extraHitHeight = 4;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      // 높이 48(누르는 칸)은 최소값이다 — 글자를 키우면 탭 바가 같이 늘어난다(DESIGN §11.2).
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height + extraHitHeight),
        child: Stack(
          // 최소 높이 48 을 안쪽 탭까지 그대로 넘긴다 — 안 그러면 탭이 글자 높이(43)로 줄어 누르는 칸이 48 이 안 된다.
          fit: StackFit.passthrough,
          children: [
            // 아래 선 1px #EBEBEB 은 보이는 줄(44)의 맨 아래 — 누르는 칸의 투명한 4 위에 놓는다.
            const Positioned(
              left: 0,
              right: 0,
              bottom: extraHitHeight,
              child: SizedBox(height: 1, child: ColoredBox(color: AppColors.hairlineSoft)),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, label) in labels.indexed)
                    Expanded(
                      child: _Tab(label: label, selected: index == selected, onTap: () => onSelected(index)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryText : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      // 눌림 효과가 이 칸 안에 그려지게 자기 Material 을 둔다(COMMON §4-2).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // 위 12(pen padding-top) 에서 글자 시작.
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
                child: Center(
                  heightFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
              // 밑줄 2px 은 보이는 줄(44)의 맨 아래(pen `h1Uby`) — 누르는 칸 아래 4 위.
              Positioned(
                left: 0,
                right: 0,
                bottom: MeTabBar.extraHitHeight,
                child: Container(height: 2, color: selected ? AppColors.primaryText : Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
