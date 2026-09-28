import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16e 가 읽는 계정 정보. 실패도 [Result] 그대로 — 던지면 Riverpod 3 이 재시도 타이머를 건다(화면 15 와 같다).
/// autoDispose: 화면을 떠나면 실명이 메모리에서 내려가고, 16e-1 에서 돌아오면 새로 읽는다.
final accountInfoProvider = FutureProvider.autoDispose<Result<AccountInfo>>((ref) {
  return ref.watch(accountRepositoryProvider).fetchAccount();
});
