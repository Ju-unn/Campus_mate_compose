import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_list_frame.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/safety/model/data/report_target.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';

// 화면 문구는 문구 파일(ARB)에 있다 — pen HWM2G(값표 B §2): 제목 kyDqZ · 안내 OHJVi · 빈 상태 계획서 A6.
// "신고했어요. 운영팀이 확인할게요" 는 pen 에 없는 문구(대장 09-29). 리뷰 신고는 차단하지 않아(P1) 기존 신고 문구("차단되어…")를 쓰지 않는다.

/// 20c 받은 리뷰(pen `HWM2G`). 15 "친구들이 본 나" 에서 push 로, 새 리뷰 푸시에서 `go` 로 연다.
/// 받은 사람은 지울 수 없고 신고만 한다 — 신고해도 차단하지 않고 카드는 그대로 둔다(P1 · 결정 3).
class ReceivedReviewsScreen extends StatelessWidget {
  const ReceivedReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FriendReviewListFrame(
      title: context.l10n.friendReviewReceivedTitle,
      notice: context.l10n.friendReviewReceivedNotice,
      source: FriendReviewListSource.received,
      cardBuilder: (context, review) => FriendReviewCard(review: review, onReport: () => _report(context, review.id)),
      // pen 에 없는 상태(대장 4) — 16f 차단 목록 빈 상태(`KLSeQ`)와 같은 모양, 설명 없이 제목까지.
      empty: FriendReviewEmpty(mascot: 'assets/images/mascot-female.png', title: context.l10n.friendReviewReceivedEmpty),
    );
  }

  /// 기존 신고 시트를 그대로 띄운다. 어느 결과든 이 화면에 남고 카드도 그대로다 — `reportThenLeave` 는
  /// 차단을 전제로 대화 목록으로 떠나서 쓰지 않는다. 신고됨만 문구를 바꾸고 나머지는 시트가 준 문구 그대로.
  static Future<void> _report(BuildContext context, String reviewId) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n; // 시트가 닫힌 뒤 화면이 없어져도 토스트는 띄운다 — 글자는 미리 잡는다.
    final result = await showReportSheet(context, ReportTarget.friendReview(reviewId));
    if (result == null) return;
    final failure = result.failure;
    showSafetyToast(messenger, failure == null ? l10n.commonReportedNotice : failureText(l10n, failure));
  }
}
