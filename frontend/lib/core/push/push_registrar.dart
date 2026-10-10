import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/matching/model/card_repository.dart';

/// 토큰 등록·해제와 갱신 구독. 로그인한 뒤 [start], 로그아웃할 때 [stop].
///
/// [start] 는 여러 번 불러도 안전하다 — 새로 가입한 사용자는 학생 인증·학과 입력을
/// 마치기 전이라 서버가 등록을 403 으로 막는데, 그때는 토큰을 기억하지 않으므로
/// 인증 게이트가 열린 뒤 다시 부르면 그때 등록된다(2026-09-23 실기기 테스트).
class PushRegistrar {
  PushRegistrar(
    this._messaging,
    this._repository, {
    this._retryDelay = const Duration(minutes: 1),
    this._deleteTimeout = const Duration(seconds: 5),
  });

  final PushMessaging _messaging;
  final CardRepository _repository;
  final Duration _retryDelay;
  final Duration _deleteTimeout;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;
  Future<void>? _starting;
  Timer? _discardRetry;
  Future<void>? _discarding;

  /// 겹쳐 불리면 진행 중인 시도를 같이 기다린다 — 로그인 직후와 게이트가 열리는 순간이
  /// 붙어 있으면 두 번째 호출이 첫 번째의 등록이 끝나기 전에 같은 토큰을 또 보낸다.
  Future<void> start() {
    if (_registeredToken != null) {
      return Future<void>.value();
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (!await _messaging.requestPermission()) {
      // 거부해도 앱은 그대로 쓴다. 알림 설정 화면(16d)에서 다시 켤 수 있다.
      return;
    }
    // 앞 사람의 기기 토큰 버리기가 진행 중이면 끝난 뒤에 받는다 — 곧 버려질 토큰을 새 주인으로 등록하지 않게.
    await _discarding;
    final token = await _messaging.getToken();
    if (token != null) {
      await _register(token);
    }
    _refreshSubscription ??= _messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    final result = await _repository.registerPushToken(token);
    // 서버가 받아 준 토큰만 기억한다 — 실패한 것을 기억하면 다시 시도하지 않고,
    // [stop] 이 서버에 없는 토큰을 지우려 한다.
    result.when(
      onSuccess: (_) {
        _registeredToken = token;
        // 이 토큰은 이제 새로 로그인한 사람 것이다 — 앞 사람 로그아웃 때 걸어 둔 버리기를 멈춘다.
        _discardRetry?.cancel();
        _discardRetry = null;
      },
      onFailure: (_) {},
    );
  }

  /// 로그아웃. 토큰을 남겨 두면 다음에 로그인한 사람에게 내 알림이 간다.
  Future<void> stop() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) {
      return;
    }
    // 앱 http 에는 타임아웃이 없다 — 매달린 DELETE 를 기다리면 로그아웃(signOut 의 finally)까지 못 간다.
    // 끝나지 않으면 인터넷 없음과 같게 보고 기기 토큰을 버린다. 늦게 온 DELETE 는 서버가 주인까지 맞춰 지워 무해하다.
    final deleted = await _repository
        .deletePushToken(token)
        .timeout(_deleteTimeout, onTimeout: () => const FailureResult(NetworkFailure()));
    if (deleted.when(onSuccess: (_) => false, onFailure: (_) => true)) {
      // 기다리지 않는다 — 느린 망에서 로그아웃 화면이 FCM 을 기다리며 멈추지 않게.
      _discarding = _discardOnDevice();
    }
  }

  /// 서버에서 못 지웠다(인터넷 없음 · 세션이 이미 끝남, A15). 로그아웃 뒤라 서버 삭제는 다시 보낼 수 없다 —
  /// 대신 이 기기의 FCM 토큰을 버린다. 로그인이 필요 없고, 서버가 그 토큰으로 보내면 FCM 404 를 받아
  /// 행을 지운다(`backend/app/cards/push.py` "dead"). 이것도 인터넷이 필요해 실패하면 [_retryDelay] 마다 다시 한다.
  /// ponytail: 앱을 끄면 다시 하기도 끝난다 — 그 토큰은 다음 로그인이 같은 토큰을 등록할 때 새 주인에게 넘어간다.
  Future<void> _discardOnDevice() async {
    _discardRetry?.cancel();
    _discardRetry = null;
    try {
      await _messaging.deleteToken();
    } on Exception {
      _discardRetry = Timer(_retryDelay, () => _discarding = _discardOnDevice());
    }
  }
}
