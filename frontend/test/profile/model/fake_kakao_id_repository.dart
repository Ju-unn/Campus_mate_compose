import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/kakao_id_repository.dart';

class FakeKakaoIdRepository implements KakaoIdRepository {
  Result<void> nextResult = const Success(null);
  final List<String> submitted = [];

  /// 채워 두면 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 모양 확인용).
  Completer<void>? hold;

  @override
  Future<Result<void>> submit(String kakaoId) async {
    submitted.add(kakaoId);
    await hold?.future;
    return nextResult;
  }
}
