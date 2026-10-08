import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/core/auth/confirm_sign_out.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 관문 화면 맨 아래의 "로그아웃" 글자 버튼. 약관 동의(02-c, pen `u05wB`)와 학교 메일 입력(02)이 같은 모양 ·
/// 같은 동작(16g 확인 시트 → [confirmSignOut])을 쓴다. 소셜로 잘못 들어온 사람의 탈출구다.
class LogoutTextButton extends ConsumerWidget {
  const LogoutTextButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MutedTextButton(label: '로그아웃', onPressed: () => confirmSignOut(context, ref));
  }
}
