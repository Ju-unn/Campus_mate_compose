import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/safety/model/partner_profile.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeSafetyRepository implements SafetyRepository {
  Result<void> reportResult = const Success(null);
  Result<void> blockResult = const Success(null);
  Result<List<BlockedUser>> blocks = const Success([]);
  Result<void> unblockResult = const Success(null);

  final List<({Map<String, String> target, ReportReason reason, String? note})> reports = [];
  final List<String> blocked = [];
  final List<String> unblocked = [];
  int fetchCount = 0;

  /// 채워 두면 해당 호출이 이것이 끝날 때까지 멈춘다 — 진행 중에 한 번 더 누르는 상황용.
  Completer<void>? holdReport;
  Completer<void>? holdFetch;
  Completer<void>? holdUnblock;

  @override
  Future<Result<void>> report({
    required ReportTarget target,
    required ReportReason reason,
    String? note,
  }) async {
    reports.add((target: target.toJson(), reason: reason, note: note));
    await holdReport?.future;
    return reportResult;
  }

  @override
  Future<Result<void>> block(String profileId) async {
    blocked.add(profileId);
    return blockResult;
  }

  @override
  Future<Result<List<BlockedUser>>> fetchBlocks() async {
    fetchCount += 1;
    await holdFetch?.future;
    return blocks;
  }

  @override
  Future<Result<void>> unblock(String profileId) async {
    unblocked.add(profileId);
    await holdUnblock?.future;
    return unblockResult;
  }

  Result<PartnerProfile> partnerProfile = Success(partnerProfileFixture());
  final List<String> partnerProfileRequests = [];
  Completer<void>? holdPartnerProfile;

  @override
  Future<Result<PartnerProfile>> fetchPartnerProfile(String profileId) async {
    partnerProfileRequests.add(profileId);
    await holdPartnerProfile?.future;
    return partnerProfile;
  }
}

/// 14c 상대 프로필. 기본은 게이트 전(카톡 · 실사진 없음)이고, [photoUrls] 를 주면 게이트 뒤다.
/// [idealNote] 는 "이런 사람이 좋아요" 글이다. 기본은 없다.
PartnerProfile partnerProfileFixture({
  String matchId = 'm-1',
  String profileId = 'p2',
  String nickname = '여우비',
  String? kakaoId,
  List<String>? photoUrls,
  String? idealNote,
}) {
  return PartnerProfile(
    matchId: matchId,
    detail: CardDetail(
      cardId: matchId,
      profile: CardProfile(profileId: profileId, nickname: nickname, age: 23),
      survey: List.filled(9, 0.5),
      animalType: AnimalType.cat,
      impressionType: ImpressionType.chic,
      religion: Religion.none,
      isSmoker: false,
      interests: const ['등산'],
      myTraits: const ['유머러스'],
      idealTraits: const ['다정한'],
      idealNote: idealNote,
    ),
    kakaoId: kakaoId,
    photoUrls: photoUrls,
  );
}

BlockedUser blockedUserFixture({String profileId = 'p2', String nickname = '여우비'}) {
  return BlockedUser(
    profileId: profileId,
    nickname: nickname,
    blockedAt: DateTime(2026, 9, 27, 14),
  );
}
