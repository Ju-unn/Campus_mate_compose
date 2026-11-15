import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:flutter/widgets.dart';

/// 14e 상대 차단 확인 — 공용 확인 팝업 위험 변형(대장 전달 2026-11-16, 옛 시트 pen `aCTy1`). 확인하면 true — 차단 요청은 부른 쪽이 보낸다.
Future<bool> confirmBlock(BuildContext context, String nickname) => showConfirmPopup(
      context,
      title: context.l10n.safetyBlockConfirmTitle(nickname: nickname),
      body: context.l10n.safetyBlockConfirmDescription,
      confirmLabel: context.l10n.safetyBlockConfirmButton,
      danger: true,
    );
