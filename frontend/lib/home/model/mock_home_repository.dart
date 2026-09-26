import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// 지인 리뷰·참여 대학 지표가 서버에 생기기 전까지 쓰는 목데이터.
/// 숫자는 pen 시안 값이고, 대학 이름은 공개 저장소라 전부 지어낸 값이다.
class MockHomeRepository implements HomeRepository {
  const MockHomeRepository();

  @override
  Future<Result<HomeSummary>> fetchSummary() async {
    return const Success(
      HomeSummary(
        unreadNotifications: 2,
        presentPeopleImages: ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
        deliveredCards: 12480,
        signups: 862,
        conversationsStarted: 391,
        reviewRating: 4.8,
        reviewCount: 143,
        campuses: ['한빛대', '새솔대', '가람대', '푸른숲대'],
        profileCompletionPercent: 60,
      ),
    );
  }
}
