import 'dart:async';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/kakao_login_gateway.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/in_app_heart_store_gateway.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:campus_mate/common/widgets/keyboard_dismiss_on_tap.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/auth/session_scope.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/open_draft_store.dart';
import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/core/lifecycle/resume_refresh.dart';
import 'package:campus_mate/core/push/firebase_bootstrap.dart';
import 'package:campus_mate/core/push/local_system_notifications.dart';
import 'package:campus_mate/core/push/push_messaging.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/router/splash_hold.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/tour/view/app_tour_host.dart';
import 'package:campus_mate/tour/viewmodel/app_tour_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 안드로이드는 google-services 플러그인이 넣어 준 리소스를 읽으므로 options 를 코드에 적지 않는다
  // (firebase_options.dart 를 만들지 않는 이유 — flutterfire CLI 를 새로 들이지 않는다).
  // 실패해도(iOS 에 GoogleService-Info.plist 가 없을 때) 앱은 푸시 없이 계속 뜬다 — 아래 pushMessagingProvider 덮어쓰기.
  final firebaseReady = await initializeFirebase();
  await SupabaseInitializer.run(SupabaseConfig.fromEnvironment());
  // 온보딩 뷰모델이 처음 상태를 만들 때 바로 읽을 수 있게 디스크를 한 번 읽어 둔다. 못 열어도 앱은 뜬다.
  // 계정 id 는 따로 들고 있지 않고 그때그때 Supabase 세션(로그인 상태)에서 읽는다 — 로그인 전이면 null 이라 쓰지 않는다.
  final drafts = await openDraftStore(accountId: () => Supabase.instance.client.auth.currentUser?.id);
  // 키가 없는 빌드(시험 · CI)는 건너뛴다 — 앱은 켜지고 카카오 버튼만 실패 토스트를 띄운다.
  await initializeKakaoSdk(Env.kakaoNativeAppKey);
  runApp(SessionScope(
    authChanges: Supabase.instance.client.auth.onAuthStateChange,
    overrides: [
      draftStoreProvider.overrideWithValue(drafts),
      if (!firebaseReady) pushMessagingProvider.overrideWithValue(const NoPushMessaging()),
      // 안드로이드 시스템 알림 창구는 앱을 켤 때 한 번만 만든다 — 로그아웃해도 새로 만들지 않는다(push_provider.dart).
      systemNotificationsProvider.overrideWithValue(LocalSystemNotifications(FlutterLocalNotificationsPlugin())),
      // 하트 구매는 안드로이드(구글 플레이)와 iOS(App Store)에서 연다. 다른 곳은 provider 기본값(아무것도 하지 않는 창구)이다.
      // 로그아웃해도 버리지 않는다 — 플러그인 하나를 앱이 끝날 때까지 쓴다. iOS 창구는 여기서(앱 시작) 바로 거래를 듣기 시작한다.
      if (platformHeartStoreGateway(() => InAppPurchase.instance) case final gateway?)
        heartStoreGatewayProvider.overrideWithValue(gateway),
      // 앱 투어를 "이 계정이 봤는지" 계정(프로필 id = 로그인 사용자 id)별로 센다. 그때그때 세션에서 읽는다.
      tourAccountIdProvider.overrideWithValue(() => Supabase.instance.client.auth.currentUser?.id),
    ],
    child: const CampusMateApp(),
  ));
}

/// 앱 루트 위젯. 로그인 상태는 [AuthSessionListenable] 이,
/// 인증 게이트는 [VerificationGateListenable] 이 실시간으로 알려준다.
class CampusMateApp extends ConsumerStatefulWidget {
  const CampusMateApp({super.key});

  @override
  ConsumerState<CampusMateApp> createState() => _CampusMateAppState();
}

class _CampusMateAppState extends ConsumerState<CampusMateApp> {
  late final AuthSessionListenable _authSession;
  late final VerificationGateListenable _verificationGate;
  late final OnboardingStepListenable _onboardingStep;
  late final AccountStatusListenable _accountStatus;
  late final GoRouter _router;
  /// 앱이 백그라운드에서 돌아올 때 하단 내비 "대화" 숫자를 갱신한다([_refreshChatsOnResume]).
  /// 앱이 화면에서 사라지고(hide) 다시 보일 때(show) 사용자 채널을 끊고 다시 건다([_syncUserChannel]).
  late final AppLifecycleListener _lifecycle;

