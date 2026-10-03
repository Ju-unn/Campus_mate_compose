import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// ⋯ 시트에서 고른 것. 취소 · 바깥 탭은 null.
enum ChatRoomMenuAction { report, block, leave }

/// 채팅방 앱바 ⋯ 를 누르면 뜨는 바텀시트(pen `Lgdxu` / 시트 `hUrVg` = Menu · Chat `RzZT8`).
///
/// [canTargetPartner] 가 false 면(방을 못 읽어 상대를 모른다) 신고 · 차단 줄을 뺀다.
Future<ChatRoomMenuAction?> showChatRoomMenuSheet(
  BuildContext context, {
  bool canTargetPartner = true,
}) {
  return showSafetySheet<ChatRoomMenuAction>(
    context,
    (_) => ChatRoomMenuSheet(canTargetPartner: canTargetPartner),
  );
}

/// 행 3개 · 구분선 · 취소. 여백 [12,16,24,16], 간격 4, 그림자 없음.
/// 상대를 모르면 나가기 한 행만 남는다 — 이 모양은 pen 에 없어 같은 행을 뺀 것뿐이다.
class ChatRoomMenuSheet extends StatelessWidget {
  const ChatRoomMenuSheet({this.canTargetPartner = true, super.key});

  final bool canTargetPartner;

  @override
  Widget build(BuildContext context) {
    void pick(ChatRoomMenuAction? action) => Navigator.of(context).pop(action);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서 시트가 화면보다 길어지면 스크롤한다.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xxs,
            children: [
              const Center(child: SheetHandle()),
              if (canTargetPartner) ...[
                _MenuRow(
                  icon: AppIcon3d.siren,
                  iconSize: 22,
                  label: '신고하기',
                  color: AppColors.ink,
                  onTap: () => pick(ChatRoomMenuAction.report),
                ),
                // 되돌리기 어려운 동작이라 이 행만 글자가 빨강이다(pen `H4oXC` #C13515).
                _MenuRow(
                  icon: AppIcon3d.blockUser,
                  iconSize: 24,
                  label: '차단하기',
                  color: AppColors.error,
                  onTap: () => pick(ChatRoomMenuAction.block),
                ),
              ],
              _MenuRow(
                icon: AppIcon3d.logout,
                iconSize: 24,
                label: '채팅방 나가기',
                color: AppColors.ink,
                onTap: () => pick(ChatRoomMenuAction.leave),
              ),
              const ColoredBox(color: AppColors.hairlineSoft, child: SizedBox(height: 1)),
              _Tappable(
                onTap: () => pick(null),
                child: Center(
                  child: Text(
                    '취소',
                    // pen `l0H9N` 16/600, 줄높이 속성 없음 · 렌더 23.
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 23 / 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 한 행(pen `WAKrs` · `H4oXC` · `RqpxU`): 328×52, 여백 [0,4], 3D 아이콘(22 · 24 — pen 행마다 다르다)과 글자 사이 12.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final AppIcon3d icon;
  final double iconSize;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          children: [
            Icon3d(icon, size: iconSize),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                // pen 16 / normal, 줄높이 속성 없음 · 렌더 23.
                style: AppTypography.body.copyWith(color: color, height: 23 / 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 52 높이(최소값) 누름 칸. 눌림 효과가 시트와 같이 움직이게 칸 안에 Material 을 둔다(COMMON §4-2).
class _Tappable extends StatelessWidget {
  const _Tappable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: child),
        ),
      ),
    );
  }
}
