import 'dart:async';

import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';

final sampleAccount = AccountInfo(
  loginProvider: 'kakao',
  birthYear: 2003,
  university: '서울대학교',
  joinedAt: DateTime.utc(2026, 9, 1, 10),
  kakaoId: 'fox_rain',
);

class FakeAccountRepository implements AccountRepository {
  Result<AccountInfo> accountResult = Success(sampleAccount);
  Result<void> withdrawResult = const Success(null);
  Result<String?> kakaoIdResult = const Success('hong_gildong');
  int accountFetches = 0;
  int withdrawCalls = 0;

  /// [withdraw] 가 받은 애플 코드(부를 때마다 하나).
  final List<String?> withdrawAppleCodes = [];
  int kakaoIdFetches = 0;

  /// 채워 두면 [withdraw] 가 끝나지 않고 기다린다 — 보내는 중 상태를 보려고.
  Completer<void>? holdWithdraw;

  @override
  Future<Result<AccountInfo>> fetchAccount() async {
    accountFetches++;
    return accountResult;
  }

  @override
  Future<Result<void>> withdraw({String? appleAuthorizationCode}) async {
    withdrawCalls++;
    withdrawAppleCodes.add(appleAuthorizationCode);
    await holdWithdraw?.future;
    return withdrawResult;
  }

  @override
  Future<Result<String?>> fetchKakaoId() async {
    kakaoIdFetches++;
    return kakaoIdResult;
  }
}
