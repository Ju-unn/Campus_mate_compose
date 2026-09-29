import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16g(pen `ZkOEb`) 로그아웃 확인. 설정 16 과 약관 동의 02-c 가 같은 문구 · 같은 시트를 쓴다.
/// 틀이 안전 확인 시트(`aCTy1`)와 같아 그대로 쓴다. 확인하면 시트가 먼저 닫히고,
/// 로그아웃이 끝나면 라우터가 로그인 화면으로 보낸다 — 여기서 이동하지 않는다.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final signOut = ref.read(signOutProvider);
  final confirmed = await showSafetyConfirmSheet(
    context,
    title: '로그아웃할까요?',
    description: '다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.',
    confirmLabel: '로그아웃',
  );
  if (confirmed) {
    await signOut();
  }
}
