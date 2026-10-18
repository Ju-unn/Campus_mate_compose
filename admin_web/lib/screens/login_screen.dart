import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/router/admin_router.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A0 로그인(pen CRAiQ): 카드 440, 로고 → 제목 → 설명 → "구글로 로그인"(보조 단추, 가득), 블록 사이 24.
/// 실패(pen A0_로그인_실패): 단추 아래 24 에 오류 줄 — 로그인 시작이 실패했거나 구글에서 ?error= 로 돌아왔을 때.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await ref.read(adminAuthProvider).signInWithGoogle();
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      // 성공하면 페이지가 구글로 넘어간다. 돌아오지 않는 경우(팝업 막힘 등)에 다시 누를 수 있게 푼다.
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _returnedWithError(BuildContext context) {
    return GoRouterState.of(context).uri.queryParameters[GatePaths.loginFailedParam] == '1';
  }

  @override
  Widget build(BuildContext context) {
    return GateCard(
      width: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CampusMate', style: AdminTypography.xl.copyWith(color: AdminColors.primary)),
          const SizedBox(height: AdminSpacing.lg),
          Semantics(header: true, child: Text('관리자 로그인', style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(height: AdminSpacing.lg),
          Text(
            '운영자 전용 구글 계정으로 로그인해 주세요. 로그인 뒤 2단계 인증이 필요해요.',
            style: AdminTypography.sm.copyWith(color: AdminColors.body),
          ),
          const SizedBox(height: AdminSpacing.lg),
          AdminButton(
            label: '구글로 로그인',
            variant: AdminButtonVariant.secondary,
            expand: true,
            loading: _busy,
            onPressed: _signIn,
          ),
          if (_failed || _returnedWithError(context)) ...[
            const SizedBox(height: AdminSpacing.lg),
            const ErrorRow('구글 로그인을 마치지 못했어요. 다시 시도해 주세요.'),
          ],
        ],
      ),
    );
  }
}
