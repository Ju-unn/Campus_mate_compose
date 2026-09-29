import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_view_model.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 화면 문구 — pen NHcsP(값표 B §1).
const _tagQuestion = '어떤 장점이 있나요?'; // pen a9uYrP
const _commentQuestion = '한마디를 남겨주세요'; // pen rFK7Q
const _commentHint = '이 사람을 잘 보여주는 따뜻한 이야기를 적어주세요.'; // pen YgXMi
const _submitLabel = '리뷰 남기기'; // pen sXqh8
// pen 에 없는 문구(대장 09-29). 409 는 서버 FRIEND_REVIEW_ALREADY_WRITTEN 과 같은 말 — 열 때는 VM 이 문구 없이 알려 준다.
const _submittedMessage = '리뷰를 남겼어요';
const _alreadyWrittenMessage = '이미 리뷰를 남겼어요';

// 토큰에 없는 pen 값.
const double _sheetHeight = 664; // pen NHcsP 고정 높이
const double _headerHeight = 52; // pen eRud0
const double _avatarSize = 44; // pen Tb6Fe
const double _targetGap = 10; // pen AYwqQ gap
const double _chipHeight = 40; // pen dtjY5 등
const double _submitHeight = 52; // pen DkS7m

/// 테스트가 pen 크기를 재는 데 쓰는 자리 표시.
const Key friendReviewComposeHandleKey = ValueKey('friend-review-compose-handle');
const Key friendReviewCommentBoxKey = ValueKey('friend-review-comment-box');
const Key friendReviewSubmitKey = ValueKey('friend-review-submit');

/// 20b 를 지금 화면 위에 띄운다 — 온보딩 20 코드 확인 뒤(PR 4)가 부른다. 남기면 true, 아니면 null.
/// 보내는 중에 닫으면 저장돼도 null 이다 — 부르는 쪽은 null 을 "안 씀" 으로 가르지 말 것.
Future<bool?> showFriendReviewComposeSheet(BuildContext context, String revieweeId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // 화면이 664 보다 낮으면 손잡이가 상태 표시줄 밑으로 들어간다(검토 사소 1).
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // pen nIrPW 판 채움 #00000080 = 모달 딤 토큰.
    barrierColor: AppColors.scrim,
    builder: (_) => FriendReviewComposeSheet(revieweeId: revieweeId),
  );
}

/// 추천 가입 푸시 `/home/friend-reviews/write/:profileId` 가 쓰는 go_router 페이지(대장 Q1, 2026-09-29).
/// 홈 경로 아래에 달려 홈이 밑에 깔리고 그 위에 [showFriendReviewComposeSheet] 와 같은 시트가 뜬다.
class FriendReviewComposePage extends Page<bool> {
  const FriendReviewComposePage({required this.revieweeId, super.key});

  final String revieweeId;

  @override
  Route<bool> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<bool>(
      settings: this,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      modalBarrierColor: AppColors.scrim,
      builder: (_) => FriendReviewComposeSheet(revieweeId: revieweeId),
    );
  }
}

/// 20b 리뷰 쓰기 시트 본문(pen `NHcsP`). 664 고정, 손잡이만(제목 · 닫기 없음).
/// 태그가 서버 12종이라 pen(6개) 보다 길다 — 가운데만 스크롤하고 버튼은 바닥에 둔다(편차).
class FriendReviewComposeSheet extends ConsumerStatefulWidget {
  const FriendReviewComposeSheet({required this.revieweeId, super.key});

  final String revieweeId;

  @override
  ConsumerState<FriendReviewComposeSheet> createState() => _FriendReviewComposeSheetState();
}

class _FriendReviewComposeSheetState extends ConsumerState<FriendReviewComposeSheet> {
  final TextEditingController _comment = TextEditingController();

