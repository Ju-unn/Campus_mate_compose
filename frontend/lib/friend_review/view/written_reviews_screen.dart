import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/friend_review_list_frame.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/friend_review/viewmodel/writable_friends_provider.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 화면 문구 — pen FEysN · kaGTH · N701NC · nGtDb(값표 20e §2~§5).
const _title = '내가 쓴 리뷰'; // pen V7KzU
const _notice = '내가 남긴 리뷰는 언제든 지울 수 있어요.\n수정은 할 수 없어요.'; // pen DPIaV
const _emptyTitle = '아직 쓴 리뷰가 없어요'; // pen QlDBt/ZBzIg
const _emptyDescription = '추천으로 연결된 친구에게\n리뷰를 남기면 여기에 모여요'; // pen QlDBt/DFs55
const _sheetTitle = '리뷰를 지울까요?'; // pen UClUE/xd8je
const _deletedMessage = '리뷰를 지웠어요'; // pen W7HENj/LGEZH
const _waitingTitle = '리뷰를 기다리는 친구'; // pen bDZnr/qa34E
const _waitingDescription = '추천 코드로 이어진 친구예요. 지웠거나 놓친 리뷰도 다시 쓸 수 있어요.'; // pen bDZnr/AJ2hf

/// pen UClUE/O7tR3q — 닉네임은 받은 사람.
String _sheetBody(String nickname) => '지우면 $nickname님 프로필에서 바로 사라지고\n되돌릴 수 없어요.';

const ({FriendReviewListSource source, String? profileId}) _written =
    (source: FriendReviewListSource.written, profileId: null);

/// 20e 내가 쓴 리뷰(pen `FEysN`, 20c 사본). 15 "내가 쓴 리뷰" 에서 push 로 연다.
/// 카드마다 휴지통 → 20e-2 확인 → 지우면 카드가 빠지고 20e-3 토스트. 고치기는 없다(안내 문구).
/// 안내 아래 20e-4 "리뷰를 기다리는 친구"(pen `bDZnr`) — 추천으로 이어졌고 아직 내 리뷰가 없는 친구에게 "쓰기"(결함 A3).
class WrittenReviewsScreen extends ConsumerWidget {
  const WrittenReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 읽는 중 · 실패 · 0명이면 섹션을 통째 숨긴다(대장 ②). 다시 읽는 동안은 지난 목록을 둬 깜빡이지 않는다.
    final friends = ref
        .watch(writableFriendsProvider)
        .value
        ?.when(onSuccess: (friends) => friends.isEmpty ? null : friends, onFailure: (_) => null);
    return FriendReviewListFrame(
      title: _title,
      notice: _notice,
      source: FriendReviewListSource.written,
      header: friends == null
          ? null
          : _WaitingFriends(friends: friends, onWrite: (friend) => _write(context, ref, friend)),
      cardBuilder: (context, review) =>
          FriendReviewCard(review: review, onDelete: () => _confirmDelete(context, ref, review)),
      // 20e-1 `QlDBt`(Empty `TVc8b`) — 마스코트 `J2kzx`(마스터 그대로) = 파란 목도리, 버튼은 꺼짐.
      empty: const FriendReviewEmpty(
        mascot: 'assets/images/mascot-male.png',
        title: _emptyTitle,
        description: _emptyDescription,
      ),
    );
  }

  /// 확인 시트 → 지우기. 시트는 지우기가 끝나면 닫히고, 도중에 닫아도 요청이 끝나면 결과를 알린다
  /// (서버에서는 이미 지워졌을 수 있다 — 15d-2 투표 삭제와 같은 흐름).
  static Future<void> _confirmDelete(BuildContext context, WidgetRef ref, FriendReview review) async {
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = ref.read(friendReviewListViewModelProvider(_written).notifier);
    Future<String?>? deleting;
    await showSafetySheet<void>(
      context,
      (_) => _DeleteConfirmSheet(nickname: review.nickname, onDelete: () => deleting = viewModel.delete(review.id)),
    );
    if (deleting == null) return; // "지우기" 를 누르지 않고 닫았다.
    final error = await deleting;
    _showToast(messenger, error ?? _deletedMessage, failed: error != null);
    // 카드가 빠졌으면(지움 · 그새 없어진 404) 그 친구는 다시 쓸 수 있어 기다리는 친구로 돌아온다.
    if (!context.mounted) return;
    if (ref.read(friendReviewListViewModelProvider(_written)).reviews.every((r) => r.id != review.id)) {
      ref.invalidate(writableFriendsProvider);
    }
  }

  /// 20e-4 "쓰기" → 그 친구 20b. 남겼으면 두 목록을 다시 읽는다 — 그 친구는 섹션에서 빠지고 카드로 들어온다.
  static Future<void> _write(BuildContext context, WidgetRef ref, ReviewTarget friend) async {
    final saved = await showFriendReviewComposeSheet(context, friend.profileId);
    if (saved != true || !context.mounted) return;
    ref.invalidate(writableFriendsProvider);
    ref.read(friendReviewListViewModelProvider(_written).notifier).refresh();
  }

  /// 20e-3 토스트(pen `W7HENj`, Toast `I8UOWm`): 가운데, 아래 24, 아이콘 꺼짐. 실패는 pen 에 없어 20b 실패 토스트와
  /// 같은 circle-alert 를 단다.
  static void _showToast(ScaffoldMessengerState messenger, String message, {required bool failed}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
        // 04-2 토스트와 같은 3초(pen 에 표시 시간이 없다).
        duration: const Duration(seconds: 3),
        content: Center(
          child: AppToast(
            leading: failed ? const Icon(AppIcons.circleAlert, size: 16, color: AppColors.onInk) : null,
            label: message,
          ),
        ),
      ));
  }
}

