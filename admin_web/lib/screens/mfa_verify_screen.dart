import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/screens/code_form.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A1 2단계 입력(pen A1_2단계_입력 PNG): 카드 480, 제목 → 설명 → 6칸 → (오류 줄) → 확인, 사이 20.
class MfaVerifyScreen extends ConsumerWidget {
  const MfaVerifyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(gateProvider).value;
    final factorId = stage is VerifyMfa ? stage.factorId : null;
    return GateCard(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('2단계 인증 코드 입력', style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(height: AdminSpacing.gateBlock),
          Text('인증 앱에 나온 6자리 숫자를 입력해 주세요.', style: AdminTypography.sm.copyWith(color: AdminColors.body)),
          const SizedBox(height: AdminSpacing.gateBlock),
          // 관문이 이 화면으로 보낼 때는 늘 VerifyMfa 다. 잠깐 다른 단계로 바뀌는 사이에는 칸만 비워 둔다.
          if (factorId != null) CodeForm(factorId: factorId),
        ],
      ),
    );
  }
}
