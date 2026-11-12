import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:flutter/material.dart';

/// 그림 칸 비율 — pen HomeSeasonCarousel `z4q4nv` 그림 328×184. 폭은 화면에 맞춰 늘고 높이는 이 비율을 따른다.
const double _imageAspect = 328 / 184;

/// 그림과 점 줄 사이(pen `z4q4nv` gap 10).
const double _dotsGap = 10;

/// 점 지름 · 점 사이(pen CarouselDots · 5 `djKOY` — 6 · 6, 실사진 슬라이더 `Kd4S5` 와 같은 값).
const double _dotSize = 6;

/// 다음 장으로 넘기는 간격(사용자 결정 11-12 「3초마다」).
const Duration _interval = Duration(seconds: 3);

/// 홈 배너 슬라이드(홈 v3 `kkKiZ` · 컴포넌트 HomeSeasonCarousel `z4q4nv`). 그림과 그림 속 문구는 서버가 준다(`/home/summary` banners).
/// 3초마다 다음 장(마지막 다음은 처음). 누르기 동작은 없다(사용자 결정 11-12 「눌러도 아무 데도 안 간다」).
/// 누르고 있는 동안 · 기기 "동작 줄이기" · 화면 읽기가 켜져 있으면 저절로 넘기지 않는다([AutoMarquee] 와 같은 규칙) — 손으로는 넘긴다.
/// 0장이면 그리지 않고(홈 화면이 앞뒤 간격째 뺀다), 1장이면 점도 넘김도 없다.
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({required this.banners, super.key});

  final List<HomeBanner> banners;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  var _page = 0;

  /// 화면을 누르고 있는 손가락 수. 모두 뗐을 때(0)만 다시 넘긴다.
  int _pointersDown = 0;

  /// 저절로 넘기지 않는 때 — 기기 "동작 줄이기" 또는 화면 읽기 켜짐(WCAG 2.2.2).
  bool _reduceMotion = false;

  /// 홈이 보이는지 — 다른 탭 · 위에 쌓인 화면에 가려지면 TickerMode 가 꺼진다. 가려진 채 넘김을 걸면 멈춘 Ticker 에 쌓인다.
  bool _visible = true;

  /// 앱이 앞에 있는지(뒤로 가면 화면을 그리지 않는다).
  bool _foreground = true;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  /// 넘길 수 있으면 3초 타이머를 (없을 때만) 걸고, 아니면 끈다. 다시 걸면 그때부터 3초다.
  void _sync() {
    if (widget.banners.length < 2 || _reduceMotion || _pointersDown > 0 || !_visible || !_foreground) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_interval, (_) => _advance());
  }

  void _advance() {
    if (!_controller.hasClients) return;
    final next = (_page + 1) % widget.banners.length;
    unawaited(_controller.animateToPage(next, duration: AppMotion.standard, curve: AppMotion.standardCurve));
  }

  void _press(int delta) {
    _pointersDown += delta;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
    // valuesOf 가 의존을 걸어 TickerMode 가 바뀌면 여기가 다시 불린다.
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 장 수가 줄면 PageView 는 마지막 장으로 물러난다 — 점도 같이 물린다.
    _page = math.min(_page, math.max(0, widget.banners.length - 1));
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: _imageAspect,
          // 손가락이 닿아 있는 동안 멈춘다 — PageView 의 밀기는 그대로 받는다.
          child: Listener(
            onPointerDown: (_) => _press(1),
            onPointerUp: (_) => _press(-1),
            onPointerCancel: (_) => _press(-1),
            child: PageView.builder(
              controller: _controller,
              itemCount: banners.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => _BannerImage(banner: banners[index]),
            ),
          ),
        ),
        if (banners.length > 1) ...[
          const SizedBox(height: _dotsGap),
          _Dots(count: banners.length, current: _page),
        ],
      ],
    );
  }
}

/// 배너 그림 한 장 — 모서리 16, 덮어 그린다. 오는 동안 · 못 받으면 회색(surfaceSoft) 바탕만 보인다.
/// 화면 읽기는 그림 속 문구를 그림으로 읽는다(누르기 동작 없음).
class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: banner.altText,
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: CachedNetworkImage(
          imageUrl: banner.imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (context, url, error) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 점 줄(pen CarouselDots · 5 `djKOY`) — 지름 6 · 사이 6, 현재 ink(#222222) · 나머지 hairline(#DDDDDD). 바뀔 때 움직임 없음(실사진 슬라이더와 같다).
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(width: _dotSize),
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(color: index == current ? AppColors.ink : AppColors.hairline, shape: BoxShape.circle),
          ),
        ],
      ],
    );
  }
}
