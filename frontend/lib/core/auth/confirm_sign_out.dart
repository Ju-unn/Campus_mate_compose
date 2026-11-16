import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16g 로그아웃 확인 — 공용 확인 팝업의 설명 없음 변형(pen `BDVsY`, 사용자 2026-11-16 「"로그아웃할까요?"-> 이것만」).
/// 설정 16 · 가입 중 화면(약관 동의 02-c · 학교 메일 02 등) · 정지 화면이 같은 팝업을 쓴다. 확인하면 팝업이 먼저 닫히고,
/// 로그아웃이 끝나면 라우터가 로그인 화면으로 보낸다 — 여기서 이동하지 않는다.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final signOut = ref.read(signOutProvider);
  final confirmed = await showConfirmPopup(
    context,
    title: context.l10n.coreSignOutConfirmTitle,
    confirmLabel: context.l10n.commonLogout,
  );
  if (confirmed) {
    await signOut();
  }
}
