import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/widgets.dart';

/// 3D 그림 아이콘 하나(pen `fIXLw` 3D Icon Library 타일). 화면은 [size] 만 고른다.
///
/// 원본이 512px 이라 화면 크기 × 화소 배율로 줄여서 풀어 둔다 — 설정 화면처럼 여러 개가 한꺼번에 떠도 메모리가 작다.
/// 옆에 글자가 붙는 장식 그림이라 낭독기에는 읽히지 않게 둔다.
class Icon3d extends StatelessWidget {
  const Icon3d(this.icon, {required this.size, super.key});

  final AppIcon3d icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Image.asset(
      icon.asset,
      width: size,
      height: size,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
