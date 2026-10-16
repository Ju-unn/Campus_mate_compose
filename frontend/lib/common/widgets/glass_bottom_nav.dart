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
/// 앞 방울 자리를 넘겨받아 새 화면의 방울이 그 자리에서 미끄러져 온다. 모션 줄이기가 켜져 있으면 처음부터 제자리.
///
/// 알약 위에서 끌면 방울 가운데가 손가락을 따라가고 손가락 밑 탭이 강조된다 — 화면은 손을 뗄 때 한 번만 바뀐다
/// (2026-10-16 사용자 요청 "드래그해서 움직이고 멈추면 그 탭 열리는거", 대장 결정: 진동은 다른 탭이 열릴 때만 · 알약 어디서든 ·
/// 방울 크기 그대로 · 모션 줄이기에서도 따라가기). 처음 탭에서 놓거나 시스템이 터치를 빼앗으면 제자리로 돌아간다.
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

/// 끄는 동안 강조 탭을 바꾸려면 지금 강조된 칸 경계를 이만큼 넘어야 한다 — 경계에서 손이 떨려도 강조가 깜빡이지 않게.
/// pen · DESIGN 에 없는 값이라 대장 지시 명세 값(2026-10-16, 4px)이다.
const double _switchMargin = AppSpacing.xxs;

class _GlassBottomNavState extends ConsumerState<GlassBottomNav> with SingleTickerProviderStateMixin {
  /// 방울 자리는 탭 단위(메인 0 ~ 나 4, 사이는 소수)다. 진행도 하나로 [_from] 에서 [_to] 로 옮긴다 —
  /// 새 화면 진입 · 끌기 시작 때 손가락 밑으로 건너오기 · 놓은 뒤 제자리 찾기가 모두 이 길이다.
  late double _from;
  late double _to;
  late final AnimationController _progress;

  /// 손가락 밑 탭 = 놓으면 열릴 탭(끌지 않을 때는 지금 탭). 색만 바꾸고 화면 읽기의 선택은 지금 탭 그대로다.
  late AppTab _highlight = widget.current;

  /// 끄는 손가락의 알약 기준 x. 알약 밖으로 나가도 자르지 않는다 — 돌아올 때 손가락과 방울이 어긋나지 않게.
  double _fingerX = 0;

  /// 끄는 중 시스템이 터치를 빼앗았는지(전화 · 알림창 · 홈 제스처). Flutter 는 끌기가 시작된 뒤의 취소도 onEnd 로
  /// 알려서, 먼저 오는 포인터 취소를 따로 적어 둔다.
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _to = widget.current.index.toDouble();
    // 탭을 눌러(끌어) 들어왔으면 앞 화면 방울 자리에서, 아니면 제자리에서 시작한다(움직이지 않는다).
    _from = ref.read(_bubbleHandoffProvider).take(widget.current) ?? _to;
    _progress = AnimationController(vsync: this, duration: AppMotion.press, value: 1);
    if (_from != _to) _progress.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final instant = MediaQuery.disableAnimationsOf(context);
    _progress.duration = instant ? Duration.zero : AppMotion.press;
    // 모션 줄이기: 움직이던 것도 바로 끝 자리.
    if (instant) _progress.value = 1;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// 지금 그려진 방울 자리(탭 단위).
  double get _shown => _from + (_to - _from) * AppMotion.pressCurve.transform(_progress.value);

  /// 지금 자리에서 [to] 로 `{motion.press}` 동안 미끄러진다(모션 줄이기면 바로).
  void _glideTo(double to) {
    _from = _shown;
    _to = to;
    _progress.forward(from: 0);
  }

  void _select(AppTab tab) {
    if (tab != widget.current) {
      unawaited(ref.read(hapticsGatewayProvider).selectionClick());
      ref.read(_bubbleHandoffProvider).hand(from: _shown, to: tab);
    }
    context.go(_items[tab.index].$4);
  }

  void _dragStart(DragStartDetails details, double cellWidth) {
    _cancelled = false;
    _fingerX = details.localPosition.dx;
    _follow(cellWidth, glide: true);
  }

  // 손가락 좌표 대신 움직인 양을 더한다 — 두 번째 손가락이 끌기를 넘겨받아도 방울이 그쪽으로 튀지 않는다.
  void _dragUpdate(DragUpdateDetails details, double cellWidth) {
    _fingerX += details.primaryDelta!;
    _follow(cellWidth);
  }

