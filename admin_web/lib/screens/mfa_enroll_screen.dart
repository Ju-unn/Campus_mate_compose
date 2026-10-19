import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/screens/code_form.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A1 2단계 등록(pen A1_2단계_등록 PNG): 카드 560, 제목 → 안내 1 → 비밀 키 상자 → 안내 2 → 6칸 → 확인, 사이 20.
/// QR 은 그리지 않는다 — Supabase QR 은 SVG 라 새 부품이 필요하다(설계서 §5). 비밀 키를 직접 넣게 한다.
class MfaEnrollScreen extends ConsumerStatefulWidget {
  const MfaEnrollScreen({super.key});

  @override
  ConsumerState<MfaEnrollScreen> createState() => _MfaEnrollScreenState();
}

class _MfaEnrollScreenState extends ConsumerState<MfaEnrollScreen> {
  TotpEnrollment? _enrollment;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  Future<void> _enroll() async {
    setState(() => _failed = false);
    try {
      final enrollment = await ref.read(adminAuthProvider).enrollTotp();
      if (mounted) setState(() => _enrollment = enrollment);
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollment = _enrollment;
    final step = AdminTypography.sm.copyWith(color: AdminColors.body);
    return GateCard(
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('2단계 인증 등록', style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(height: AdminSpacing.gateBlock),
          Text('1. 인증 앱(구글 OTP, 1Password 등)에서 새 항목을 만들고 아래 비밀 키를 직접 입력해 주세요.', style: step),
          const SizedBox(height: AdminSpacing.gateBlock),
          if (enrollment != null) ...[
            _SecretBox(secret: enrollment.secret),
            const SizedBox(height: AdminSpacing.gateBlock),
            Text('2. 앱에 나온 6자리 숫자를 입력해 주세요.', style: step),
            const SizedBox(height: AdminSpacing.gateBlock),
            CodeForm(factorId: enrollment.factorId),
          ] else if (_failed) ...[
            const ErrorRow('비밀 키를 만들지 못했어요. 잠시 뒤 다시 시도해 주세요.'),
            const SizedBox(height: AdminSpacing.gateBlock),
            AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: _enroll),
          ] else
            const SizedBox(height: 68, child: Center(child: AdminLoader(color: AdminColors.muted))),
        ],
      ),
    );
  }
}

/// 비밀 키 상자(pen WKK0m): web-surface-strong 바탕 · 모서리 8 · 안쪽 [12,16] · 키와 복사 사이 12, 키 20/700(고정폭 아님).
/// 키는 4자씩 띄워 보여 주고(손으로 옮겨 적기 쉽게) 줄바꿈을 허용한다(32자면 두 줄, 복사는 세로 가운데).
/// 복사는 띄어쓰기 없는 원문을 넣고 "복사했어요" 토스트를 띄운다.
class _SecretBox extends StatelessWidget {
  const _SecretBox({required this.secret});

  final String secret;

  String get _grouped => secret.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim();

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (context.mounted) AdminToast.show(context, '복사했어요');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('secret-box'),
      padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.md, vertical: AdminSpacing.sm),
      decoration: BoxDecoration(
        color: AdminColors.surfaceStrong,
        borderRadius: BorderRadius.circular(AdminRadius.sm),
      ),
      child: Row(
        children: [
          // Supabase 비밀 키는 32자라 pen 예시(16자)보다 길다 — 4자 묶음 사이에서 줄을 바꾼다.
          Expanded(child: Text(_grouped, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(width: AdminSpacing.sm),
          AdminButton(label: '복사', variant: AdminButtonVariant.secondary, onPressed: () => _copy(context)),
        ],
      ),
    );
  }
}
