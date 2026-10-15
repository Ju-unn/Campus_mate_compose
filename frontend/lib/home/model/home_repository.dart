import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// 09b 메인이 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class HomeRepository {
  Future<Result<HomeSummary>> fetchSummary();

  /// mosaic-rail 사람 칸. 요약과 따로 부른다 — 이쪽이 늦거나 실패해도 다른 블록은 그려진다.
  Future<Result<HomePeople>> fetchPeople();
}
