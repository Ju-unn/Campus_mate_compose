import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 아직 만들지 않은 탭(지금은 커뮤니티). 하단 내비는 5탭을 그리므로 갈 곳은 있어야 한다.
///
/// 톱니는 두지 않는다 — 설정(16)으로 들어가는 곳은 15 내 프로필(`nkFJV`) 앱바의 톱니
/// (`hwVQB` 안 `C7teyl`) 하나뿐이고, 그 화면이 `MyProfileScreen` 이다.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.tab, super.key});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(child: Text('곧 만나요', style: AppTypography.headline)),
      bottomNavigationBar: AppBottomNav(current: tab),
    );
  }
}
