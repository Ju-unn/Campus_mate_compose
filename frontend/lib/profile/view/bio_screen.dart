import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/line_break_limit_formatter.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';
import 'package:campus_mate/profile/view/writing_example.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 자기소개 칸(06-3 · 15c)이 같이 쓰는 상한 — 8줄 · 300자. 줄 상한이 먼저다(넘친 줄 바꿈을 공백으로 바꿔도 글자 수는 같다).
/// 카운터 · 상한 안내는 없다(pen `yxga9` · `zWMxM` 에 없다) — 채팅 1,000자처럼 끝에 닿으면 더 들어가지 않을 뿐이다.
final bioInputFormatters = [lineBreakLimitFormatter(bioMaxLines), codePointLimitFormatter(bioMaxLength)];

/// 자기소개 화면(DESIGN.md 화면 06-3, datingApp.pen `06-3 자기소개`).
/// 06-2b 가 받아 온 초안이 placeholder 가 아니라 실제 입력값으로 들어와 있다(§13-71).
/// "다시 만들기" 버튼은 없다(2026-09-13 사용자 결정, §13-79).
class BioScreen extends ConsumerStatefulWidget {
  const BioScreen({super.key});

  @override
  ConsumerState<BioScreen> createState() => _BioScreenState();
}

class _BioScreenState extends ConsumerState<BioScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(bioViewModelProvider).bio);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bioViewModelProvider.select((s) => s.completed), (previous, completed) {
      // 06-3 뒤에는 아바타 확인(만드는 중 · 실패 · 리빌)을 거쳐 20 → 20d → 홈으로 잇는다(2026-10-17 리빌 맨 끝, 종전 곧바로 20).
      // 서버 단계는 avatar(아직) 또는 complete(아바타가 이미 있어 저장 순간 가입 확정)다 — 둘 다 같은 화면이 상태를 보고 그린다.
      // 단계 캐시가 bio 인 동안 옮기면 redirect 가 06-3 으로 되돌리고, 뒤늦게 complete 가 되면 06-3 에서 홈으로 튕긴다
      // — 캐시가 바뀐 뒤(같은 프레임 안) 옮긴다.
      if (!completed) return;
      ref.read(onboardingStepListenableProvider).refresh().then((_) {
        if (context.mounted) context.go(AppRoutes.onboardingAvatar);
      });
    });
    final state = ref.watch(bioViewModelProvider);
    final viewModel = ref.read(bioViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 2, total: 3),
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
                      Text(
                        '이렇게 소개해볼까요?',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '설문을 바탕으로 초안을 썼어요. 마음에 안 들면 자유롭게 고쳐주세요.',
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: '자기소개',
                        placeholder: '나를 한두 문장으로 소개해주세요',
                        controller: _controller,
                        onChanged: viewModel.changeBio,
                        errorText: state.errorMessage,
                        inputFormatters: bioInputFormatters,
                        maxLines: bioMaxLines,
                      ),
                      // 작성 예시(사용자 요청 10-15, 문구는 사용자 승인 후보). 자리는 06-2a 와 같은 입력칸 아래 32(pen 확인 대상).
                      const SizedBox(height: AppSpacing.xl),
                      const WritingExample(
                        sentences: ['같은 학교 친구들과 카페에서 공부하는 걸 좋아해요. 주말엔 운동하거나 영화 봐요.'],
                      ),
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
