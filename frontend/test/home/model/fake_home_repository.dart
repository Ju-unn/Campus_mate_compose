import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository(this.summary);

  Result<HomeSummary> summary;

  /// 요약을 읽은 수 — 19 대기 화면이 여는 시각에 다시 읽는지 본다.
  int calls = 0;

  @override
  Future<Result<HomeSummary>> fetchSummary() async {
    calls++;
    return summary;
  }
}
