import 'dart:math' as math;

import 'package:campus_mate/common/university_logos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 학교 로고 + 학교 이름(pen School Symbol — 학교 원본 `WdrL7` 등 5개, 높이 · 정렬은 02_SCHOOL_ROW_HEIGHT_FIX 10-01).
///
/// 로고는 글자보다 2 크고(12→14 · 14→16 · 16→18) 글자와 4 띄운다. 글자가 두 줄로 넘어가면 로고는 첫 줄 가운데에 두고
/// 둘째 줄은 로고 + 4 만큼 들여 쓴다 — 두 줄 덩어리 가운데로 옮기지 않는다. 글자를 키우면 로고는 그대로, 커진 첫 줄
/// 가운데로 간다. 로고가 없는 학교거나 아직 · 못 불러오면 간격까지 빼고 이름만 그린다.
///
/// 글자 칸이 [Flexible] 이라 폭이 정해진 자리에 둔다 — 가로로 끝없는 자리(Row 자식 · 가로 ListView)면 Expanded 등으로
/// 감싼다. [style] 은 글자 크기와 줄높이(height)가 있어야 한다(AppTypography 토큰은 다 있다).
class SchoolLabel extends ConsumerWidget {
  const SchoolLabel(
    this.university, {
    this.text,
    required this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    super.key,
  });

  /// 로고를 찾는 학교 이름(`universities.name`).
  final String university;

  /// 그릴 글자 — 학과 · 학번을 붙일 때 넘긴다. 없으면 [university].
  final String? text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// 두 줄로 접힐 때 줄 정렬 — 오른쪽(end)이면 로고 + 글자 묶음도 칸 오른쪽에 붙고, 글자 상자를 가장 긴 줄 폭으로
  /// 줄여 로고가 첫 줄 바로 앞 4 에 온다. 없으면 왼쪽 정렬(지금 그대로).
  final TextAlign? textAlign;

  static const double _gap = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // const 생성자에서는 style 의 필드를 볼 수 없어 여기서 — 로고가 없는 학교에서도 바로 걸리게 맨 앞에 둔다.
    assert(style.fontSize != null && style.height != null, 'SchoolLabel 은 style 의 fontSize · height 로 로고 자리를 잰다');
    final alignEnd = textAlign == TextAlign.end || textAlign == TextAlign.right;
    final label = Text(
      text ?? university,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      textWidthBasis: alignEnd ? TextWidthBasis.longestLine : TextWidthBasis.parent,
    );
    final url = ref.watch(universityLogosProvider).value?[university];
    if (url == null) return label;

    final logo = style.fontSize! + 2;
    final firstLine = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.network(
          url,
          width: logo,
          height: logo,
          excludeFromSemantics: true,
          // 간격을 그림 쪽에 붙여 둬야 못 불러왔을 때 같이 빠진다(errorBuilder 는 frameBuilder 를 거치지 않는다).
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => Padding(
            padding: EdgeInsets.only(top: math.max(0, (firstLine - logo) / 2), right: _gap),
            child: child,
          ),
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        Flexible(child: label),
      ],
    );
  }
}
