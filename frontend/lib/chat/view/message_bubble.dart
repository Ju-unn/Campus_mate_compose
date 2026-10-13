import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 스크린 리더가 '1' 대신 읽는 말(pen `RvjRp` 접근성 메모). 숫자만 읽히면 뜻이 안 전해진다.
const String unreadByPartnerLabel = '상대가 아직 읽지 않았어요';

/// pen `UVex8`(Bubble Row) 의 '1' ↔ 말풍선 간격. 간격 토큰(4 · 8) 사이의 pen 값이다.
const double _unreadMarkGap = 6;

/// 말풍선 한 개(pen `fm3rk` 상대 / `RvjRp` 나). 시각은 **말풍선 밖 아래**에 둔다(DESIGN §8.6).
/// 시스템 줄은 여기로 오지 않는다 — `SystemMessage` 가 따로 그린다.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    this.isUnread = false,
    this.showTime = true,
    this.onLongPress,
    super.key,
  });

  final Message message;
  final bool isMine;

  /// 상대가 아직 안 읽은 내 줄(카톡식, 사용자 결정 10-13) — 말풍선 왼쪽에 '1'(pen `Qs5As`).
  /// 상대가 읽으면 다음 그림에서 바로 사라진다(애니메이션 없음, pen 메모). 판단은 `ChatRoomUiState.isUnreadByPartner`.
  final bool isUnread;

  /// 같은 사람이 같은 분에 보낸 연속 줄은 마지막 줄에만 시각을 둔다(pen `mmtWq` 같은 분 묶음).
  final bool showTime;

  /// 말풍선을 길게 눌렀을 때(조각 6 메시지 신고). 상대 텍스트 말풍선에만 넘긴다 — 내 것에는 메뉴가 없다.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isUnread) _withUnreadMark(context) else _pressable(context),
          if (showTime) ...[
            const SizedBox(height: 2),
            Text(
              timeLabel(message.createdAt),
              style: AppTypography.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pressable(BuildContext context) =>
      GestureDetector(onLongPress: onLongPress, child: _bubble(context));

  /// pen `UVex8`: 가로 간격 6 · 아래 맞춤 [읽음 표시, 말풍선]. 한 줄로 합쳐 읽혀서
  /// 스크린 리더는 "상대가 아직 읽지 않았어요" 와 말풍선 글을 같이 읽고 '1' 글자는 읽지 않는다.
  Widget _withUnreadMark(BuildContext context) {
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: _unreadMarkGap,
        children: [
          // pen Qs5As: Pretendard 12/600 `$colors.primary-text` #C4224B(흰 바탕 5.71:1). 줄높이 속성은 없다.
          Text(
            '1',
            semanticsLabel: unreadByPartnerLabel,
            style: AppTypography.caption.copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w600),
          ),
          // 글자를 키워도 '1' 이 밀려 넘치지 않게 말풍선이 남은 폭 안에서 줄어든다.
          Flexible(child: _pressable(context)),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    return ConstrainedBox(
      // 화면의 78% 를 넘기지 않는다 — 넘기면 누구 말인지 구분이 사라진다.
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : AppColors.surfaceSoft,
          // 꼬리 쪽 모서리 하나만 작게 깎아 방향을 만든다(pen `k7IEF`·`AIqtT`).
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.md),
            topRight: const Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(isMine ? AppRadius.md : 4),
            bottomRight: Radius.circular(isMine ? 4 : AppRadius.md),
          ),
        ),
        child: Text(
          message.body,
          style: isMine
              ? AppTypography.body
                  .copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w500)
              : AppTypography.body.copyWith(color: AppColors.ink),
        ),
      ),
    );
  }
}
