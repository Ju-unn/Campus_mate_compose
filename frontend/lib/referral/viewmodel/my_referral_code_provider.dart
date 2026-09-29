import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16i 친구 초대 시트가 읽는 내 추천 코드. 실패도 [Result] 그대로 — 던지면 Riverpod 3 이 재시도 타이머를 건다(16e 와 같다).
/// autoDispose: 시트를 닫으면 내려가고, 못 읽었던 사람은 다시 열 때 새로 읽는다.
final myReferralCodeProvider = FutureProvider.autoDispose<Result<String>>((ref) {
  return ref.watch(referralRepositoryProvider).myCode();
});
