import 'package:campus_mate/auth/social/viewmodel/reviewer_login_ui_state.dart';
import 'package:campus_mate/auth/social/viewmodel/reviewer_login_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 구글 플레이 심사원 전용 아이디 · 비밀번호 창을 띄운다 — 시작 화면 로고를 빠르게 7번 누르면 열린다(앱 1.0.2).
/// 일반 사용자에게는 보이지 않는 기능이라 눈에 띄는 입구가 없다.
Future<void> showReviewerLoginSheet(BuildContext context) {
  return showSafetySheet<void>(context, (_) => const ReviewerLoginSheet());
}

/// 이메일 · 비밀번호 · 로그인 · 닫기. 가입과 비밀번호 찾기는 없다(운영에서 미리 비밀번호를 붙여 둔 계정으로만 들어간다).
///
/// 입력은 이 위젯의 입력칸만 들고 있고, 시트가 닫히면 함께 사라진다 — 상태 · 로그 · 분석에 남기지 않는다.
/// 심사원이 읽는 창이라 라벨은 영어다(문구 파일에는 있지만 언어와 상관없이 영어 그대로 둔다).
class ReviewerLoginSheet extends ConsumerStatefulWidget {
  const ReviewerLoginSheet({super.key});

  @override
  ConsumerState<ReviewerLoginSheet> createState() => _ReviewerLoginSheetState();
}

class _ReviewerLoginSheetState extends ConsumerState<ReviewerLoginSheet> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _signIn() => ref.read(reviewerLoginViewModelProvider.notifier).signIn(_email.text, _password.text);

  /// 글자를 칠 때마다 로그인 단추를 켜고 끈다.
  void _onChanged(String _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    ref.listen(reviewerLoginViewModelProvider, _closeWhenCompleted);
    final state = ref.watch(reviewerLoginViewModelProvider);
    final canSignIn = ReviewerLoginUiState.isFilled(_email.text, _password.text);
    return SafetySheet(
      children: [
        Text(context.l10n.authSocialReviewerTitle, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        LabeledField(
          label: context.l10n.authSocialReviewerEmail,
          controller: _email,
          onChanged: _onChanged,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: AppSpacing.sm),
        LabeledField(
          label: context.l10n.authSocialReviewerPassword,
          controller: _password,
          onChanged: _onChanged,
          obscureText: true,
        ),
        _FailureLine(failure: state.failure),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: context.l10n.authSocialReviewerSignIn,
          isLoading: state.isSubmitting,
          onPressed: canSignIn ? _signIn : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          label: context.l10n.authSocialReviewerClose,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _closeWhenCompleted(ReviewerLoginUiState? previous, ReviewerLoginUiState next) {
    if (next.completed) {
      Navigator.of(context).pop();
    }
  }
}

/// 입력칸 아래 실패 한 줄. 없으면 자리도 차지하지 않는다. 낭독기에는 나타나는 즉시 읽힌다.
class _FailureLine extends StatelessWidget {
  const _FailureLine({required this.failure});

  final Failure? failure;

  @override
  Widget build(BuildContext context) {
    final current = failure;
    if (current == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(context.errorText(current), style: AppTypography.caption.copyWith(color: AppColors.error)),
      ),
    );
  }
}
