import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/matching/model/repository/card_repository.dart';
import 'package:flutter/foundation.dart';

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
  Future<void>? _stopping;
  // [start] 를 부른 뒤 [stop] 전인지. 아니면 [stop] 은 할 일이 없다 — signOut() 이 stop() 을 부른 뒤 세션이
  // 사라지면 main.dart 가 한 번 더 부르는데, 그때 기기에서 토큰을 읽어 지우려 하면 안 된다.
  bool _active = false;
  Timer? _discardRetry;
  Future<void>? _discarding;

  /// 겹쳐 불리면 진행 중인 시도를 같이 기다린다 — 로그인 직후와 게이트가 열리는 순간이
  /// 붙어 있으면 두 번째 호출이 첫 번째의 등록이 끝나기 전에 같은 토큰을 또 보낸다.
  Future<void> start() {
    _active = true;
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
    result.when(onSuccess: (_) => _remember(token), onFailure: (_) {});
  }

  void _remember(String token) {
    // 로그아웃이 끝난 뒤 매달렸다 늦게 성공한 등록이다 — 기억하면 앞 사람 토큰을 새 주인 것으로 읽어 버리기를 멈춘다.
    if (!_active) {
      return;
    }
    _registeredToken = token;
    // 이 토큰은 이제 새로 로그인한 사람 것이다 — 앞 사람 로그아웃 때 걸어 둔 버리기를 멈춘다.
    _discardRetry?.cancel();
    _discardRetry = null;
  }

  /// 로그아웃. 토큰을 남겨 두면 다음에 로그인한 사람에게 내 알림이 간다.
  /// 등록에 성공한 토큰을 모르는 경우에도 서버에는 남아 있을 수 있어 [_findToken] 으로 찾아 지운다(L1).
  /// 찾지 못했거나 서버에서 못 지웠으면 기기 토큰을 버린다([_discardOnDevice]).
  Future<void> stop() {
    // 진행 중인 로그아웃이 있으면 같이 기다린다 — [_active] 는 찾기가 끝나야 내려가므로 그 전에는 이 줄이 먼저 막는다.
    // 첫 stop 이 끝나기 전에 start() 가 끼면 그 사이 불린 stop 은 첫 번째와 합쳐진다 — 새 등록은 그 뒤의 stop(main.dart 뒷정리)이 지운다.
    final stopping = _stopping;
    if (stopping != null) {
      return stopping;
    }
    if (!_active) {
      return Future<void>.value();
    }
    return _stopping = _stopSession().whenComplete(() => _stopping = null);
  }

  Future<void> _stopSession() async {
    if (!await _removedFromServer()) {
      // 기다리지 않는다 — 느린 망에서 로그아웃 화면이 FCM 을 기다리며 멈추지 않게.
      _discarding = _discardOnDevice();
    }
  }

  /// 찾기와 서버 삭제가 [_deleteTimeout] 하나를 나눠 쓴다 — 로그아웃 최악 대기가 그 시간을 넘지 않게.
  Future<bool> _removedFromServer() async {
    final clock = Stopwatch()..start();
    final token = await _findToken();
    // 찾기가 끝났다. 이제부터 매달렸다 늦게 성공하는 등록은 기억하지 않는다([_register]).
    _active = false;
    _registeredToken = null;
    return token != null && await _deleted(token, within: _deleteTimeout - clock.elapsed);
  }

  /// 서버에서 지울 토큰. 못 찾으면 null — 로그아웃은 이 단계 때문에 멈추지 않는다.
  /// 등록(앱 http 쓰기 상한 30초)이나 FCM 이 매달리면 로그아웃이 그만큼 멈춘다 — [_deleteTimeout] 이 지나면 모르는 것으로 본다.
  Future<String?> _findToken() async {
    try {
      return await _tokenToDelete().timeout(_deleteTimeout);
    } on Object catch (error) {
      debugPrint('푸시 토큰 찾기 실패: ${error.runtimeType}');
      return null;
    }
  }

  /// 등록 응답으로 아는 토큰, 모르면 기기의 토큰. 서버에 남았을 수 있는 경우는 셋이다.
  /// ① 예전 세션이 등록했는데 그 뒤 알림 권한을 꺼서 [_start] 가 권한 단계에서 멈췄다 ② 서버는 받았는데 응답이 끊겼다
  /// ③ 등록 요청이 날아가는 중에 로그아웃했다. 서버에 없는 토큰을 지우라 해도 서버는 0행을 지우고 ok 를 준다.
  Future<String?> _tokenToDelete() async {
    // ③ 날아가는 요청이 서버에 닿은 뒤에 지워야 한다 — 먼저 지우면 요청이 로그아웃 뒤에 닿아 토큰이 남는다.
    // 등록 실패는 start() 를 부른 쪽이 본다 — 여기서는 끝나기만 기다린다. 구독은 [_start] 가 만들기를 끝낸 뒤에 끊는다.
    await _starting?.catchError((Object _) {});
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    return _registeredToken ?? await _messaging.getToken();
  }

  /// 서버에서 지웠는지. [within] 이 남아 있지 않으면 보내지 않고 실패로 본다.
  /// 앱 http 쓰기 상한(30초)은 로그아웃이 기다리기에 길다 — 매달린 DELETE 를 기다리면 로그아웃(signOut 의 finally)이 그만큼 늦는다.
  /// 끝나지 않으면 인터넷 없음과 같게 보고 실패로 돌려준다. 늦게 온 DELETE 는 서버가 주인까지 맞춰 지워 무해하다.
  Future<bool> _deleted(String token, {required Duration within}) async {
    if (within <= Duration.zero) {
      return false;
    }
    final result = await _repository
        .deletePushToken(token)
        .timeout(within, onTimeout: () => const FailureResult(NetworkFailure()));
    return result.when(onSuccess: (_) => true, onFailure: (_) => false);
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
