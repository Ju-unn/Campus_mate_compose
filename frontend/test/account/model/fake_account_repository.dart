import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';

class FakeAccountRepository implements AccountRepository {
  Result<void> withdrawResult = const Success(null);
  Result<String?> kakaoIdResult = const Success('hong_gildong');
  int withdrawCalls = 0;
  int kakaoIdFetches = 0;

  /// 채워 두면 [withdraw] 가 끝나지 않고 기다린다 — 보내는 중 상태를 보려고.
  Completer<void>? holdWithdraw;

  @override
  Future<Result<void>> withdraw() async {
    withdrawCalls++;
    await holdWithdraw?.future;
    return withdrawResult;
  }

  @override
  Future<Result<String?>> fetchKakaoId() async {
    kakaoIdFetches++;
    return kakaoIdResult;
  }
}
