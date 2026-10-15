import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// 서로 다른 1×1 PNG 두 장(옛 임시 그림 두 장 자리) — 레일 사람 칸 기본값.
final HomePeople twoPeople = HomePeople.fromJson({
  'people': [
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ],
});

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository(this.summary, {Result<HomePeople>? people}) : people = people ?? Success(twoPeople);

  Result<HomeSummary> summary;

  /// 레일 사람 칸. 기본은 두 사람.
  Result<HomePeople> people;

  /// 사람 칸을 읽은 수 — 앱이 켜져 있는 동안 한 번만 읽는지 본다.
  int peopleCalls = 0;

  /// 사람 칸 응답을 붙잡아 두면(받는 중) 이 Completer 가 끝날 때 [people] 을 돌려준다.
  Completer<void>? holdPeople;

  /// 요약을 읽은 수 — 19 대기 화면이 여는 시각에 다시 읽는지 본다.
  int calls = 0;

  @override
  Future<Result<HomeSummary>> fetchSummary() async {
    calls++;
    return summary;
  }

  @override
  Future<Result<HomePeople>> fetchPeople() async {
    peopleCalls++;
    await holdPeople?.future;
    return people;
  }
}
