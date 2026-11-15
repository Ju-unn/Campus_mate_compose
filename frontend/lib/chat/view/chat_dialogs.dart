import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:flutter/material.dart';

/// 되돌릴 수 없는 두 가지를 누르기 **전에** 묻는 확인 — 공용 확인 팝업(pen "Row X · 확인 팝업", 대장 전달 2026-11-16).

/// 채팅방 나가기 = 게이트 거절(결정 11). **같은 팝업을 앱바 메뉴 · 14f 시트 · 대화 목록이 함께 쓴다** —
/// 게이트 전용 거절 문구를 따로 만들면 같은 동작이 두 얼굴을 갖는다. 되돌릴 수 없어 위험(빨강) 변형이다.
Future<bool> confirmLeaveChat(BuildContext context) => showConfirmPopup(
      context,
      title: context.l10n.chatLeaveConfirmTitle,
      body: context.l10n.chatLeaveConfirmBody,
      confirmLabel: context.l10n.chatLeave,
      danger: true,
    );

/// 신뢰 확인 수락(결정 10, 14g 미리 수락 배너). 상대에게 문구가 간다. 일반 변형이다.
Future<bool> confirmTrustAccept(BuildContext context) => showConfirmPopup(
      context,
      title: context.l10n.chatTrustAcceptConfirmTitle,
      body: context.l10n.chatTrustAcceptConfirmBody,
      confirmLabel: context.l10n.chatTrustAcceptConfirmAction,
    );
