import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/home/model/data/cohort_wait.dart';
import 'package:campus_mate/home/model/data/home_people.dart';
import 'package:campus_mate/home/model/data/home_summary.dart';
import 'package:campus_mate/home/model/data/profile_completion_item.dart';
import 'package:campus_mate/home/model/repository/home_repository.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

/// [HomeRepository] 를 FastAPI `GET /home/summary` · `GET /home/people` 로 구현한다.
class HttpHomeRepository implements HomeRepository {
  const HttpHomeRepository(this._api, {this._platform});

  final ApiClient _api;

  /// 리뷰 띠가 읽을 스토어(아이폰 = ios, 안드로이드 = android). 웹 · 데스크톱은 null — 스토어가 없어 0명 상태.
  final TargetPlatform? _platform;

  /// 서버 `store_ratings` 의 칸 이름.
  String? get _store => switch (_platform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => null,
      };

  /// 내 스토어의 (별점, 평가 수). 평가 수 null = 그 스토어가 수를 주지 않는다(플레이 보고서). 못 읽으면 0명 상태 —
  /// 옛 칸 `store_rating` · `store_rating_count` 는 사람이 넣던 값이라 읽지 않는다(2026-11-16 사용자 「실제 스토어 값만」).
  (double, int?) _rating(Map<String, dynamic> json) {
    final ratings = json['store_ratings'];
    final mine = ratings is Map<String, dynamic> ? ratings[_store] : null;
    if (mine is! Map<String, dynamic>) return (0, 0);
    final rating = mine['rating'];
    final count = mine['count'];
    if (rating is! num || (count != null && count is! int)) return (0, 0);
    return (rating.toDouble(), count as int?);
  }

  @override
  Future<Result<HomeSummary>> fetchSummary() => _api.send('GET', '/home/summary', (body) {
        final json = body as Map<String, dynamic>;
        final cohort = json['cohort'] as Map<String, dynamic>?;
        final (rating, count) = _rating(json);
        return HomeSummary(
          reviewRating: rating,
          reviewCount: count,
          deliveredCards: json['delivered_cards'] as int,
          signups: json['signups'] as int,
          conversationsStarted: json['conversations_started'] as int,
          campuses: (json['campuses'] as List<dynamic>).cast<String>(),
          profileCompletionPercent: json['profile_completion_percent'] as int,
          // 옛 서버는 칸이 없다 — 빈 목록. 모르는 값은 건너뛴다(한 값 때문에 홈 전체가 실패하지 않게).
          profileCompletionMissing: [
            for (final code in json['profile_completion_missing'] as List<dynamic>? ?? const [])
              ?ProfileCompletionItem.tryParse(code),
          ],
          cohort: cohort == null
              ? null
              : CohortWait(
                  firstCardAt: DateTime.parse(cohort['first_card_at'] as String).toLocal(),
                  recruitCount: cohort['recruit_count'] as int,
                ),
          // 옛 서버는 칸이 없다 — 없거나 null 이면 빈 목록(배너 칸을 숨긴다).
          banners: [
            for (final banner in json['banners'] as List<dynamic>? ?? const [])
              HomeBanner.fromJson(banner as Map<String, dynamic>),
          ],
        );
      });

  @override
  Future<Result<HomePeople>> fetchPeople() => _api.send('GET', '/home/people', HomePeople.fromJson);
}
