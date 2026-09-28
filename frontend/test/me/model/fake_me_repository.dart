import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';

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

  @override
  Future<Result<MyProfile>> fetchProfile() async {
    calls++;
    return profile;
  }

  @override
  Future<Result<void>> updateProfile({String? bio, String? nickname, int? heightCm}) async {
    updates.add({'bio': ?bio, 'nickname': ?nickname, 'height_cm': ?heightCm});
    await holdUpdate?.future;
    return updateResult;
  }
}
