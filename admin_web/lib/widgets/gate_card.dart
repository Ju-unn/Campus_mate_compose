import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/widgets/enter_motion.dart';
import 'package:flutter/material.dart';

/// 관문 화면(A0 · A1 · 권한 없음 · 2단계 필요)의 가운데 카드. 바탕 web-canvas 위 흰 카드,
/// 테두리 web-outline 1 · 모서리 14 · 안쪽 40. 폭은 화면마다 다르다(PNG 측정: A0 440, A1 등록 560, 나머지 480).
/// 글자는 끌어서 복사할 수 있다(비밀 키 포함). 처음 그려질 때 한 번 살짝 올라오며 나타난다(EnterMotion, 동작 줄이기면 없음).
/// 브라우저 탭 제목을 "CampusMate 관리자"로 되돌린다 — 셸에서 메뉴 이름을 달았다가 로그아웃하면 남아 있지 않게.
/// 브라우저 탭 제목(관문 화면 · 셸 접미사)
const String appTitle = 'CampusMate 관리자';

class GateCard extends StatelessWidget {
  const GateCard({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    final page = Scaffold(
      backgroundColor: AdminColors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AdminSpacing.lg),
          child: SelectionArea(
            child: EnterMotion(
              child: Container(
              width: width,
              padding: const EdgeInsets.all(AdminSpacing.gateCard),
              decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
              // 테두리를 앞에 그려 안쪽 40 이 테두리 두께만큼 밀리지 않게 한다(pen 은 테두리가 칸 크기에 들지 않는다).
              foregroundDecoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(color: AdminColors.outline),
              ),
              child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return Title(title: appTitle, color: AdminColors.primary, child: page);
  }
}