  /// 앱이 화면에 보이는가(hidden · paused 가 아니다). 앱은 보이는 채로 시작한다.
  bool _appShown = true;
  /// 스플래시를 잠깐 붙잡아 두는 임시 장치 (로고 작업 때 다시 본다).
  final SplashHold _splashHold = SplashHold();
  final List<StreamSubscription<Object>> _pushSubscriptions = [];
  /// 알림을 눌러 연 경로. 라우터가 그대로 받아 줄 때까지 붙잡아 둔다([_openPendingPushRoute]).
  String? _pendingPushPath;

  @override
  void initState() {
    super.initState();
    // 시작 화면이 로그아웃 확인에 쓰는 것과 같은 인스턴스다. 로그아웃하면 SessionScope 가 새로 만든다.
    _authSession = ref.read(authSessionListenableProvider);
    // 3b·3c·온보딩 ViewModel 이 각 단계 직후 부르는 것과 같은 인스턴스여야 라우터가 다시 평가된다.
    _verificationGate = ref.read(verificationGateListenableProvider);
    _onboardingStep = ref.read(onboardingStepListenableProvider);
    // apiClientProvider 가 실패를 올리는 것과 같은 인스턴스다. 로그아웃하면 SessionScope 가 새로 만든다.
    _accountStatus = ref.read(accountStatusListenableProvider);
    _authSession.addListener(_refreshVerificationGate);
    _verificationGate.addListener(_startPushWhenGateOpens);
    _verificationGate.addListener(_startHeartPurchasesWhenGateOpens);
    _verificationGate.addListener(_openPendingPushRoute);
    _verificationGate.addListener(_syncUserChannel);
    _onboardingStep.addListener(_openPendingPushRoute);
    _accountStatus.addListener(_signOutWhenWithdrawn);
    _router = _createRouter();
    _lifecycle = AppLifecycleListener(
      onResume: _refreshChatsOnResume,
      onHide: () => _setAppShown(false),
      onShow: () => _setAppShown(true),
    );
    _refreshVerificationGate();
  }

  /// 어느 탭에 있든 돌아오면 대화 목록·수락 대기를 다시 읽는다. 로그아웃·관문 미완료 가드는 함수 안에 있다.
  void _refreshChatsOnResume() =>
      refreshOnResume(ref.read, isAuthenticated: _authSession.isAuthenticated, gate: _verificationGate.value);

  void _setAppShown(bool shown) {
    _appShown = shown;
    _syncUserChannel();
  }

  /// 사용자 채널 `user:<내 id>`(채팅 실시간 전환 설계안 A)는 **앱이 보이고 로그인 · 관문을 통과한 동안만** 연다 —
  /// 뒤로 가면 끊고(연결 수 · 배터리, 그동안은 푸시가 맡는다) 앞으로 오면 다시 건다. 붙으면 채널이 목록을 한 번 읽어
  /// 놓친 이벤트를 메운다. 로그아웃하면 여기서 끊고, SessionScope 가 컨테이너째 버리며 남은 것도 정리된다.
  void _syncUserChannel() {
    final channel = ref.read(userChannelProvider.notifier);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final open = _appShown && _authSession.isAuthenticated && _verificationGate.value == VerificationGate.complete;
    if (!open || userId == null) {
      channel.stop();
      return;
    }
    channel.start(userId);
  }

  /// 탈퇴(직접 16c 든 다른 기기에서든)면 시작 화면용 알림을 남기고 로그아웃한다 — 로그아웃은 여기 한 곳뿐이다.
  void _signOutWhenWithdrawn() => signOutWhenWithdrawn(_accountStatus.value, ref.read(signOutProvider));

  /// 세션이 바뀔 때마다 게이트·온보딩 단계를 다시 조회한다.
  /// 로그아웃하면 조회에 쓸 토큰이 없고, 앞 사용자의 통과 상태를
  /// 다음 사용자가 물려받으면 안 되므로 캐시를 비운다.
  void _refreshVerificationGate() {
    _syncUserChannel();
    if (!_authSession.isAuthenticated) {
      _forgetSession();
      return;
    }
    unawaited(_verificationGate.refresh());
    unawaited(_onboardingStep.refresh());
    _startPush();
  }

  /// 세션이 없어졌을 때(로그아웃 · 탈퇴 · gotrue 가 갱신 실패로 세션을 스스로 버린 경우 모두) 앞 사용자의 것을 비운다.
  void _forgetSession() {
    // 앞 사용자가 눌러 둔 알림 경로를 다음 사용자가 물려받지 않게 한다.
    _pendingPushPath = null;
    _verificationGate.reset();
    _onboardingStep.reset();
    _stopPush();
    // 온보딩 임시 저장 값도 지운다 — signOut() 을 지나지 않고 세션만 사라지는 경로가 있다. 두 번 지워도 같은 결과다.
    unawaited(ref.read(draftStoreProvider).clearAll());
  }

