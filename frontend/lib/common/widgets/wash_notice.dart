import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 글만 있는 안내(datingApp.pen Notice `WQIrY` — 아이콘 · 링크 끔): primary-wash 바탕, 모서리 12, 안쪽 14, 14/400 body 줄높이 1.5.
/// 15-4 카드 미리보기 · 06-4 지인 차단(xxLBt) · 02 미등록 학교(RxIqA)가 같이 쓴다. 제목 · 아이콘이 있는 안내는 [NoticeCard].
class WashNotice extends StatelessWidget {
  const WashNotice({required this.text, super.key});

  final String text;

  /// 모서리 12 · 안쪽 14 는 pen 값(토큰 사이 값 — 라운드 sm 8 · md 14, 간격 sm 12 · md 16).
  static const double _radius = 12;
  static const double _padding = 14;

  @override
  Widget build(BuildContext context) {
    // 폭은 부모가 정한다 — 폭 꽉(pen fill)이 필요한 자리는 부모가 늘린다(ListView · stretch · SizedBox).
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Text(text, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.body)),
      ),
    );
  }
}
