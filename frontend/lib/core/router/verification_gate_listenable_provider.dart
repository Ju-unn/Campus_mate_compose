import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 전체가 같은 게이트 캐시를 보게 한다.
///
/// main.dart 는 이것을 라우터의 `refreshListenable` 에 걸고,
/// 3b·3c ViewModel 은 인증이 끝난 순간 `refresh()` 를 불러 라우터를 다시 평가시킨다.
/// 이 통로가 없으면 인증을 마친 사용자가 앱을 다시 켤 때까지 그 화면에 갇힌다.
final verificationGateListenableProvider = Provider<VerificationGateListenable>((ref) {
  final listenable = VerificationGateListenable(ref.read(verificationGateRepositoryProvider));
  ref.onDispose(listenable.dispose);
  return listenable;
});
