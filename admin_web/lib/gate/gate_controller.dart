import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final gateProvider = AsyncNotifierProvider<GateController, GateStage>(GateController.new);

/// 지금 어느 관문 단계인지 판정한다. 로그인 상태가 바뀌면([AdminAuth.changes]) 처음부터 다시 판정한다.
class GateController extends AsyncNotifier<GateStage> {
  @override
  Future<GateStage> build() async {
    final config = ref.watch(adminConfigProvider);
    if (!config.isComplete) return ConfigMissing(config.missingKeys());
    // await 전에 모두 읽는다 — 판정 중에 다시 판정이 시작되면 이 ref 는 더 쓸 수 없다.
    final auth = ref.watch(adminAuthProvider);
    final api = ref.watch(adminApiProvider);
    final subscription = auth.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    try {
      return await _resolve(auth, api);
    } on Exception {
      return const Unavailable();
    }
  }

  /// 연결 안 됨 화면의 "다시 시도"
  void retry() => ref.invalidateSelf();

  /// 2단계 필요 화면의 단추 — 가진 TOTP 로 입력, 없으면 등록.
  void startMfa(MfaRequired stage) {
    final factorId = stage.factorId;
    state = AsyncData(factorId == null ? const EnrollMfa() : VerifyMfa(factorId));
  }

  static Future<GateStage> _resolve(AdminAuth auth, AdminApi api) async {
    if (!auth.hasSession) return const SignedOut();
    final mfa = await auth.mfaState();
    final factorId = mfa.factorId;
    if (!mfa.aal2) return factorId == null ? const EnrollMfa() : VerifyMfa(factorId);
    final me = await api.me();
    if (me.isSuccess) return Ready(auth.email ?? '');
    if (me.statusCode == 401) {
      // 서버가 토큰을 거절했다 — 들고 있는 세션을 버려야 다시 로그인할 수 있다(안 버리면 이 판정을 되풀이한다).
      await auth.signOut();
      return const SignedOut();
    }
    if (me.statusCode == 403 && me.reason == AdminReason.mfaRequired) return MfaRequired(factorId);
    if (me.statusCode == 403) return const NotAdmin();
    return const Unavailable();
  }
}