  /// 로그인한 뒤에만 FCM 을 건드린다 — 로그인 전에는 등록할 주인이 없고,
  /// Firebase 를 켜지 않은 테스트도 이 경로로는 들어오지 않는다.
  /// 구독은 한 번만 걸고, 토큰 등록은 부를 때마다 다시 시도한다(registrar 가 중복을 걸러 준다).
  void _startPush() {
    if (_pushSubscriptions.isEmpty) {
      final messaging = ref.read(pushMessagingProvider);
      final foreground = ref.read(foregroundPushProvider);
      _pushSubscriptions.addAll([
        // 앱이 켜져 있을 때 받은 알림 — 화면을 갱신하고 시스템 알림으로도 보여 준다(2026-10-13 사용자 요청).
        messaging.onMessage.listen(_onForegroundMessage),
        // 알림을 눌러서 열었을 때만 화면을 옮긴다. 앱이 직접 띄운 알림(안드로이드)을 눌러도 같은 길로 간다.
        messaging.onMessageOpenedApp.listen(_openRoute),
        foreground.onTap.listen(_openRoute),
      ]);
      unawaited(messaging.initialMessage().then(_openLaunchRoute));
      // 안드로이드는 시스템 알림 창구를 준비하고, iOS 는 FCM 포그라운드 표시를 켠다.
      unawaited(foreground.start().then(_openLaunchRoute));
    }
    unawaited(ref.read(pushRegistrarProvider).start());
  }

  /// 꺼진 앱을 알림(FCM 이 띄운 것이든 앱이 직접 띄운 것이든)을 눌러 켰으면 그 화면으로 간다.
  void _openLaunchRoute(Map<String, dynamic>? data) {
    if (data != null) {
      _openRoute(data);
    }
  }

  /// 새로 가입한 사용자는 학교 메일·학과 입력 전이라 토큰 등록이 403 으로 막힌다 —
  /// 로그인 때 한 번만 시도하면 앱을 다시 켜기 전까지 알림을 못 받는다.
  /// 게이트가 열리는 순간 다시 등록한다.
  void _startPushWhenGateOpens() {
    if (_verificationGate.value == VerificationGate.complete) {
      _startPush();
    }
  }

  /// 하트 결제 구독은 상점이 아니라 여기서 연다 — 상점이 닫혀 있어도 늦게 온 결제를 받고, 결제 직후 앱이 꺼졌던 결제를 복구한다
  /// (계획서 6-1 ①). 서버 확인은 가입 관문 뒤라 관문이 열린 다음에만. 뷰모델은 앱 수명 동안 하나이고, 로그아웃하면
  /// SessionScope 가 컨테이너째 버린다 — 다음 사람이 로그인해 관문이 열리면 새 뷰모델이 다시 구독한다.
  void _startHeartPurchasesWhenGateOpens() {
    if (_verificationGate.value == VerificationGate.complete) {
      unawaited(ref.read(heartPurchaseViewModelProvider.notifier).refresh());
    }
  }

  /// 세션이 이미 끝난 뒤에 불리는 뒷정리다 — 토큰 삭제는 세션이 살아 있어야 되므로
  /// 로그아웃은 `signOut(registrar, auth)` 로 먼저 지우고 나간다(`core/auth/sign_out.dart`).
  /// 여기 `stop()` 은 그때 이미 비워진 토큰을 다시 지우려 하지 않고,
  /// 세션 만료처럼 우리가 부르지 않은 종료에서만 실제로 할 일이 남는다.
  void _stopPush() {
    if (_pushSubscriptions.isEmpty) {
      return;
    }
    for (final subscription in _pushSubscriptions) {
      unawaited(subscription.cancel());
    }
    _pushSubscriptions.clear();
    unawaited(ref.read(pushRegistrarProvider).stop());
  }

  /// 푸시가 가리키는 화면의 목록을 다시 읽는다 — 앱이 켜진 채 받은 알림과 알림을 눌러 연 경우 둘 다.
  void _refreshForRoute(Map<String, dynamic> data) => refreshForPush(ref.read, data, invalidate: ref.invalidate);

