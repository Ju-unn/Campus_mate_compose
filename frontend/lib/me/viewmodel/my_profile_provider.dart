import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 화면 15 가 읽는 내 프로필. 실패도 [Result] 그대로 돌려준다 — 화면이 실패 상태를 그려야 하고,
/// 던지면 Riverpod 3 이 알아서 재시도 타이머를 건다.
final myProfileProvider = FutureProvider<Result<MyProfile>>((ref) {
  return ref.watch(meRepositoryProvider).fetchProfile();
});
