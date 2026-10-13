import 'dart:async';

import 'package:campus_mate/account/model/apple_withdrawal_code.dart';

/// 애플 창 없이 탈퇴 흐름을 시험하는 가짜. 기본은 애플 사용자가 아닌 사람(코드 없음)이다.
class FakeAppleWithdrawalCode implements AppleWithdrawalCode {
  FakeAppleWithdrawalCode([this.code]);

  String? code;
  int obtainCalls = 0;

  /// 채워 두면 [obtain] 이 끝나지 않고 기다린다 — 애플 창이 떠 있는 동안을 흉내 낸다.
  Completer<void>? hold;

  @override
  Future<String?> obtain() async {
    obtainCalls++;
    await hold?.future;
    return code;
  }
}