  /// 앱이 켜진 채 받은 푸시 — 해당 화면 목록과 홈 종 배지를 맞추고, 시스템 알림으로도 보여 준다
  /// (2026-10-13 사용자 요청으로 조각 4 의 "앱이 켜져 있으면 배너를 띄우지 않는다" 를 뒤집었다).
  /// 지금 열려 있는 채팅방의 알림은 안드로이드에서 띄우지 않는다 — 서버의 "방을 보고 있으면 안 보낸다"
  /// (`last_read_at` 30초 눈대중)가 빗나간 경우다. iOS 는 시스템이 띄워 막지 못한다(`core/push/foreground_push.dart`).
  void _onForegroundMessage(PushMessage message) {
    _refreshForRoute(message.data);
    refreshUnreadForPush(ref.read, isAuthenticated: _authSession.isAuthenticated, gate: _verificationGate.value);
    // 맨 위 화면의 경로 — 대화 목록에서 push 로 연 채팅방도 여기에 잡힌다.
    final currentLocation = _router.state.matchedLocation;
    unawaited(ref.read(foregroundPushProvider).present(message, currentLocation: currentLocation));
  }

  /// 알림을 눌러 연 경우에도 목록을 다시 읽는다 — 백그라운드에 있던 앱은 [_refreshForRoute] 를 못 받았고,
  /// 대화 탭 같은 목록은 들어갈 때 다시 읽지 않아 옮기기만 하면 낡은 목록(빈 상태)이 그대로 보인다.
  void _openRoute(Map<String, dynamic> data) {
    _refreshForRoute(data);
    _pendingPushPath = PushRoute.resolve(data);
    _openPendingPushRoute();
  }

  /// 꺼진 앱을 알림으로 켜면 경로가 관문 · 온보딩 조회보다 먼저 온다(A10). 그때 열면 조회 전
  /// 기본값(약관 동의)으로 끌려갔다가, 조회가 오면 홈으로 가서 목표 화면을 놓친다.
  /// 그래서 라우터와 같은 규칙이 그 경로를 그대로 받아 줄 때만 열고, 아니면 다음 변화 때 다시 본다.
  void _openPendingPushRoute() {
    final path = _pendingPushPath;
    if (path == null) {
      return;
    }
    final redirect = AuthRedirect(
      _authSession.isAuthenticated,
      _verificationGate.value,
      _onboardingStep.value,
      accountStatus: _accountStatus.value,
    );
    if (redirect.resolve(path) != null) {
      return;
    }
    _pendingPushPath = null;
    PushRoute.open(_router, path);
  }

  GoRouter _createRouter() {
    return AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      verificationGate: () => _verificationGate.value,
      onboardingStep: () => _onboardingStep.value,
      isSplashHeld: _splashHold.isHolding,
      accountStatus: () => _accountStatus.value,
      refreshListenable: Listenable.merge([_authSession, _verificationGate, _onboardingStep, _accountStatus, _splashHold]),
    );
  }

  /// 세션 리스너 · 게이트는 provider 가 소유해 [ProviderScope] 와 함께 정리된다 — 여기서 dispose 하지 않는다.
  @override
  void dispose() {
    _lifecycle.dispose();
    for (final subscription in _pushSubscriptions) {
      unawaited(subscription.cancel());
    }
    _verificationGate.removeListener(_startPushWhenGateOpens);
    _verificationGate.removeListener(_startHeartPurchasesWhenGateOpens);
    _verificationGate.removeListener(_openPendingPushRoute);
    _verificationGate.removeListener(_syncUserChannel);
    _onboardingStep.removeListener(_openPendingPushRoute);
    _accountStatus.removeListener(_signOutWhenWithdrawn);
    _authSession.removeListener(_refreshVerificationGate);
    _splashHold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CampusMate',
      theme: AppTheme.light(),
      // 시스템 다크에 끌려가지 않게 고정한다 (DESIGN.md §2.7 — 다크 모드는 MVP 범위 밖)
      themeMode: ThemeMode.light,
      routerConfig: _router,
      // 입력칸 밖 빈 곳을 누르면 키보드를 내린다 — 화면 · 시트 · 대화상자가 모두 이 밑에 뜬다(사용자 피드백 9).
      // 앱 투어 덮개도 라우터 바깥 여기에 둔다 — 화면을 옮겨 가며 단계를 이어도 덮개가 남는다(pen 섹션 24).
      builder: (context, child) => KeyboardDismissOnTap(child: AppTourHost(router: _router, child: child!)),
    );
  }
}
