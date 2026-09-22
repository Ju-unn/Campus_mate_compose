import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 되돌릴 수 없는 두 가지를 누르기 **전에** 알려주는 확인 다이얼로그.
/// pen 에 없는 화면이라 기존 다이얼로그 스타일을 그대로 쓴다(결정 7·10 이 시안 뒤에 생겼다).

/// 채팅방 나가기 = 게이트 거절(결정 11). **같은 다이얼로그를 앱바 메뉴와 14f 시트가 함께 쓴다** —
/// 게이트 전용 거절 문구를 따로 만들면 같은 동작이 두 얼굴을 갖는다.
Future<bool> confirmLeaveChat(BuildContext context) async {
  return await _confirm(
    context,
    title: '채팅방을 나갈까요?',
    // 되돌릴 수 없다는 것과 상대에게 보인다는 것을 둘 다 적는다(결정 7).
    body: '나가면 이 대화를 다시 볼 수 없고, 상대에게는 나갔다고 표시돼요.',
    confirmLabel: '나가기',
    isDestructive: true,
  );
}

/// 신뢰 확인 수락(결정 10). 취소가 없고 상대에게 문구가 간다.
Future<bool> confirmTrustAccept(BuildContext context) async {
  return await _confirm(
    context,
    title: '카카오톡 아이디·실사진 공개를 수락할까요?',
    body: '수락하면 채팅창에 수락했다는 문구가 상대에게 전송됩니다.',
    confirmLabel: '수락',
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.canvas,
      title: Text(title, style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
      content: Text(body, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('취소', style: AppTypography.labelSmall.copyWith(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: AppTypography.labelSmall
                .copyWith(color: isDestructive ? AppColors.error : AppColors.primaryText),
          ),
        ),
      ],
    ),
  );
  return answer ?? false;
}
