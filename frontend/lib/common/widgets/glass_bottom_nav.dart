import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart' show AppTab;
import 'package:campus_mate/core/haptics/haptics_gateway.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// pen 값 중 토큰표에 없는 것(구역 `MX4jk`, 마스터 `AppBottomNavGlass` `xtj0K`, 사용자 승인 2026-10-13).
/// 알약 채움 #FFFFFF C7 — 알파 78%(마스터 context "알파 최소 78%").
const _pillFill = Color(0xC7FFFFFF);

/// 알약 안쪽 1px 선 #FFFFFF99.
const _pillStroke = Color(0x99FFFFFF);

/// 알약 그림자 (0,8) blur 24 #1A16191F.
const _pillShadow = BoxShadow(color: Color(0x1F1A1619), offset: Offset(0, 8), blurRadius: 24);

/// 알약 background_blur 반지름 20 — 시그마 20 으로 옮긴다(대장 지시).
const double _pillBlurSigma = 20;

/// 알약 최소 높이 66 = 위아래 안쪽 4 + 탭 칸 58. 글자를 키우면 늘어난다(DESIGN §11.2).
const double _pillMinHeight = 66;
const double _cellMinHeight = _pillMinHeight - 2 * AppSpacing.xxs;

/// 아이콘 ↔ 라벨 2(탭 칸 gap).
const double _iconLabelGap = 2;

/// 선택 방울(`ANnU7` · `e5De2` · `bTYXh` · `xWvRT` · `g6Wcb`): 채움 #FFFFFF99, 위쪽만 1px #FFFFFFE6, 모서리 27.
const _bubbleFill = Color(0x99FFFFFF);
const _bubbleTopStroke = Color(0xE6FFFFFF);
const double _bubbleRadius = 27;

/// 방울 그림자 (0,5) blur 12 #1A161933.
const _bubbleShadow = BoxShadow(color: Color(0x331A1619), offset: Offset(0, 5), blurRadius: 12);

/// 방울은 탭 칸보다 좌우 6 씩 넓고(76 = 64 + 12) 알약 위아래에서 6 씩 들어온다(y 6, 높이 54).
const double _bubbleOverhang = 6;
const double _bubbleInset = 6;

/// 떠 있는 유리 알약 하단 내비 — 5개 탭 화면(메인 · 오늘 · 커뮤니티 · 대화 · 나)에서만 쓴다.
/// 상세 화면(10b 카드 상세)은 [AppBottomNav] 를 그대로 쓴다(상세 화면 내비는 별도 결정).
///
/// 부르는 Scaffold 는 `extendBody: true` 로 둔다 — 본문이 알약 뒤로 이어지고, 이 위젯의 높이
/// (알약 + 띄움 12 + safe area)를 Scaffold 가 본문 `MediaQuery.padding.bottom` 으로 넘긴다. 스크롤 목록은 그 값을
/// 아래 여백에 더해 마지막 항목이 알약에 가리지 않게 한다.
///
/// 탭을 눌러 **다른 탭으로 바뀔 때만** 진동 한 번(같은 탭은 없음). 탭마다 화면이 따로라 내비도 새로 만들어지므로,
/// 앞 탭을 넘겨받아 새 화면의 방울이 그 자리에서 미끄러져 온다. 모션 줄이기가 켜져 있으면 처음부터 제자리.
class GlassBottomNav extends ConsumerStatefulWidget {
  const GlassBottomNav({required this.current, super.key});

  final AppTab current;

  @override
  ConsumerState<GlassBottomNav> createState() => _GlassBottomNavState();
}

/// 탭 목록·아이콘·라벨·경로는 [AppBottomNav] 와 같다(DESIGN §8.8).
const _items = <(AppTab, IconData, String, String)>[
  (AppTab.main, AppIcons.house, '메인', AppRoutes.home),
  (AppTab.today, AppIcons.heart, '오늘', AppRoutes.today),
  (AppTab.community, AppIcons.users, '커뮤니티', AppRoutes.community),
  (AppTab.chat, AppIcons.messageCircle, '대화', AppRoutes.conversations),
  (AppTab.me, AppIcons.userRound, '나', AppRoutes.myProfile),
];

class _GlassBottomNavState extends ConsumerState<GlassBottomNav> {
  /// 방울이 출발하는 탭. 탭을 눌러 들어왔으면 앞 탭, 아니면 지금 탭(움직이지 않는다).
  late final AppTab _origin;

  @override
  void initState() {
    super.initState();
    _origin = ref.read(_bubbleHandoffProvider).take(widget.current) ?? widget.current;
  }

