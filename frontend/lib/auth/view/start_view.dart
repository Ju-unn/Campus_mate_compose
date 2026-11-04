import 'dart:async';
import 'dart:math' as math;

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/start_view_model.dart';
import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시작 화면 — 앱을 열 때마다 뜨는 스플래시(pen `jXJSY` → 크리스마스 장면 판 `EbdUI`)를 고친 것(대장 지시문 07).
/// 스피너는 두지 않는다(DESIGN.md §13-3).
///
/// 배경은 크리스마스 장면(Lottie 360×780, 화면 전체 cover — 장면 안에 로고 · 토끼가 있다)이고, 그 아래 문구 한 줄,
/// 맨 아래에 소셜 로그인 버튼과 안내 줄. 사용자 결정(2026-11-03): 1.0.2 부터 날짜 조건 없이 늘 이 장면이다
/// (장면을 바꿀 때는 [AppLottie.splashChristmas] 를 새 장면으로 교체한다).
/// 버튼 영역은 **로그아웃이 확인된 뒤에만** 그린다 — 이미 로그인된 사람은 게이트 조회 동안 이 화면에 머무는데,
/// 그때 버튼이 번쩍이지 않게 한다. 자리는 비워 두어 문구가 움직이지 않는다.
class StartView extends ConsumerStatefulWidget {
  const StartView({super.key});

  /// 시험이 위치 · 상태를 재는 자리.
  static const Key loginAreaKey = ValueKey('start-login-area');
  static const Key toastKey = ValueKey('start-toast');

  @override
  ConsumerState<StartView> createState() => _StartViewState();
}

/// 후속 지시문 13 B-2 디자인 값: 영역 아래 28, 안내 줄 위 padding 4, 안내 줄 높이 20.
const double _bottomPadding = 28;
const double _noticeTopPadding = 4;
const double _noticeLineHeight = 20;

class _StartViewState extends ConsumerState<StartView> {
  /// 토스트가 떠 있는 시간(04-2 · 02 토스트와 같다).
  static const _toastDuration = Duration(seconds: 3);
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    // 로그아웃(탈퇴 · 로그인 만료)하며 남긴 알림 — 예전에는 02 로그인 화면이 띄웠다. 이제 로그아웃하면 여기로 온다.
    final notice = LoginNotice.take();
    if (notice != null) {
      // build 중에는 provider 를 바꿀 수 없어 첫 프레임 뒤에 띄운다.
      WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel().showNotice(notice.message, isInfo: notice.isInfo));
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  StartViewModel _viewModel() => ref.read(startViewModelProvider.notifier);

