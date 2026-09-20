import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b). 건너뛰기 없음(§13-100).
class KakaoIdScreen extends ConsumerWidget {
  const KakaoIdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kakaoIdViewModelProvider);
    final viewModel = ref.read(kakaoIdViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('카카오톡 아이디', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('카카오톡 아이디를 알려주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xl),
                      TextFormField(
                        initialValue: state.kakaoIdInput,
                        onChanged: viewModel.changeKakaoId,
                        decoration: const InputDecoration(hintText: '카카오톡 아이디'),
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}
