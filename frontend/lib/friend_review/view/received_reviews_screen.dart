import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/friend_review_list_frame.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';

// 화면 문구 — pen HWM2G(값표 B §2).
const _title = '받은 리뷰'; // pen kyDqZ
const _notice = '받은 리뷰는 직접 삭제할 수 없어요. 부적절한 내용은 신고해주세요.'; // pen OHJVi
// pen 에 없는 문구(대장 09-29). 리뷰 신고는 차단하지 않아(P1) 기존 신고 문구("차단되어…")를 쓰지 않는다.
const _reportedMessage = '신고했어요. 운영팀이 확인할게요';
const _emptyTitle = '아직 받은 리뷰가 없어요'; // 계획서 A6

/// 20c 받은 리뷰(pen `HWM2G`). 15 "친구들이 본 나" 에서 push 로, 새 리뷰 푸시에서 `go` 로 연다.
/// 받은 사람은 지울 수 없고 신고만 한다 — 신고해도 차단하지 않고 카드는 그대로 둔다(P1 · 결정 3).
class ReceivedReviewsScreen extends StatelessWidget {
  const ReceivedReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FriendReviewListFrame(
      title: _title,
      notice: _notice,
      source: FriendReviewListSource.received,
      cardBuilder: (context, review) => FriendReviewCard(review: review, onReport: () => _report(context, review.id)),
      // pen 에 없는 상태(대장 4) — 16f 차단 목록 빈 상태(`KLSeQ`)와 같은 모양, 설명 없이 제목까지.
      empty: const FriendReviewEmpty(mascot: 'assets/images/mascot-female.png', title: _emptyTitle),
    );
  }

  /// 기존 신고 시트를 그대로 띄운다. 어느 결과든 이 화면에 남고 카드도 그대로다 — `reportThenLeave` 는
  /// 차단을 전제로 대화 목록으로 떠나서 쓰지 않는다. 신고됨만 문구를 바꾸고 나머지는 시트가 준 문구 그대로.
  static Future<void> _report(BuildContext context, String reviewId) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showReportSheet(context, ReportTarget.friendReview(reviewId));
    if (result == null) return;
    showSafetyToast(messenger, result.outcome == ReportOutcome.reported ? _reportedMessage : result.message);
  }
}