/// 20e-2 확인(pen `N701NC`, AlertSheet `D0TvG` 인스턴스 `UClUE`). 15d-2 투표 삭제(poll_sheets)와 같은 마스터 —
/// 위 모서리 24 · 그림자 #00000026 (0,-2) blur 16 · 손잡이 영역 위아래 12 · 내용 [8,16,32,16] 간격 16 ·
/// 버튼 사이 8(button-danger `ECxPJ` 56 · button-text `HKdWX` 48). 공통 승격은 백로그 39.
/// 지우는 중엔 "지우기" 안에 도는 표시(AppButton isLoading)만 두고, "취소" · 바깥 탭은 그대로 닫는다.
class _DeleteConfirmSheet extends StatefulWidget {
  const _DeleteConfirmSheet({required this.nickname, required this.onDelete});

  final String nickname;
  final Future<String?> Function() onDelete;

  @override
  State<_DeleteConfirmSheet> createState() => _DeleteConfirmSheetState();
}

class _DeleteConfirmSheetState extends State<_DeleteConfirmSheet> {
  bool _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    await widget.onDelete();
    // "취소" · 바깥 탭으로 이미 닫히는 중이면(애니메이션 동안 State 는 살아 있다) 또 닫지 않는다 — 밑의 20e 가
    // 닫힌다(PR 3 검토 필수 1, 20b · poll_sheets 와 같은 방어).
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        // pen D0TvG 그림자 — 토큰(AppElevation.card)과 방향이 달라 리터럴(poll_sheets · invite_friends_sheet 와 같다).
        boxShadow: AppElevation.top,
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서 시트가 화면보다 길어지면 스크롤한다.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 손잡이 n6pxDs 36×4 #DDDDDD — 모서리는 값표에 없어 같은 마스터 15d-2 와 같은 SheetHandle(r8).
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(child: SheetHandle()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // pen xd8je 20/700, 줄높이 속성 없음 · 렌더 29.
                    Text(_sheetTitle, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _sheetBody(widget.nickname),
                      // pen O7tR3q 14 / 보통 / muted / 1.55.
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // pen ECxPJ(HE8FZ) #E5E5E5 · 18/700 #C13515 = AppButton danger.
                    AppButton(
                      label: '지우기',
                      variant: AppButtonVariant.danger,
                      isLoading: _deleting,
                      onPressed: _delete,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // pen HKdWX · wICaR 48, 14/600 #C4224B = AppButton text.
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

/// 20e-4 섹션(pen `J3d8g8`, 간격 8): 제목 → 설명 → 친구 줄들, 그 아래 16 에 소제목 `Q3eosx` "내가 쓴 리뷰".
class _WaitingFriends extends StatelessWidget {
  const _WaitingFriends({required this.friends, required this.onWrite});

  final List<ReviewTarget> friends;
  final void Function(ReviewTarget friend) onWrite;

  @override
  Widget build(BuildContext context) {
    // pen qa34E · Q3eosx 16/700 ink.
    final heading = AppTypography.bodyStrong.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_waitingTitle, style: heading),
        const SizedBox(height: AppSpacing.xs),
        // pen AJ2hf 13 / muted / 1.5.
        Text(_waitingDescription, style: AppTypography.bodySmall.copyWith(fontSize: 13, height: 1.5, color: AppColors.muted)),
        for (final friend in friends) ...[
          const SizedBox(height: AppSpacing.xs),
          WritableFriendRow(friend: friend, onWrite: () => onWrite(friend)),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(_title, style: heading),
      ],
    );
  }
}

/// 친구 한 줄(pen `LJhYM`): 64 · 흰 바탕 r12 · 테두리 hairlineSoft 1 · 좌우 12 · 간격 12 —
/// 이니셜 40(`eNFmA`) → 닉네임 15/600 · 2 · 학교 → "쓰기". 테두리는 pen 처럼 여백을 먹지 않게 DecoratedBox 로 그린다.
class WritableFriendRow extends StatelessWidget {
  const WritableFriendRow({required this.friend, required this.onWrite, super.key});

  final ReviewTarget friend;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final university = friend.university;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: ConstrainedBox(
        // 높이는 최소값만 — 글자를 키우면 따라 늘어난다.
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              FriendReviewInitial(
                nickname: friend.nickname,
                size: 40,
                // pen HP0vI 원 #FFF0F2 · YAaTW 17/600 ink.
                style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 1),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(friend.nickname, style: AppTypography.bodyStrong.copyWith(fontSize: 15, color: AppColors.ink)),
                    if (university != null) ...[
                      const SizedBox(height: 2),
                      // pen YQMGC: 로고 16(HcLjG) · 간격 4 · ZD9sX 14 / body / 1.5.
                      SchoolLabel(university, style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _WriteButton(onPressed: onWrite),
            ],
          ),
        ),
      ),
    );
  }
}

/// "쓰기"(pen `LJhYM` 버튼): 36 · 좌우 14 · r10 · rausch · 14/600 흰 글자.
/// 눌림 효과가 버튼 안에서 그려지게 칸 안에 Material 을 둔다(COMMON §4-2).
class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text('쓰기', style: AppTypography.labelSmall.copyWith(color: AppColors.onPrimary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