  /// 방울 가운데를 손가락 x 에 둔다. 처음 한 번은 지금 자리에서 건너오고, 그 뒤는 도착점만 옮겨 1:1 로 따른다.
  void _follow(double cellWidth, {bool glide = false}) {
    final to = ((_fingerX - AppSpacing.xxs) / cellWidth - 0.5).clamp(0.0, _items.length - 1.0);
    // 일부러 끄는 프레임마다 setState 한다 — 이 다시 그리기가 강조와 함께 아래에서 바꾼 방울 자리(_to)도 그린다.
    setState(() => _highlight = _tabUnder(_fingerX, cellWidth));
    if (glide) return _glideTo(to);
    // 건너오는 중이면 도착점이 손가락을 따라 옮겨 가고, 다 건너왔으면 이 자리가 곧 방울 자리다.
    _to = to;
  }

  /// 놓으면 손가락 밑 탭을 연다(화면 전환은 여기서 한 번). 처음 탭이거나 시스템이 취소했으면 제자리로 돌아간다.
  void _dragEnd() {
    if (!_cancelled && _highlight != widget.current) return _select(_highlight);
    setState(() => _highlight = widget.current);
    _glideTo(widget.current.index.toDouble());
  }

  /// 손가락 밑 칸. 지금 강조된 칸 경계에서 [_switchMargin] 만큼 지난 자리부터 바꾼다(pen 견본: 경계 132 + 4 = 손가락 136 은 커뮤니티).
  AppTab _tabUnder(double x, double cellWidth) {
    final start = AppSpacing.xxs + _highlight.index * cellWidth;
    if (x > start - _switchMargin && x < start + cellWidth + _switchMargin) return _highlight;
    return _items[((x - AppSpacing.xxs) / cellWidth).floor().clamp(0, _items.length - 1)].$1;
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(chatBadgeCountProvider);
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
              double bubbleLeft(double tab) => (AppSpacing.xxs + tab * cellWidth - _bubbleOverhang)
                  .clamp(0, constraints.maxWidth - bubbleWidth)
                  .toDouble();
              // Listener 가 끌기 인식기보다 먼저 포인터 취소를 받는다(GestureBinding 이 맨 마지막에 돈다).
              return Listener(
                onPointerCancel: (_) => _cancelled = true,
                child: GestureDetector(
                  // 가로 끌기를 화면 읽기의 "가로 스크롤" 동작으로 내보내지 않는다 — 낭독기 사용자는 탭 방식 그대로다.
                  excludeFromSemantics: true,
                  onHorizontalDragStart: (details) => _dragStart(details, cellWidth),
                  onHorizontalDragUpdate: (details) => _dragUpdate(details, cellWidth),
                  onHorizontalDragEnd: (_) => _dragEnd(),
                  child: CustomPaint(
                    painter: const _OuterShadowPainter(_pillShadow, AppRadius.pill),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _GlassFill()),
                        AnimatedBuilder(
                          animation: _progress,
                          builder: (context, child) => Positioned(
                            left: bubbleLeft(_shown),
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
                              for (final (tab, icon, label, _) in _items)
                                Expanded(
                                  child: _GlassTab(
                                    icon: icon,
                                    label: label,
                                    isSelected: tab == widget.current,
                                    isHighlighted: tab == _highlight,
                                    badge: tab == AppTab.chat ? badge : 0,
                                    onTap: () => _select(tab),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 다음 탭 화면의 내비에게 "앞 화면 방울이 어디 있었는지"(탭 단위 — 끌다 놓았으면 소수)를 한 번 넘긴다.
/// 받을 탭이 맞을 때만 쓰고 바로 비운다.
class _BubbleHandoff {
  ({double from, AppTab to})? _pending;

  void hand({required double from, required AppTab to}) => _pending = (from: from, to: to);

  double? take(AppTab current) {
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
    required this.isHighlighted,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// 지금 탭 — 화면 읽기가 "선택됨" 으로 읽는다.
  final bool isSelected;

  /// 활성 색으로 칠하는 탭. 평소엔 지금 탭, 끄는 동안엔 손가락 밑 탭이다.
  final bool isHighlighted;
  final int badge;
  final VoidCallback onTap;

  /// pen 라벨(`G2LX51` 등) 11/600 — lineHeight · letterSpacing 속성 없음, 렌더 높이 16. badge 토큰(1.3 · 0.02em)과 달라 맞춘다.
  static final _labelStyle = AppTypography.badge.copyWith(height: 16 / 11, letterSpacing: 0);

  @override
  Widget build(BuildContext context) {
    // 비활성 body(사용자 승인), 활성 아이콘은 primary 채움색(현행 유지), 활성 라벨은 흰 바탕 글자용 primary-text.
    final iconColor = isHighlighted ? AppColors.primary : AppColors.body;
    final labelColor = isHighlighted ? AppColors.primaryText : AppColors.body;
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
