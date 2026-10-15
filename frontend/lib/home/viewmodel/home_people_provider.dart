import 'dart:async';

import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 못 받았거나 빈 목록(인원 부족)일 때 다시 받기까지 붙잡아 두는 시간 — 같은 세션의 재요청 간격 하한(요청 폭주 방지).
/// pen · DESIGN 값 아님, 검토 지시(10-16 "최소 5분 등 단순한 제한").
const Duration homePeopleRetryAfter = Duration(minutes: 5);

/// mosaic-rail 사람 칸. 요약([homeSummaryProvider])과 따로 읽는다 — 사람 칸이 실패해도 다른 블록은 그대로다.
/// 못 받으면 [HomePeople.none] 이고 레일은 기본 그림 칸으로 대신한다. 실패를 던지지 않는다(요약과 같은 이유 — Riverpod 3 재시도 타이머).
/// - 사람이 있게 받았으면 앱이 켜져 있는 동안(로그아웃하면 ProviderScope 가 새로 생긴다) 그대로 둔다.
/// - 못 받았거나 빈 목록이면 [homePeopleRetryAfter] 동안만 붙잡아 두고, 그 뒤 홈에 다시 들어올 때(홈을 떠나면 autoDispose) 다시 받는다.
///   빈 목록은 서버의 정상 응답이지만 가입자가 늘면 채워지므로 같은 규칙으로 다시 묻는다. 홈에 머무는 동안은 다시 받지 않는다.
final homePeopleProvider = FutureProvider.autoDispose<HomePeople>((ref) async {
  final result = await ref.watch(homeRepositoryProvider).fetchPeople();
  final people = result.when(onSuccess: (people) => people, onFailure: (_) => HomePeople.none);
  final keep = ref.keepAlive();
  if (people.isEmpty) {
    final release = Timer(homePeopleRetryAfter, keep.close);
    ref.onDispose(release.cancel);
  }
  return people;
});
