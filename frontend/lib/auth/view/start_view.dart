import 'dart:async';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/auth/viewmodel/start_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/start_view_model.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시작 화면 — 앱을 열 때마다 뜨는 스플래시(pen `jXJSY`)를 고친 것(대장 지시문 07). 스피너는 두지 않는다(DESIGN.md §13-3).
///
/// 위는 지금 스플래시 그대로(마스코트 · "CampusMate" · 부제), 아래에 소셜 로그인 버튼과 안내 줄.
/// 버튼 영역은 **로그아웃이 확인된 뒤에만** 그린다 — 이미 로그인된 사람은 게이트 조회 동안 이 화면에 머무는데,
/// 그때 버튼이 번쩍이지 않게 한다. 자리는 비워 두어 마스코트가 움직이지 않는다.
class StartView extends ConsumerStatefulWidget {
  const StartView({super.key});

  /// 시험이 위치 · 상태를 재는 자리.
  static const Key mascotKey = ValueKey('start-mascot');
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _viewModel().showNotice(notice));
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
    return Scaffold(
      body: SafeArea(
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
                    Expanded(child: _Hero(toast: state.toast)),
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
    );
  }
}

/// 마스코트 · 앱 이름 · 부제(지금 스플래시 그대로)와 그 아래 큰 빈 공간. 토스트는 빈 공간 맨 아래(버튼 바로 위)에
/// 겹쳐 띄워, 떴다 사라져도 마스코트가 움직이지 않는다.
class _Hero extends StatelessWidget {
  const _Hero({required this.toast});

  final StartToast? toast;

  @override
  Widget build(BuildContext context) {
    final current = toast;
    return Stack(
      children: [
        const Center(child: _Brand()),
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    // 마스코트·부제는 2026-09-23 사용자 결정으로 pen 대로 넣었다.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/mascot-female.png', key: StartView.mascotKey, width: 96, height: 96),
        const SizedBox(height: AppSpacing.md),
        Text('CampusMate', style: AppTypography.display.copyWith(color: AppColors.primary)),
        const SizedBox(height: AppSpacing.md),
        Text(
          '하루 한 사람, 같은 캠퍼스에서',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 기존 [AppToast](짙은 #222222 알약, 흰 글씨 14/600)를 버튼과 같은 폭으로 늘려 쓴다. 긴 글은 2줄까지 늘어난다.
class _Toast extends StatelessWidget {
  const _Toast({required this.toast});

  final StartToast toast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: StartView.toastKey,
      width: double.infinity,
      child: AppToast(
        label: toast.message,
        leading: toast.hasWarningIcon ? const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk) : null,
      ),
    );
  }
}

/// 카카오 → 구글 버튼과 맨 아래 안내 줄. 로그아웃이 확인되기 전에는 그리지도, 누르게도, 읽히게도 하지 않고
/// 크기만 차지한다([Visibility.maintainSize]).
class _LoginArea extends ConsumerWidget {
  const _LoginArea({required this.state, required this.isSignedOut});

  final StartUiState state;
  final bool isSignedOut;

  /// 이번 PR 은 카카오 · 구글만. 애플은 iOS 에서만, 개발자 계정 승인 뒤 별도 PR.
  static const _providers = [SocialProvider.kakao, SocialProvider.google];

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
          for (final (index, provider) in _providers.indexed) ...[
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
              // 줄 높이 20(캡션 12 의 20/12배).
              style: AppTypography.caption.copyWith(color: AppColors.muted, height: _noticeLineHeight / 12),
            ),
          ),
        ],
      ),
    );
  }
}
