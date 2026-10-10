import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소. 몇 번 불렸는지도 센다("다시 시도" 확인용).
class FakeMeRepository implements MeRepository {
  FakeMeRepository(this.profile);

  Result<MyProfile> profile;
  int calls = 0;

  /// `updateProfile` 이 받은 칸들(보낸 칸만 담긴다 — 서버 본문과 같은 모양).
  final List<Map<String, Object>> updates = [];
  Result<void> updateResult = const Success(null);

  /// 채워 두면 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 모양 확인용).
  Completer<void>? holdUpdate;

  /// 채워 두면 프로필 읽기가 이 Completer 가 끝날 때까지 기다린다("잔액을 읽는 중" 모양 확인용).
  Completer<void>? holdFetch;

  @override
  Future<Result<MyProfile>> fetchProfile() async {
    calls++;
    await holdFetch?.future;
    return profile;
  }

  /// 15-4 가 읽는 내 카드. 채우지 않으면 실패로 돈다.
  Result<CardDetail> cardPreview = const FailureResult(UnknownFailure());
  int cardPreviewCalls = 0;

  @override
  Future<Result<CardDetail>> fetchCardPreview() async {
    cardPreviewCalls++;
    return cardPreview;
  }

  @override
  Future<Result<void>> updateProfile({String? bio, String? nickname, int? heightCm}) async {
    updates.add({'bio': ?bio, 'nickname': ?nickname, 'height_cm': ?heightCm});
    await holdUpdate?.future;
    return updateResult;
  }

  /// `savePhotos` 가 받은 칸 순서와 원본 번호.
  final List<(List<PhotoSlot>, int)> photoSaves = [];
  Result<void> savePhotosResult = const Success(null);

  /// 채워 두면 사진 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 모양 확인용).
  Completer<void>? holdSavePhotos;

  @override
  Future<Result<void>> savePhotos(List<PhotoSlot> slots, int avatarSource) async {
    photoSaves.add((slots, avatarSource));
    await holdSavePhotos?.future;
    return savePhotosResult;
  }
}
