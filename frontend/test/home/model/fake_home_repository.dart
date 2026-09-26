import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository(this.summary);

  Result<HomeSummary> summary;

  @override
  Future<Result<HomeSummary>> fetchSummary() async => summary;
}