  void _select(AppTab tab, String route) {
    if (tab != widget.current) {
      unawaited(ref.read(hapticsGatewayProvider).selectionClick());
      ref.read(_bubbleHandoffProvider).hand(from: widget.current, to: tab);
    }
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(chatBadgeCountProvider);
    final instant = MediaQuery.disableAnimationsOf(context);
    // 블러는 뒤 본문이 움직일 때마다 다시 계산되지만, 알약 그림 자체는 이 경계 안에서 다시 그리지 않는다.
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth - 2 * AppSpacing.xxs) / _items.length;
              final bubbleWidth = cellWidth + 2 * _bubbleOverhang;
              // 메인 · 나 칸의 방울은 알약 밖으로 2 나가던 것을 안으로 당긴다(사용자 결정 10-13: 메인 x0 · 나 x252).
              double bubbleLeft(AppTab tab) => (AppSpacing.xxs + tab.index * cellWidth - _bubbleOverhang)
                  .clamp(0, constraints.maxWidth - bubbleWidth)
                  .toDouble();
              final target = bubbleLeft(widget.current);
              return CustomPaint(
                painter: const _OuterShadowPainter(_pillShadow, AppRadius.pill),
                child: Stack(
                  children: [
                    const Positioned.fill(child: _GlassFill()),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: instant ? target : bubbleLeft(_origin), end: target),
                      duration: instant ? Duration.zero : AppMotion.press,
                      curve: AppMotion.pressCurve,
                      builder: (context, left, child) => Positioned(
                        left: left,
                        top: _bubbleInset,
                        bottom: _bubbleInset,
                        width: bubbleWidth,
                        child: child!,
                      ),
                      child: const _Bubble(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Row(
                        children: [
                          for (final (tab, icon, label, route) in _items)
                            Expanded(
                              child: _GlassTab(
                                icon: icon,
                                label: label,
                                isSelected: tab == widget.current,
                                badge: tab == AppTab.chat ? badge : 0,
                                onTap: () => _select(tab, route),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 다음 탭 화면의 내비에게 "어느 탭에서 눌러 왔는지" 를 한 번 넘긴다. 받을 탭이 맞을 때만 쓰고 바로 비운다.
class _BubbleHandoff {
  ({AppTab from, AppTab to})? _pending;

  void hand({required AppTab from, required AppTab to}) => _pending = (from: from, to: to);

  AppTab? take(AppTab current) {
    final pending = _pending;
    _pending = null;
    return pending?.to == current ? pending!.from : null;
  }
}

final _bubbleHandoffProvider = Provider<_BubbleHandoff>((ref) => _BubbleHandoff());

/// 알약 모양으로 자른 배경 블러 + 반투명 채움 + 안쪽 1px 선. 선은 자식을 밀지 않게 DecoratedBox 테두리로 둔다.
class _GlassFill extends StatelessWidget {
  const _GlassFill();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _pillBlurSigma, sigmaY: _pillBlurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _pillFill,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: _pillStroke),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _OuterShadowPainter(_bubbleShadow, _bubbleRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _bubbleFill,
          borderRadius: BorderRadius.circular(_bubbleRadius),
          border: const Border(top: BorderSide(color: _bubbleTopStroke)),
        ),
      ),
    );
  }
}

/// [shadow] 를 둥근 모양 **바깥에만** 그린다. `BoxDecoration.boxShadow` 는 모양 아래에도 칠해 반투명 채움
/// (알약 78% · 방울 60%) 사이로 비쳐 회색이 된다 — pen 렌더는 알약 · 방울 안쪽이 하얗다(`eemnX` 캡처).
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter(this.shadow, this.radius);

  final BoxShadow shadow;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(math.min(radius, size.shortestSide / 2)));
    final reach = 2 * shadow.blurRadius + shadow.offset.distance;
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shape.outerRect.inflate(reach))
          ..addRRect(shape),
      )
      ..drawRRect(shape.shift(shadow.offset), shadow.toPaint())
      ..restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) => oldDelegate.shadow != shadow || oldDelegate.radius != radius;
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final int badge;
  final VoidCallback onTap;

  /// pen 라벨(`G2LX51` 등) 11/600 — lineHeight · letterSpacing 속성 없음, 렌더 높이 16. badge 토큰(1.3 · 0.02em)과 달라 맞춘다.
  static final _labelStyle = AppTypography.badge.copyWith(height: 16 / 11, letterSpacing: 0);

  @override
  Widget build(BuildContext context) {
    // 비활성 body(사용자 승인), 활성 아이콘은 primary 채움색(현행 유지), 활성 라벨은 흰 바탕 글자용 primary-text.
    final iconColor = isSelected ? AppColors.primary : AppColors.body;
    final labelColor = isSelected ? AppColors.primaryText : AppColors.body;
    // 아이콘·글자·숫자를 한 덩어리로 읽는다 — 토크백이 "대화", "3" 을 따로 읽으면 뜻이 흩어진다(AppBottomNav 와 같다).
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        // 눌림 효과가 화면 Material 이 아니라 이 칸 위에 그려지게(COMMON §4-2). 칸 모양은 pen 탭 모서리 9999.
        child: Material(
          type: MaterialType.transparency,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _cellMinHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: iconColor),
                  const SizedBox(height: _iconLabelGap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 글자를 키우면(DESIGN §11.2) 칸 폭 안에서 말줄임한다(AppBottomNav 와 같다).
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _labelStyle.copyWith(color: labelColor),
                        ),
                      ),
                      if (badge > 0) ...[const SizedBox(width: AppSpacing.xxs), _CountBadge(count: badge)],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// pen `A6Xn1I` — 16×16 원, 두 자리부터는 옆으로 늘어난다. 숫자 규칙 · 읽는 말은 [AppBottomNav] 의 배지와 같다.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '안 읽음 $count개',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: AppTypography.badge.copyWith(color: AppColors.onPrimary, height: 1.2),
          ),
        ),
      ),
    );
  }
}