  /// 시트 안 토스트용. 시트가 화면 아래를 덮어 바깥(밑 화면) 토스트는 가려진다.
  final GlobalKey<ScaffoldMessengerState> _sheetMessenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = friendReviewComposeViewModelProvider(widget.revieweeId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    ref.listen(provider, _onChanged);
    final target = state.target;
    return Padding(
      // 키보드가 올라오면 그만큼 올린다 — 664 가 남은 높이보다 크면 시트가 줄고 가운데가 스크롤한다.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: _sheetHeight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          ),
          child: ScaffoldMessenger(
            key: _sheetMessenger,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: false,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // pen 여백 위 12 → 손잡이 줄 4 → 간격 16(스크롤 칸 위 여백).
                  const SizedBox(height: AppSpacing.sm),
                  const Center(child: _Handle()),
                  Expanded(
                    // pen 에 없는 상태(대장 4) — 대상을 읽는 동안은 가운데 도는 표시만.
                    child: target == null
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: _Form(
                              target: target,
                              state: state,
                              comment: _comment,
                              onToggle: viewModel.toggleTag,
                              onCommentChanged: viewModel.setComment,
                            ),
                          ),
                  ),
                ],
              ),
              // 바닥 고정 버튼. 시트 안 토스트가 이 위에 뜬다.
              bottomNavigationBar: target == null
                  ? null
                  : SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                        child: _SubmitButton(
                          isSubmitting: state.isSubmitting,
                          onPressed: state.canSubmit ? viewModel.submit : null,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// 열 때 409 · 실패와 남김 성공은 밑 화면에 토스트를 띄우고 닫는다. 보내기 실패는 시트 안에 띄우고 남는다.
  void _onChanged(FriendReviewComposeUiState? previous, FriendReviewComposeUiState next) {
    final outside = ScaffoldMessenger.of(context);
    // 뒤로 · 바깥 탭으로 이미 닫히는 중이면(애니메이션 동안 State 는 살아 있다) 또 닫지 않는다 — 밑 화면이 닫힌다.
    // 푸시로 연 홈 위 시트면 밑이 마지막 페이지라 go_router 가 깨진다(검토 필수 1, poll_sheets 와 같은 방어).
    void close([bool? result]) {
      if (ModalRoute.isCurrentOf(context) ?? false) {
        Navigator.of(context).pop(result);
      }
    }

    if (next.submitted && previous?.submitted != true) {
      showSafetyToast(outside, _submittedMessage);
      close(true);
      return;
    }
    if (next.alreadyWritten && previous?.alreadyWritten != true) {
      showSafetyToast(outside, _alreadyWrittenMessage, icon: AppIcons.circleAlert);
      close();
      return;
    }
    final loadError = next.loadError;
    if (loadError != null && previous?.loadError == null) {
      showSafetyToast(outside, loadError, icon: AppIcons.circleAlert);
      close();
      return;
    }
    final submitError = next.submitError;
    if (submitError != null && previous?.submitError == null) {
      showSafetyToast(_sheetMessenger.currentState!, submitError, icon: AppIcons.circleAlert);
    }
  }
}

/// 손잡이(pen `vH016`): 36×4 hairline r999. 조각 6 시트 · 14d 와 모서리 값이 다르다.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: friendReviewComposeHandleKey,
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(AppRadius.pill)),
    );
  }
}

/// 스크롤 칸(pen 간격 16): 머리 → 질문 1 → 태그 → 질문 2 → 한마디.
class _Form extends StatelessWidget {
  const _Form({
    required this.target,
    required this.state,
    required this.comment,
    required this.onToggle,
    required this.onCommentChanged,
  });

  final ReviewTarget target;
  final FriendReviewComposeUiState state;
  final TextEditingController comment;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onCommentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TargetHeader(nickname: target.nickname),
        const SizedBox(height: AppSpacing.md),
        const _Question(_tagQuestion),
        // 칩의 누르는 영역이 보이는 칩보다 위아래로 4 씩 크다 — 보이는 간격 16 을 맞추려고 4 를 뺀다.
        const SizedBox(height: AppSpacing.md - _chipTapInset),
        _TagGrid(selected: state.selected, onToggle: onToggle),
        const SizedBox(height: AppSpacing.md - _chipTapInset),
        const _Question(_commentQuestion),
        const SizedBox(height: AppSpacing.md),
        _CommentBox(controller: comment, length: state.comment.runes.length, onChanged: onCommentChanged),
      ],
    );
  }
}

