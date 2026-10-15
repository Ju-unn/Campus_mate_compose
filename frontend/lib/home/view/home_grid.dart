import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:flutter/material.dart';

/// 통계 칸 하나를 보이는 최소값(DESIGN §8.9 규칙 4 — 임계값 미만 칸은 숨긴다). 값은 §13 미결 9(베타 데이터를 보고 정함)라
/// 지금은 "0 이면 숨김" 만 한다.
const int _minStatValue = 1;

/// 09b 6칸 그리드(pen `M5hpo7` `bRRhx`, 대장 전달 확정 값 10-15): 3열 × 2행 · 칸 104×96 · 간격 8 · 328×200.
/// 감싸는 바탕 · 여백은 없고 칸마다 바탕을 칠한다(통계 · 링크 칸 primaryWash, 곧 열려요 칸은 테두리만).
/// 위 행은 통계(누르지 않음) — 임계값 미만 칸은 숨기고 남은 칸이 폭을 나누며, 셋 다 숨으면 위 행만 빠진다.
/// 아래 행은 인스타그램 · 이벤트 · 자리표시. 요약이 없으면(조회 중 · 실패) 홈 화면이 이 그리드를 통째로 숨긴다.
class HomeGrid extends StatelessWidget {
  const HomeGrid({required this.summary, required this.onInstagram, required this.onEvent, super.key});

  final HomeSummary summary;
  final VoidCallback onInstagram;
  final VoidCallback onEvent;

  @override
  Widget build(BuildContext context) {
    final stats = [
      if (summary.deliveredCards >= _minStatValue)
        // 그림만 1.25 배(pen 값, 옛 `krua8` 과 같다) — 그림 칸 40 은 그대로다.
        StatTile(icon: AppIcon3d.send, iconScale: 1.25, value: _thousands(summary.deliveredCards), label: '전달된 카드'),
      if (summary.signups >= _minStatValue)
        StatTile(icon: AppIcon3d.join, iconScale: 1.16, value: _thousands(summary.signups), label: '가입 수'),
      if (summary.conversationsStarted >= _minStatValue)
        StatTile(icon: AppIcon3d.chat, value: _thousands(summary.conversationsStarted), label: '시작된 대화'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats.isNotEmpty) ...[_row(stats), const SizedBox(height: AppSpacing.xs)],
        _row([
          _LinkTile(
            art: Image.asset('assets/images/brand-instagram-v1.webp', width: 28, height: 28, fit: BoxFit.contain),
            label: '인스타그램',
            semanticLabel: 'CampusMate 인스타그램 열기',
            onTap: onInstagram,
          ),
          _LinkTile(
            // 선물 에셋은 둘레 여백이 있어 로고 28 과 같은 크기로 보이게 36 으로 둔다(pen).
            art: const Icon3d(AppIcon3d.gift, size: 36),
            label: '이벤트',
            semanticLabel: '이벤트 보기',
            onTap: onEvent,
          ),
          const _ComingSoonTile(),
        ]),
      ],
    );
  }

  /// 칸이 같은 폭을 나눠 갖는 한 줄. 글자를 키워 한 칸이 늘어나면 줄 높이를 같이 맞춘다.
  static Widget _row(List<Widget> tiles) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, tile) in tiles.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.xs),
            Expanded(child: tile),
          ],
        ],
      ),
    );
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// 링크 칸(인스타 · 이벤트). 칸 전체가 누름 칸이고 잉크는 칸 자기 Material 에 그린다 — 홈 목록 안에서 움직이므로(COMMON 4-2).
/// pen `cStz1`: primaryWash · 안쪽 hairline 1 테두리 · 모서리 14. 그림 칸 40 → 6 → 라벨 12/600 ink lh1.4 를 세로 가운데,
/// 오른쪽 위 (82, 8) 에 arrow-up-right 14 muted.
class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.art, required this.label, required this.semanticLabel, required this.onTap});

  final Widget art;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.primaryWash,
        // BorderSide 는 기본이 안쪽 선이다 — 칸 크기 104×96 그대로 테두리를 그린다.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            // 글 칸은 위치를 주지 않는 자식이라야 줄 높이(IntrinsicHeight)에 들어간다 — 글자를 키우면 칸이 늘어난다.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconPlate(child: art),
                      const SizedBox(height: 6),
                      // 한 낱말 라벨이라 줄을 바꿀 곳이 없다 — 글자를 키워 칸보다 넓어지면 자르지 않고 줄인다.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          softWrap: false,
                          style: AppTypography.caption
                              .copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  top: 8,
                  right: 8, // 칸 104 에서 x82(= 104 − 8 − 14)
                  child: Icon(AppIcons.arrowUpRight, size: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 자리표시 칸(pen `UlVom`) — 바탕 없음 + 안쪽 hairline 1 테두리, "곧 열려요" 12/600 muted. 누르지 않는다.
class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '곧 열려요(준비 중)',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          '곧 열려요',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
        ),
      ),
    );
  }
}
