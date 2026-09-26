import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 두 시트는 채팅탭 PR 5 의 `ChatRoomMenuSheet`(Menu · Chat `RzZT8`) · 차단 확인과 같은 마스터다(결정 D4).
// PR 5 가 먼저 merge 되면 common/widgets 로 옮긴 그 시트를 쓴다(공유 파일 요청). 아니면 여기 두고 백로그 39 승격 줄에 합친다.

/// 내 글 "…"(15d-1 `RCNu0`) → "삭제하기" → 확인(15d-2 `K64Q8p`) → 지우기(사용자 결정 2).
Future<void> showPollMenu(BuildContext context, WidgetRef ref, String pollId) async {
  final wantsDelete = await _showSheet<bool>(context, const _PollMenuSheet());
  if (wantsDelete != true || !context.mounted) return;
  if (await _showSheet<bool>(context, const _DeleteConfirmSheet()) != true) return;
  final error = await ref.read(communityFeedViewModelProvider.notifier).delete(pollId);
  if (error != null && context.mounted) showPollToast(context, error);
}

Future<T?> _showSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다(채팅 시트와 같다).
    barrierColor: AppColors.scrim,
    builder: (_) => sheet,
  );
}

/// 손잡이 36×4 · 모서리 8 · hairline(두 시트 공통).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(AppRadius.sm)),
    );
  }
}

/// 누르는 행. ListTile 은 쓰지 않는다 — 가장 가까운 Material 이 시트 밖이면 눌림 효과가 떠 있다(COMMON §4-2).
class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: child),
      ),
    );
  }
}

/// 15d-1 메뉴(Menu · Chat 인스턴스 `ofjwb`): #FFF · 위 radius 24 · 안쪽 [12,16,24,16] · 간격 4,
/// 행 52(안쪽 [0,4], 아이콘 20 + 12 + 16/400), "삭제하기" 줄만 error, 구분선 1 hairlineSoft, "취소" 16/600.
class _PollMenuSheet extends StatelessWidget {
  const _PollMenuSheet();

  @override
  Widget build(BuildContext context) {
    void pick(bool? result) => Navigator.of(context).pop(result);
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
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xxs,
            children: [
              const Center(child: _SheetHandle()),
              _SheetRow(
                onTap: () => pick(true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: Row(
                    children: [
                      const Icon(AppIcons.trash2, size: 20, color: AppColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '삭제하기',
                          // pen 16 / normal, 줄높이 속성 없음 · 렌더 23(채팅 메뉴 행과 같다).
                          style: AppTypography.body.copyWith(color: AppColors.error, height: 23 / 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const ColoredBox(color: AppColors.hairlineSoft, child: SizedBox(height: 1)),
              _SheetRow(
                onTap: () => pick(null),
                child: Center(
                  child: Text('취소', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 23 / 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 15d-2 확인(AlertSheet `D0TvG` 인스턴스 `CCdBk`): 위 radius 24 · 그림자 #00000026 (0,-2) blur 16 ·
/// 손잡이 영역 위아래 12 · 내용 [8,16,32,16] 간격 16 · 제목 20/700 · 본문 14/400 lh1.55 muted ·
/// 버튼 세로 간격 8(button-danger 56 · button-text 48).
class _DeleteConfirmSheet extends StatelessWidget {
  const _DeleteConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: [BoxShadow(color: Color(0x26000000), offset: Offset(0, -2), blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(child: _SheetHandle()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('이 질문을 삭제할까요?', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '질문과 받은 투표가 모두 사라지고 되돌릴 수 없어요.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: '삭제하기',
                      variant: AppButtonVariant.danger,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      label: '취소',
                      variant: AppButtonVariant.text,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