/// 시트 머리(pen `eRud0` 52, 대상 묶음 `AYwqQ` 간격 10): 이니셜 44 · 이름 · 관계(간격 2). 관계 선택 칸은 pen 에 없다.
class _TargetHeader extends StatelessWidget {
  const _TargetHeader({required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // 높이는 최소값만 — 글자를 키우면 따라 늘어난다.
      constraints: const BoxConstraints(minHeight: _headerHeight),
      child: Row(
        children: [
          FriendReviewInitial(
            nickname: nickname,
            size: _avatarSize,
            // pen YAaTW 16/700 #222222. 줄높이 1 — 가운데 정렬이라 보이는 자리는 같다.
            style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700, height: 1),
          ),
          const SizedBox(width: _targetGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  // pen DcyWQ 17/600 lh1.5, 렌더 26.
                  style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 26 / 17),
                ),
                const SizedBox(height: 2),
                Text(
                  friendReviewRelationLabel,
                  // pen gN8D6 12/400 #6A6A6A lh1.5, 렌더 19.
                  style: AppTypography.caption.copyWith(color: AppColors.muted, height: 19 / 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 질문 줄(pen `a9uYrP` · `rFK7Q`): 17/600 ink lh1.5, 렌더 27.
class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 27 / 17));
  }
}

/// 누르는 영역 48(Material 버튼 padded)과 보이는 칩 40 의 차이 반쪽.
const double _chipTapInset = 4;

/// 태그 격자(pen `XpkFb`): 2열, 간격 8. 칩 누르는 영역이 48 이라 줄 사이 누르는 영역은 붙고 보이는 간격은 8 이다.
class _TagGrid extends StatelessWidget {
  const _TagGrid({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < friendReviewTags.length; i += 2)
          Row(
            children: [
              for (final tag in friendReviewTags.skip(i).take(2)) ...[
                if (tag != friendReviewTags[i]) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _TagChip(label: tag, isSelected: selected.contains(tag), onTap: () => onToggle(tag)),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// 태그 칩(pen `dtjY5` 선택 · `Et3XV` 안 선택): 40 r999 테두리 1, 14/600. 선택 = primaryWash · primary · primaryText,
/// 안 선택 = 흰 · hairline · body. 4번째는 VM 이 무시한다(대장 결정 4 — 최대 3, pen 에 표시 없음).
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      // 버튼이 자기 Material 을 가져 눌림 효과가 칩 모양 안에 그려진다(COMMON §4-2).
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: isSelected ? AppColors.primaryWash : AppColors.canvas,
          foregroundColor: isSelected ? AppColors.primaryText : AppColors.body,
          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.hairline),
          shape: const StadiumBorder(),
          // 보이는 칩 40, 누르는 영역은 padded 로 48(대장 7 — 44 이상).
          minimumSize: const Size.fromHeight(_chipHeight),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          // pen C7b3mk 등 14/600 lh1.5, 렌더 22.
          textStyle: AppTypography.labelSmall.copyWith(height: 22 / 14),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// 한마디 칸(pen `h3SkMd` = Textarea `Zhq9p`): 104 · surfaceSoft r8 outline 1 · 여백 12, 카운터 왼쪽 아래.
/// 신고 시트 기타 메모(`_NoteBox`)와 같은 마스터라 같은 모양으로 그린다. 상한만 100(대장 1, pen "0 / 80" 은 옛 예시).
class _CommentBox extends StatelessWidget {
  const _CommentBox({required this.controller, required this.length, required this.onChanged});

  final TextEditingController controller;
  final int length;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: friendReviewCommentBoxKey,
      // 높이는 최소값만 — 여러 줄을 쓰거나 글자를 키우면 상자가 늘어난다.
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
      // 테두리를 decoration 에 두면 Container 가 테두리 두께만큼 여백을 더한다 — pen 여백 12 는 바깥선 기준이다.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLines: null,
            // 100자는 코드포인트로 센다 — 서버 len() 이 그렇게 센다(신고 메모 · 입력 바와 같은 formatter).
            inputFormatters: [codePointLimitFormatter(friendReviewCommentMaxLength)],
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink, height: 1.5),
            decoration: InputDecoration.collapsed(
              hintText: _commentHint,
              // pen YgXMi 14/400 #6A6A6A lh1.5.
              hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.5),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$length / $friendReviewCommentMaxLength',
            // pen BCwSP 12/400 #6A6A6A lh1.5.
            style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 제출(pen `DkS7m`): 328×52 primary r8, 18/700 흰색. 조각 6 시트 버튼과 모양이 같지만 보내는 중 표시가 필요해 따로 둔다.
/// pen 에 없는 상태(대장 4): 꺼짐 = primaryDisabled 바탕 · disabled 글자, 보내는 중 = 평상시 색 위 흰 도는 표시.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.isSubmitting, required this.onPressed});

  final bool isSubmitting;

  /// null 이면 꺼짐(태그 0개). 보내는 중에도 VM 이 null 을 준다.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || isSubmitting;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: isSubmitting ? _submitLabel : null,
      // 눌림 효과가 시트와 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        key: friendReviewSubmitKey,
        color: enabled ? AppColors.primary : AppColors.primaryDisabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          // 높이는 최소값만 — 글자를 키우면 버튼이 따라 커진다.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _submitHeight),
            // heightFactor 1 — 바닥 칸(bottomNavigationBar)은 높이를 넉넉히 주니 Center 가 다 차지하지 않게 한다.
            child: Center(
              heightFactor: 1,
              child: isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Text(
                        _submitLabel,
                        textAlign: TextAlign.center,
                        // pen sXqh8 18/700 lh1.5, 렌더 28.
                        style: AppTypography.label.copyWith(
                          color: enabled ? AppColors.onPrimary : AppColors.disabled,
                          height: 28 / 18,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
