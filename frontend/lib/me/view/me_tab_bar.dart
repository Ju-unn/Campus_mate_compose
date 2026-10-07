import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 밑줄 탭 바(pen `p9s0G` Tab Bar, 15-4 `O9ZIzO` · 15-4b `g1rDs`) — 알약 세그먼트가 아니라 TabBar 모양이다(사용자 지시).
/// 360×44, 흰 바탕, 아래 선 1px #EBEBEB. 탭은 같은 폭으로 나눠 갖고 높이는 44(기존 Tab `H2Qyx`: 위 12 · 밑줄이 맨 아래).
/// 고른 탭은 글자 #C4224B 14/700 + 밑줄 2px #C4224B, 안 고른 탭은 글자 #6A6A6A 14/500 + 밑줄 투명.
/// 탭 전환 움직임은 pen 에 없다 — 바로 바뀐다. 나 탭 밖에서도 쓸 수 있게 라벨 목록을 받는다.
class MeTabBar extends StatelessWidget {
  const MeTabBar({required this.labels, required this.selected, required this.onSelected, super.key});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  /// pen 바 높이 44.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      // 높이 44 는 최소값이다 — 글자를 키우면 탭 바가 같이 늘어난다(DESIGN §11.2).
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: IntrinsicHeight(
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
              // 위 12(pen padding-top) 에서 글자 시작, 아래는 밑줄 2 + 숨 쉬는 자리 8.
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
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
              // 밑줄은 바 맨 아래(pen `h1Uby`).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 2, color: selected ? AppColors.primaryText : Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
