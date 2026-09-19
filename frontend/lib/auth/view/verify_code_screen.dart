import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 인증코드 입력 화면 (DESIGN.md 화면 03).
///
/// pen `VuiDi` 원본에는 앱바가 있으나(제목 비활성) 화면 02 와 같은 이유로 뺐다.
/// CTA 는 pen 실측(52/radius 8) 대신 이미 승인된 `AppButton`(56/radius 16)을 쓴다.
class VerifyCodeScreen extends ConsumerWidget {
  const VerifyCodeScreen({required this.email, super.key});

  final UniversityEmail email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(verifyCodeViewModelProvider(email));
    final viewModel = ref.read(verifyCodeViewModelProvider(email).notifier);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('인증코드를 입력해 주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('${email.toRequestValue()} 로 보냈어요', style: AppTypography.body.copyWith(color: AppColors.body)),
              const SizedBox(height: AppSpacing.xl),
              _CodeField(onChanged: viewModel.changeCode),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: '재전송',
                variant: AppButtonVariant.text,
                onPressed: () => viewModel.resend(),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              AppButton(label: '확인', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: TextField(
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        maxLength: 6,
        style: AppTypography.body.copyWith(color: AppColors.ink),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, counterText: ''),
      ),
    );
  }
}
