import 'dart:math' as math;

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 실사진 가로 슬라이더 + 점 인디케이터(pen `o2Nhn` 화면 15, 14c "Real Photo Slider").
/// pen 에 photo-slider 마스터가 없어 화면 15 plain 프레임 값을 따른다. 다음 장이 오른쪽에 잘려 엿보인다.
class PhotoSlider extends StatefulWidget {
  const PhotoSlider({required this.photos, required this.photoSize, this.firstPhotoBadge, super.key});

  final List<ImageProvider> photos;

  /// 사진 한 장 크기. 화면 15 = 252×184(pen `T09a8`), 14c = 288×260.
  final Size photoSize;

  /// 첫 장 오른쪽 위에 얹는 배지(화면 15 "수락 후 공개", pen `E2kWIB`). 첫 페이지 안에 있어 같이 넘어간다.
  final Widget? firstPhotoBadge;

  @override
  State<PhotoSlider> createState() => _PhotoSliderState();
}

class _PhotoSliderState extends State<PhotoSlider> {
  PageController? _controller;
  var _page = 0;

  @override
  void didUpdateWidget(PhotoSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 사진이 줄면 PageView 는 마지막 장으로 물러난다 — 점도 같이 물린다. 0장이면 clamp(0, -1) 이 던지니 max 로 막는다.
    _page = math.min(_page, math.max(0, widget.photos.length - 1));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.photoSize.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 한 페이지 = 사진 + 간격 8. 첫 장을 왼쪽에 붙이고(padEnds false) 남는 폭에 다음 장이 보인다.
              final fraction = math.min(1.0, (widget.photoSize.width + AppSpacing.xs) / constraints.maxWidth);
              if (_controller?.viewportFraction != fraction) {
                // viewportFraction 은 바꿀 수 없어 부모 폭이 바뀌면 새로 만든다. 옛것은 PageView 가 놓은 뒤 버린다.
                final old = _controller;
                _controller = PageController(viewportFraction: fraction, initialPage: _page);
                if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
              }
              return PageView.builder(
                controller: _controller,
                padEnds: false,
                itemCount: photos.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Semantics(
                    container: true,
                    image: true,
                    label: '실제 사진 ${index + 1}, 전체 ${photos.length}장',
                    // 그림을 decoration 으로 깐다 — Image 위젯은 그림 비율로 제 높이를 주장한다.
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        image: DecorationImage(image: photos[index], fit: BoxFit.cover),
                      ),
                      child: index == 0 && widget.firstPhotoBadge != null
                          ? Stack(
                              children: [
                                // pen `E2kWIB` 첫 장 안 x150 y12 → 위 12, 오른쪽 13(토큰 밖 리터럴).
                                Positioned(top: AppSpacing.sm, right: 13, child: widget.firstPhotoBadge!),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // pen `SC7rv`(CarouselDots `Kd4S5`) 점 6×6 · 간격 6 은 토큰 밖 리터럴. 바뀔 때 애니메이션 없음.
              for (var index = 0; index < photos.length; index++)
                Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(left: index == 0 ? 0 : 6),
                  decoration: BoxDecoration(
                    // 비활성 #DDDDDD 는 흰 바탕 대비 1.36:1 — 출시 전 점검 대상(pen 대로 둠).
                    color: index == _page ? AppColors.ink : AppColors.hairline,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
