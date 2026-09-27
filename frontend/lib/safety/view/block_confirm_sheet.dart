import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 14e 상대 차단 확인(pen `aCTy1`). 확인하면 true — 차단 요청은 부른 쪽이 보낸다.
Future<bool> showBlockConfirmSheet(BuildContext context, String nickname) {
  return showSafetyConfirmSheet(
    context,
    title: '$nickname 님을 차단할까요?',
    // pen `u3gXUA` 문구 그대로.
    description: '이 대화는 내 목록에서 사라지고, 서로의 카드에 다시 나타나지 않아요. '
        '상대에게는 대화를 나갔다고 표시돼요. 차단은 설정 > 차단 목록에서 해제할 수 있어요.',
    confirmLabel: '차단',
  );
}
