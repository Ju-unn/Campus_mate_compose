import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/community/model/data/poll_vote_notice.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// 투표 뒤 알림의 글자 — 하트를 받았으면 보상 문구(pen 에 문구가 있으면 그것으로 바꾼다), 실패면 그 이유의 글자.
String pollVoteNoticeText(AppLocalizations l10n, PollVoteNotice notice) => switch (notice.failure) {
      null => l10n.communityVoteReward,
      final failure => failureText(l10n, failure),
    };

/// 띄운 토스트. `closed` 가 끝나면 화면에서 사라졌다.
typedef PollToast = ScaffoldFeatureController<SnackBar, SnackBarClosedReason>;

/// 15d · 17c 가 같이 쓰는 토스트(pen Toast `I8UOWm`). 뜨고 사라지는 시간은 SnackBar 에 맡긴다 — 두 화면에
/// 타이머를 따로 두지 않는다. 보상(15d-3 `NDZnK`)은 글자만 — 재화 하트는 Lucide 로 그리지 않는다(DESIGN §8.10).
/// "삭제했어요"(15d-5 `SKQgV` · 토스트 `VuCcc` 아이콘 끔)도 글자만. 나머지(오류)는 경고 아이콘.
///
/// 띄운 토스트를 돌려준다 — 15d 는 토스트가 떠 있는 동안 "질문하기" 알약을 숨긴다(17A-2 `O8hjge`).
/// [bottomInset] 은 화면 아래에 붙은 줄의 높이 — 17c 는 댓글 입력줄(80) 위에 띄운다.
PollToast showPollToast(BuildContext context, String message, {double bottomInset = 0}) {
  final l10n = context.l10n;
  final textOnly = message == l10n.communityVoteReward || message == l10n.communityDeleted;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // pen `NDZnK`: 하단 내비 위 16. SnackBar 기본(바깥 아래 10 + 안쪽 위아래 14)을 걷어 낸다.
      padding: EdgeInsets.zero,
      margin: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md + bottomInset),
      content: Center(
        child: AppToast(
          leading: textOnly ? null : const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: message,
        ),
      ),
    ));
}
