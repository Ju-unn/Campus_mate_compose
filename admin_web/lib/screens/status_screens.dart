import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/gate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 공통 "권한 없음"(pen 공통_권한_없음 PNG)
class ForbiddenScreen extends ConsumerWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(adminAuthProvider);
    return _StatusCard(
      icon: LucideIcons.shieldAlert,
      title: '관리자 계정이 아니에요',
      body: '이 구글 계정은 관리자로 등록되어 있지 않아요. 운영자 계정으로 다시 로그인해 주세요.',
      primaryLabel: '다른 계정으로 로그인',
      onPrimary: () async {
        await auth.signOut();
        await auth.signInWithGoogle();
      },
      onSignOut: auth.signOut,
    );
  }
}

/// 공통 "2단계 인증이 필요해요"(pen 공통_2단계_필요 PNG) — 서버가 403 mfa_required 로 거절했을 때
class MfaRequiredScreen extends ConsumerWidget {
  const MfaRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(gateProvider).value;
    return _StatusCard(
      icon: LucideIcons.shieldAlert,
      title: '2단계 인증이 필요해요',
      body: '인증 앱의 6자리 코드를 입력해야 계속할 수 있어요.',
      primaryLabel: '2단계 인증 코드 입력',
      onPrimary: stage is MfaRequired ? () => ref.read(gateProvider.notifier).startMfa(stage) : null,
      onSignOut: ref.read(adminAuthProvider).signOut,
    );
  }
}

/// 공통 "연결 실패"(pen 공통_연결_실패) — 서버에 닿지 못했을 때(연결 실패 · 5xx · CORS 없는 500).
class UnavailableScreen extends ConsumerWidget {
  const UnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: LucideIcons.circleAlert,
      title: '서버에 연결하지 못했어요',
      body: '인터넷 연결을 확인하고 잠시 뒤 다시 시도해 주세요.',
      primaryLabel: '다시 시도',
      onPrimary: ref.read(gateProvider.notifier).retry,
      onSignOut: ref.read(adminAuthProvider).signOut,
    );
  }
}

/// 공통 "설정 누락"(pen 공통_설정_누락) — dart-define 값이 빠진 빌드.
/// 값은 빌드에 박히므로 고쳐 다시 배포한 뒤 "다시 불러오기"(페이지 다시 열기)로 새 빌드를 받는다.
/// Supabase 를 켜지 않은 상태라 로그아웃할 세션이 없어 로그아웃 단추는 두지 않는다(대장 결정 10-18, pen 도 같이 뺀다).
class ConfigMissingScreen extends ConsumerWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: LucideIcons.circleAlert,
      title: '설정이 빠졌어요',
      body: '관리자용 안내: 서버 주소 또는 Supabase 설정 값이 비어 있어요. 배포 환경 변수를 확인해 주세요.',
      primaryLabel: '다시 불러오기',
      onPrimary: ref.read(pageReloaderProvider),
    );
  }
}

/// 공통 "판정 중"(pen 공통_판정_중) — 도는 아이콘 16(web-muted) → 12 → 글(sm, web-muted).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Title(
      title: appTitle,
      color: AdminColors.primary,
      child: Scaffold(
        backgroundColor: AdminColors.canvas,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AdminLoader(color: AdminColors.muted),
              const SizedBox(height: AdminSpacing.sm),
              Text('로그인 상태를 확인하고 있어요', style: AdminTypography.sm.copyWith(color: AdminColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 아이콘 · 제목이 가운데 놓인 카드(폭 480): 아이콘 40 → 16 → 제목 → 14 → 설명 → 16 → 주 단추 → 16 → 로그아웃(글자 단추).
/// 간격은 PNG 측정(공통_권한_없음 · 공통_2단계_필요).
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.onSignOut,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final primaryLabel = this.primaryLabel;
    final onSignOut = this.onSignOut;
    return GateCard(
      width: 480,
      child: Column(
        children: [
          Icon(icon, size: AdminSizes.statusIcon, color: AdminColors.danger),
          const SizedBox(height: AdminSpacing.md),
          Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
          const SizedBox(height: AdminSpacing.statusTitleToBody),
          Text(body, textAlign: TextAlign.center, style: AdminTypography.sm.copyWith(color: AdminColors.body)),
          if (primaryLabel != null) ...[
            const SizedBox(height: AdminSpacing.md),
            AdminButton(label: primaryLabel, onPressed: onPrimary),
          ],
          if (onSignOut != null) ...[
            const SizedBox(height: AdminSpacing.md),
            AdminButton(label: '로그아웃', variant: AdminButtonVariant.text, onPressed: onSignOut),
          ],
        ],
      ),
    );
  }
}
