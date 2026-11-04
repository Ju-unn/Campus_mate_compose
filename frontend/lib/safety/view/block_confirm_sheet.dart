import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 14e 상대 차단 확인(pen `aCTy1`). 확인하면 true — 차단 요청은 부른 쪽이 보낸다.
Future<bool> showBlockConfirmSheet(BuildContext context, String nickname) {
  return showSafetyConfirmSheet(
    context,
    title: context.l10n.safetyBlockConfirmTitle(nickname: nickname),
    // pen `u3gXUA` 문구 그대로.
    description: context.l10n.safetyBlockConfirmDescription,
    confirmLabel: context.l10n.safetyBlockConfirmButton,
  );
}
