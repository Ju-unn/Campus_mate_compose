import 'package:campus_mate/common/widgets/sheet_handle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 시트 틀(pen AlertSheet `D0TvG`): 캔버스 · 위 모서리 24 · 위쪽 그림자(`AppElevation.top`) · 화면 폭 전체 · 아래 안전 영역 비움.
/// 안쪽 내용과 스크롤은 쓰는 쪽이 정한다(손잡이가 고정인 시트 · 같이 스크롤하는 시트가 있다).
class SheetFrame extends StatelessWidget {
  const SheetFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: AppElevation.top,
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// pen AlertSheet `D0TvG` 전체: [SheetFrame] 안에 손잡이 칸(위아래 12) → 내용 [8,16,32,16](가로로 꽉 참)을 두고,
/// 글자를 키운 기기에서 화면보다 길어지면 통째로 스크롤한다. 간격은 [children] 안에 넣는다.
class AlertSheet extends StatelessWidget {
  const AlertSheet({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Center(child: SheetHandle()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    );
  }
}
