import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository.dart';

class FakeAvatarRepository implements AvatarRepository {
  /// 등록(`generateAvatar`)이 돌려줄 값. 서버는 이제 202 `pending` 을 준다.
  Result<AvatarGenerationOutcome> nextResult = const Success(AvatarPending());

  /// 상태 조회가 차례로 돌려줄 값. 비어 있으면 [nextResult] 를 쓴다 —
  /// pending → ready 전이를 흉내 낼 때만 채운다(마지막 값은 계속 돌려준다).
  final List<Result<AvatarGenerationOutcome>> statusResults = [];

  int generateCount = 0;
  int statusCount = 0;

  /// 채워 두면 등록이 여기서 멈춘다 — "올리기는 끝났는데 등록은 아직" 인 순간을 테스트가 잡을 때만 쓴다.
  Completer<void>? generateGate;

  @override
  Future<Result<AvatarGenerationOutcome>> generateAvatar() async {
    generateCount++;
    await generateGate?.future;
    return nextResult;
  }

  @override
  Future<Result<AvatarGenerationOutcome>> fetchAvatarStatus() async {
    statusCount++;
    if (statusResults.isEmpty) {
      return nextResult;
    }
    return statusResults.length == 1 ? statusResults.first : statusResults.removeAt(0);
  }
}