  /// 새 토스트가 뜰 때마다 시간을 다시 잰다.
  void _onStateChanged(StartUiState? previous, StartUiState next) {
    if (next.toast == null || identical(next.toast, previous?.toast)) {
      return;
    }
    _toastTimer?.cancel();
    _toastTimer = Timer(_toastDuration, _viewModel().dismissToast);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(startViewModelProvider, _onStateChanged);
    final state = ref.watch(startViewModelProvider);
    final session = ref.watch(authSessionListenableProvider);
    return BackExitScope(
      onHint: _viewModel().showBackExitHint,
      child: Scaffold(
        body: Stack(
          children: [
            // 장면은 안전 영역 밖, 화면 전체 기준이다(장면이 상태 표시줄 뒤까지 덮는다).
            const Positioned.fill(child: _SplashScene()),
            SafeArea(
              child: CustomScrollView(
                slivers: [
                  // 보통 글자에선 버튼이 아래에 붙고, 글자를 키워 넘치면 같이 스크롤된다(DESIGN §11.2).
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      // 좌우 24, 소셜 버튼 영역 아래 28(후속 지시문 13 B-2).
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, _bottomPadding),
                      child: Column(
                        children: [
                          Expanded(child: _Hero(toast: state.toast, safeTop: MediaQuery.paddingOf(context).top)),
                          ListenableBuilder(
                            listenable: session,
                            builder: (context, _) => _LoginArea(state: state, isSignedOut: !session.isAuthenticated),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 배경 크리스마스 장면. 장면 안 로고를 낭독기가 앱 이름으로 읽게 한다(옛 글자 로고 "CampusMate" 를 대신한다).
class _SplashScene extends StatelessWidget {
  const _SplashScene();

  @override
  Widget build(BuildContext context) {
    return const AppLottieView(scene: AppLottie.splashChristmas, fit: BoxFit.cover, semanticLabel: 'CampusMate');
  }
}

/// 장면 크기(json 360×780)와 문구 자리(pen `eATMq`: 장면 안 y462).
const double _sceneWidth = 360;
const double _sceneHeight = 780;
const double _taglineSceneTop = 462;

/// 문구 한 줄(pen `eATMq` 16/400 #6A6A6A 가운데, 장면 안 y462 · 높이 26)을 [_Hero] 안에 놓는다.
/// 장면이 cover 로 늘거나 줄어도 로고 바로 아래에 붙도록, 화면 y 가 아니라 **장면 안 y462** 를 화면 자리로 옮겨 놓는다
/// (360×780 이면 화면 y462 그대로). 글자 크기는 장면을 따라 키우지 않는다.
/// 좁고 낮은 화면에서 버튼 묶음과 겹치지 않도록, 버튼 묶음 바로 위([_taglineButtonGap])까지만 내려오고 더는 밀려 올라간다.
class _Tagline extends StatelessWidget {
  const _Tagline({required this.safeTop});

  /// 안전 영역 위쪽 여백(상태 표시줄 등). **안전 영역 밖**에서 읽어 넘긴다 — 안쪽 [MediaQuery] 는 이 값을 이미 0 으로 만든다.
  final double safeTop;

  /// 문구 한 줄이 놓일 화면 y — 장면을 화면에 cover 로 깔았을 때 장면 안 y462 가 닿는 자리.
  static double _sceneY(Size screen) {
    final scale = math.max(screen.width / _sceneWidth, screen.height / _sceneHeight);
    return (screen.height - _sceneHeight * scale) / 2 + _taglineSceneTop * scale;
  }

  @override
  Widget build(BuildContext context) {
    // 장면은 화면 전체 기준이고 [_Hero] 는 안전 영역 위쪽 여백 아래에서 시작하므로, 그만큼 뺀 자리가 [_Hero] 안 y 다.
    final top = _sceneY(MediaQuery.sizeOf(context)) - safeTop;
    return CustomSingleChildLayout(
      delegate: _TaglineLayout(top: top),
      child: Text(
        '인증된 사람과 소중한 인연',
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: AppColors.muted),
      ),
    );
  }
}

/// 문구와 버튼 묶음 사이에 최소한 남길 간격.
const double _taglineButtonGap = AppSpacing.sm;

/// [top] 에 놓되, 버튼 묶음(= [_Hero] 아래)에 [_taglineButtonGap] 이상 가까워지면 위로 밀고, 화면 위로는 나가지 않는다. 가로는 가운데.
class _TaglineLayout extends SingleChildLayoutDelegate {
  const _TaglineLayout({required this.top});

  final double top;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final lowest = size.height - childSize.height - _taglineButtonGap;
    return Offset((size.width - childSize.width) / 2, math.max(0, math.min(top, lowest)));
  }

  @override
  bool shouldRelayout(_TaglineLayout oldDelegate) => oldDelegate.top != top;
}

/// 문구가 놓이는 빈 공간(문구 아래 ~ 버튼 영역 위). 토스트는 이 빈 공간 맨 아래(버튼 바로 위)에 겹쳐 띄워,
/// 떴다 사라져도 문구가 움직이지 않는다.
class _Hero extends StatelessWidget {
  const _Hero({required this.toast, required this.safeTop});

  final StartToast? toast;

  /// 안전 영역 위쪽 여백 — [_Tagline] 이 화면 좌표 y 를 맞추는 데 쓴다.
  final double safeTop;

  @override
  Widget build(BuildContext context) {
    final current = toast;
    return Stack(
      children: [
        Positioned.fill(child: _Tagline(safeTop: safeTop)),
        if (current != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm), // 버튼 영역 바로 위 12
              child: _Toast(toast: current),
            ),
          ),
      ],
    );
  }
}

/// 기존 [AppToast](짙은 #222222 알약, 흰 글씨 14/600, 위아래 10)를 쓴다(후속 지시문 13 B-3).
/// 취소는 폭을 내용에 맞춰 가운데 · `info` 아이콘(한 줄 높이 40), 실패 · 로그아웃 알림은 버튼 폭 · `triangle-alert`
/// (긴 글은 두 줄, 높이 60). 03 학교 메일 충돌 뒤 안내는 버튼 폭 · `info`(pen 312×58, 앱은 AppToast 줄높이 20 이라 60).
class _Toast extends StatelessWidget {
  const _Toast({required this.toast});

  final StartToast toast;

  @override
  Widget build(BuildContext context) {
    final icon = toast.isCancellation || toast.isInfo ? AppIcons.info : AppIcons.alertTriangle;
    final pill = AppToast(label: toast.message, leading: Icon(icon, size: 16, color: AppColors.onInk));
    if (toast.isCancellation) {
      return Center(key: StartView.toastKey, widthFactor: 1, heightFactor: 1, child: pill);
    }
    return SizedBox(key: StartView.toastKey, width: double.infinity, child: pill);
  }
}

/// 카카오 → 구글(→ iOS 면 애플) 버튼과 맨 아래 안내 줄(pen `jXJSY` 시작 화면 4종). 로그아웃이 확인되기 전에는
/// 그리지도, 누르게도, 읽히게도 하지 않고 크기만 차지한다([Visibility.maintainSize]).
class _LoginArea extends ConsumerWidget {
  const _LoginArea({required this.state, required this.isSignedOut});

  final StartUiState state;
  final bool isSignedOut;

  /// 애플 로그인은 iOS 앱에서만(안드로이드 · 웹은 애플 SDK 가 웹 흐름이라 쓰지 않는다). dart:io `Platform` 대신
  /// [defaultTargetPlatform] 을 보는 건 시험에서 덮어쓸 수 있어서다. 그 값은 웹(아이폰 사파리)에서도 iOS 로 나오므로
  /// [kIsWeb] 을 먼저 본다(`http_card_repository.dart` 와 같은 방식).
  static List<SocialProvider> _providers() => [
        SocialProvider.kakao,
        SocialProvider.google,
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) SocialProvider.apple,
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(startViewModelProvider.notifier);
    return Visibility(
      key: StartView.loginAreaKey,
      visible: isSignedOut,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Column(
        children: [
          for (final (index, provider) in _providers().indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm), // 버튼 세로 간격 12
            SocialLoginButton(
              provider: provider,
              isLoading: state.isLoading(provider),
              onPressed: state.isEnabled(provider) ? () => viewModel.signIn(provider) : null,
            ),
          ],
          const SizedBox(height: AppSpacing.sm), // 마지막 버튼 아래 12
          Padding(
            padding: const EdgeInsets.only(top: _noticeTopPadding),
            child: Text(
              '학교 메일 인증은 가입할 때 한 번만 해요',
              textAlign: TextAlign.center,
              // 14px(대장 지시문 15, 디자인 파일 값), 줄 높이 20 = 20/14배. 기존 14px 스타일 bodySmall 을 쓴다.
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: _noticeLineHeight / 14),
            ),
          ),
        ],
      ),
    );
  }
}
