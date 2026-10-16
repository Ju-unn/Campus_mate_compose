import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
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

/// 09b 6칸 그리드 v2 — pen 화면 인스턴스 `blOdR`(ref HomeTileGrid v2 `R62HQ`, 10-16 초안 A 사용자 채택).
/// 3열 × 2행 · 통계 행 112 · 링크 행 80 · 칸 사이 · 행 사이 8 · 328×200(앱은 화면 폭에 맞춘다).
/// 감싸는 바탕 · 여백은 없고 칸마다 흰 바탕을 칠한다 — 통계 칸 `BeClX` 낮은 그림자, 링크 칸 `F4rC8g` 테두리 + 조금 더 뜬 그림자,
/// 곧 열려요 칸 `BoTMl` 옅은 테두리 + 안쪽 그림자(눌리지 않는 칸이라 들어가 보이게).
/// 위 행은 통계(누르지 않음) — 임계값 미만 칸은 숨기고 남은 칸이 폭을 나누며, 셋 다 숨으면 위 행만 빠진다.
/// 아래 행은 인스타그램 · 이벤트 · 곧 열려요. 요약이 없으면(조회 중 · 실패) 홈 화면이 이 그리드를 통째로 숨긴다.
class HomeGrid extends StatelessWidget {
  const HomeGrid({required this.summary, required this.onInstagram, required this.onEvent, super.key});

  final HomeSummary summary;
  final VoidCallback onInstagram;
  final VoidCallback onEvent;

  @override
  Widget build(BuildContext context) {
    final stats = [
      if (summary.deliveredCards >= _minStatValue)
        StatTile(icon: AppIcon3d.send, value: _thousands(summary.deliveredCards), label: '전달된 카드'),
      if (summary.signups >= _minStatValue)
        StatTile(icon: AppIcon3d.join, value: _thousands(summary.signups), label: '가입 수'),
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
            art: const Icon3d(AppIcon3d.gift, size: 28),
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

/// 아래 행 칸 최소 높이(pen `blOdR` 링크 · 곧 열려요 행 80) — 글자를 키우면 늘어난다.
const double _linkRowMinHeight = 80;

/// 그림 원과 라벨 사이(pen `F4rC8g` · `BoTMl` gap 6)
const double _plateLabelGap = 6;

/// 링크 칸(인스타 · 이벤트) — pen 링크 칸 마스터 `F4rC8g`(이름 대응: HomeLinkTile). 칸 전체가 누름 칸이고 잉크는 칸 자기 Material 에
/// 그린다 — 홈 목록 안에서 움직이므로(COMMON 4-2). canvas · 안쪽 hairline 1 테두리 · 모서리 14 · 바깥 그림자 [AppElevation.homeTileRaised].
/// 그림 원 40 → 6 → 라벨 12/600 ink lh1.4 를 세로 가운데, 오른쪽 위(위 6 · 오른쪽 6)에 화살표 칩.
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
      // 그림자는 Material 밖 상자가 그린다 — Material elevation 그림자는 pen 값과 다르다.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppElevation.homeTileRaised,
        ),
        child: Material(
          color: AppColors.canvas,
          // BorderSide 는 기본이 안쪽 선이다 — 칸 크기 그대로 테두리를 그린다.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _linkRowMinHeight),
              // 글 칸은 위치를 주지 않는 자식이라야 줄 높이(IntrinsicHeight)에 들어간다 — 글자를 키우면 칸이 늘어난다.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _PlateAndLabel(
                    plate: art,
                    label: Text(
                      label,
                      softWrap: false,
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink),
                    ),
                  ),
                  const Positioned(top: 6, right: 6, child: _ArrowChip()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 링크 칸 오른쪽 위 "다른 곳으로" 칩 — 20 원 primaryWash 안에 arrow-up-right 12 primaryText(pen `F4rC8g`).
class _ArrowChip extends StatelessWidget {
  const _ArrowChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
      child: const Icon(AppIcons.arrowUpRight, size: 12, color: AppColors.primaryText),
    );
  }
}

/// 아래 행 세 칸이 같이 쓰는 속: 그림 원 40 → 6 → 라벨, 좌우 4. 한 낱말 라벨이라 줄을 바꿀 곳이 없다 —
/// 글자를 키워 칸보다 넓어지면 자르지 않고 줄인다.
class _PlateAndLabel extends StatelessWidget {
  const _PlateAndLabel({required this.plate, required this.label});

  final Widget plate;
  final Text label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconPlate(child: plate),
          const SizedBox(height: _plateLabelGap),
          FittedBox(fit: BoxFit.scaleDown, child: label),
        ],
      ),
    );
  }
}

/// 곧 열려요 칸 — pen 마스터 `BoTMl`(이름 대응: HomeSoonTile). 누르지 않는다.
/// canvas · hairlineSoft 1 테두리 · 모서리 14 · **안쪽** 그림자 [AppElevation.homeTileInset] · 바깥 그림자 없음.
/// 그림 원 40(hourglass 20 muted) → 6 → "곧 열려요" 12/600 muted 를 세로 가운데.
class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile();

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(AppRadius.md);
    return Semantics(
      label: '곧 열려요(준비 중)',
      excludeSemantics: true,
      // 칠하는 순서는 채움 → 안쪽 그림자 → 테두리(pen 과 같다) — 그래서 테두리는 foregroundDecoration 이다.
      child: Container(
        constraints: const BoxConstraints(minHeight: _linkRowMinHeight),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: corner),
        foregroundDecoration: BoxDecoration(border: Border.all(color: AppColors.hairlineSoft), borderRadius: corner),
        child: CustomPaint(
          painter: const _InsetShadowPainter(shadow: AppElevation.homeTileInset, radius: AppRadius.md),
          child: Center(
            child: _PlateAndLabel(
              plate: const Icon(AppIcons.hourglass, size: 20, color: AppColors.muted),
              label: Text(
                '곧 열려요',
                softWrap: false,
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 모서리 둥근 칸 안쪽 그림자. Flutter `BoxShadow` 는 모양 바깥에만 그리므로(inset 없음), 칸 모양을 그림자 offset 만큼 옮겨
/// 구멍을 낸 큰 틀을 같은 blur 로 칠하고 칸 모양으로 자른다 — CSS `box-shadow: inset` 과 같은 그림이 나온다(새 의존성 없음).
class _InsetShadowPainter extends CustomPainter {
  const _InsetShadowPainter({required this.shadow, required this.radius});

  final BoxShadow shadow;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final face = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    // 틀 바깥 끝이 흐림(약 3σ)에 들어오지 않게 넉넉히 키운다.
    final frame = (Offset.zero & size).inflate(shadow.blurSigma * 3 + shadow.offset.distance);
    canvas
      ..clipRRect(face)
      ..drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(frame)
          ..addRRect(face.shift(shadow.offset).deflate(shadow.spreadRadius)),
        shadow.toPaint(),
      );
  }

  @override
  bool shouldRepaint(_InsetShadowPainter oldDelegate) => oldDelegate.shadow != shadow || oldDelegate.radius != radius;
}
