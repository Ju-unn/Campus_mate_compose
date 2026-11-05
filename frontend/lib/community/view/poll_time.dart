import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카드의 "지금" — 테스트가 고정한다(chatRoomNowProvider 와 같은 이음매).
final communityNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 카드 머리의 작성 시각(DESIGN §8.11 상대 시간). 한 주가 넘으면 날짜로 바꾼다 —
/// "43일 전" 은 셈을 시킨다. 기기 시계가 느려 미래 시각이 와도 "방금 전".
String relativeTimeLabel(AppLocalizations l10n, DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return l10n.communityTimeJustNow;
  if (gap.inHours < 1) return l10n.communityTimeMinutesAgo(minutes: gap.inMinutes);
  if (gap.inDays < 1) return l10n.communityTimeHoursAgo(hours: gap.inHours);
  if (gap.inDays < 2) return l10n.communityTimeYesterday; // pen 카드 `e45gI1` — "1일 전" 이 아니라 "어제"
  if (gap.inDays < 7) return l10n.communityTimeDaysAgo(days: gap.inDays);
  return l10n.commonDateMonthDay(month: at.month, day: at.day);
}
