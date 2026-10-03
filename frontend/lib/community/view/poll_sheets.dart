import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 두 시트는 채팅탭 `ChatRoomMenuSheet`(Menu · Chat `RzZT8`) · 차단 확인과 같은 마스터다(결정 D4) — 공통 승격은 백로그 39.

const String _pollReportedMessage = '신고했어요. 운영팀이 확인할게요';

/// 남의 글 신고(A16 · 신고 버튼 `uPUf3`). 받은 리뷰 신고(20c)와 같은 흐름 — 글쓴이는 익명이라 차단할 상대가 없어
/// `reportThenLeave` 를 쓰지 않고, 어느 결과든 카드는 그대로 남는다(가림은 운영자가 한다, 서버 #191).
Future<void> reportPoll(BuildContext context, String pollId) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showReportSheet(context, ReportTarget.poll(pollId));
  if (result == null) return;
  showSafetyToast(messenger, result.outcome == ReportOutcome.reported ? _pollReportedMessage : result.message);
}

/// 내 글 "…"(15d-1 `RCNu0`) → "삭제하기" → 확인(15d-2 `K64Q8p`) → 지우기(사용자 결정 2).
/// 지우는 동안 확인 시트는 열린 채 "삭제하기" 만 꺼지고(15d-2 삭제 중 `EIEFb`), 끝나면 닫고 "삭제했어요"(15d-5 `SKQgV`)
/// 또는 오류 토스트. 도중에 시트를 닫아도 요청이 끝나면 결과를 알린다 — 서버에서는 이미 지워졌을 수 있다.
Future<void> showPollMenu(BuildContext context, WidgetRef ref, String pollId) async {
  final wantsDelete = await _showSheet<bool>(context, const _PollMenuSheet());
  if (wantsDelete != true || !context.mounted) return;
  Future<String?>? deleting;
  await _showSheet<void>(
    context,
    _DeleteConfirmSheet(
      onDelete: () async {
        await (deleting = ref.read(communityFeedViewModelProvider.notifier).delete(pollId));
      },
    ),
  );
  if (deleting == null) return; // "삭제하기" 를 누르지 않고 닫았다.
  final error = await deleting;
  if (context.mounted) showPollToast(context, error ?? pollDeletedMessage);
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
/// 버튼 세로 간격 8(button-danger 56 · button-text 48). 지우는 중(`EIEFb`)엔 "삭제하기" 만 꺼진 모양
/// (AppButton 비활성 = 채움 primaryDisabled · 글자 disabled, 스피너 없음), "취소" 는 그대로 닫는다.
class _DeleteConfirmSheet extends StatefulWidget {
  const _DeleteConfirmSheet({required this.onDelete});

  final Future<void> Function() onDelete;

  @override
  State<_DeleteConfirmSheet> createState() => _DeleteConfirmSheetState();
}

class _DeleteConfirmSheetState extends State<_DeleteConfirmSheet> {
  bool _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    await widget.onDelete();
    // "취소" · 바깥 탭으로 이미 닫히는 중이면(애니메이션 동안 State 는 살아 있다) 또 닫지 않는다 — 아래 화면이 닫힌다.
    if (mounted && ModalRoute.of(context)!.isCurrent) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: AppElevation.top,
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
                      onPressed: _deleting ? null : _delete,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      label: '취소',
                      variant: AppButtonVariant.text,
                      onPressed: () => Navigator.of(context).pop(),
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
