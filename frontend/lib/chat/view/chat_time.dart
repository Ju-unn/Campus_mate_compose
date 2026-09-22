import 'dart:async';

import 'package:flutter/widgets.dart';

/// 채팅 화면이 쓰는 시각 표기. `intl` 을 새로 들이지 않고 손으로 만든다 —
/// 필요한 모양이 네 가지뿐이고 전부 한국어 고정이다.
const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 말풍선 옆·목록 우측의 "오후 2:14".
String timeLabel(DateTime at) {
  final isAfternoon = at.hour >= 12;
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '${isAfternoon ? '오후' : '오전'} $hour12:${at.minute.toString().padLeft(2, '0')}';
}

/// 날짜 구분선의 "9월 14일 일요일"(pen `rSFNG`).
String dateLabel(DateTime at) =>
    '${at.month}월 ${at.day}일 ${_weekdays[at.weekday - 1]}요일';

/// 목록 한 줄의 우측. 오늘이면 시각, 아니면 날짜다 —
/// 사흘 전 대화에 시계만 떠 있으면 언제 이야기했는지 알 수 없다.
String listTimeLabel(DateTime at, DateTime now) {
  final isToday = at.year == now.year && at.month == now.month && at.day == now.day;
  return isToday ? timeLabel(at) : '${at.month}월 ${at.day}일';
}

/// 게이트 배너·시트의 "21:34:10". 하루가 넘어도 시 자리에 그대로 쌓는다(최대 48시간).
String countdownLabel(Duration remaining) {
  final total = remaining.isNegative ? Duration.zero : remaining;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(total.inHours)}:${two(total.inMinutes % 60)}:${two(total.inSeconds % 60)}';
}

/// 14h 배너처럼 큰 단위로만 말하는 자리의 "3시간" · "40분".
/// `inHours` 만 쓰면 한 시간이 안 남았을 때 **"0시간 뒤 종료돼요"** 가 뜬다(조각 5 리뷰 권고 8번).
String coarseRemainingLabel(Duration remaining) {
  final total = remaining.isNegative ? Duration.zero : remaining;
  if (total.inHours >= 1) {
    return '${total.inHours}시간';
  }
  // 1분도 안 남은 마지막 순간에 "0분" 이 되지 않게 바닥을 1분으로 잡는다.
  return '${total.inMinutes < 1 ? 1 : total.inMinutes}분';
}

/// 1초마다 남은 시간을 다시 그린다. **기준은 서버가 준 기한이고 계산은 기기 시계**로 한다
/// (조각 4 PR #67 과 같은 방식 — 시간대는 기기 것을 따른다).
class CountdownBuilder extends StatefulWidget {
  const CountdownBuilder({required this.deadlineAt, required this.builder, super.key});

  final DateTime deadlineAt;
  final Widget Function(BuildContext context, Duration remaining) builder;

  @override
  State<CountdownBuilder> createState() => _CountdownBuilderState();
}

class _CountdownBuilderState extends State<CountdownBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadlineAt.difference(DateTime.now());
    return widget.builder(context, remaining.isNegative ? Duration.zero : remaining);
  }
}
