import 'dart:async';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/sign_up_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 대학 이메일로 가입을 시작하는 화면 (DESIGN.md 화면 02, pen `emHNY`).
///
/// 스플래시 다음 첫 화면이라 갈 곳이 없어 앱바를 두지 않는다
/// (pen 원본에는 앱바가 있으나 2026-09-15 사용자 결정으로 뺐다).
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _emailController = TextEditingController();

  /// 탈퇴한 계정이 로그아웃되며 남긴 알림(pen V12leV · EuJqq). 3초 뒤 지운다(04-2 토스트와 같은 시간).
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _notice = LoginNotice.take();
    if (_notice != null) {
      _noticeTimer = Timer(const Duration(seconds: 3), () => setState(() => _notice = null));
    }
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signUpViewModelProvider);
    final viewModel = ref.read(signUpViewModelProvider.notifier);
    ref.listen(signUpViewModelProvider, _onStateChanged);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: double.infinity,
                height: 124,
                child: Image(
                  image: AssetImage('assets/images/campus-heart-orbit-v1.png'),
                  fit: BoxFit.contain,
                ),
              ),
              Text('대학 이메일로 시작해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('학교 이메일 주소만 가입할 수 있어요.', style: AppTypography.body.copyWith(color: AppColors.body)),
              Text(
                '인증이 끝나면 이메일은 어디에도 공개되지 않아요.',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('대학 이메일', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
              const SizedBox(height: AppSpacing.xs),
              _EmailField(controller: _emailController, onChanged: viewModel.changeEmail),
              const SizedBox(height: AppSpacing.xs),
              const _DomainHint(),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              if (_notice != null) ...[
                Center(
                  child: AppToast(
                    leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                    label: _notice!,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm), // CTA 바로 위 12(pen KJnpw)
              ],
              // 동의는 로그인 뒤 02-c 에서 항목별로 받는다 — 여기 있던 묵시 동의 줄은 지웠다(사용자 결정 2026-09-29).
              AppButton(label: '인증 메일 받기', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }

  void _onStateChanged(SignUpUiState? previous, SignUpUiState next) {
    final email = next.otpSentTo;
    if (email == null) {
      return;
    }
    ref.read(signUpViewModelProvider.notifier).acknowledgeNavigation();
    context.go(AppRoutes.verifyCode, extra: email);
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52), // pen TDM1r. 글자 확대 때는 늘어난다
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.mail, size: 20, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: _EmailInput(controller: controller, onChanged: onChanged)),
        ],
      ),
    );
  }
}

class _EmailInput extends StatelessWidget {
  const _EmailInput({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.emailAddress,
      style: AppTypography.body.copyWith(color: AppColors.ink),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: 'hong@snu.ac.kr',
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
      ),
    );
  }
}

class _DomainHint extends StatelessWidget {
  const _DomainHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(AppIcons.badgeCheck, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '@snu.ac.kr · @yonsei.ac.kr · @korea.ac.kr 외 17곳',
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
