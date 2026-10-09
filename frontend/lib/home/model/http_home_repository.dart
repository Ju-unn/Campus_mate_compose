import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/home_summary.dart';

/// [HomeRepository] 를 FastAPI `GET /home/summary` 로 구현한다.
class HttpHomeRepository implements HomeRepository {
  const HttpHomeRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<HomeSummary>> fetchSummary() => _api.send('GET', '/home/summary', (body) {
        final json = body as Map<String, dynamic>;
        final cohort = json['cohort'] as Map<String, dynamic>?;
        return HomeSummary(
          // ponytail: 서버에 아직 없는 값이라 목값을 채운다(사용자 결정 2026-09-26) — 실데이터가 생기면 교체.
          // 그림은 pen `b9Rask` · `Ch4h6` 과 같은 일러스트. 리뷰 띠(pen `L7wKi`) 모양은 그대로 둔다.
          presentPeopleImages: const ['assets/images/person-f1-blind-v1.png', 'assets/images/person-f4-blind-v1.png'],
          // ponytail: 출시 전 임시 값(개발자 본인 평가 1건, 사용자 결정 2026-10-09). 실제 스토어 평점·서버 집계가 생기면 서버 값으로 교체한다.
          reviewRating: 5.0,
          reviewCount: 1,
          deliveredCards: json['delivered_cards'] as int,
          signups: json['signups'] as int,
          conversationsStarted: json['conversations_started'] as int,
          campuses: (json['campuses'] as List<dynamic>).cast<String>(),
          profileCompletionPercent: json['profile_completion_percent'] as int,
          cohort: cohort == null
              ? null
              : CohortWait(
                  firstCardAt: DateTime.parse(cohort['first_card_at'] as String).toLocal(),
                  recruitCount: cohort['recruit_count'] as int,
                ),
        );
      });
}
