import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 아래 세 색은 **카카오톡 화면을 흉내 낸 그림에만** 쓴다 — 남의 브랜드 색이라
/// core/theme 팔레트(우리 색)로 올리지 않고 이 파일 안에서만 둔다.
const Color _kakaoPanel = Color(0xFF0A0A0A);
const Color _kakaoYellow = Color(0xFFFEE500);
const Color _kakaoCheckMark = Color(0xFF2B2200);

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b, datingApp.pen `04-1b 카카오톡 아이디`).
/// 건너뛰기 없음(§13-100).
class KakaoIdScreen extends ConsumerWidget {
  const KakaoIdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kakaoIdViewModelProvider);
    final viewModel = ref.read(kakaoIdViewModelProvider.notifier);
    return Scaffold(
      // pen `sN9Il` 은 04-1 과 같은 첫째 점을 켠다 — 04-1b 는 04-1 에 딸린 화면이다.
      appBar: const OnboardingAppBar(current: 0, total: 6),
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
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        '카카오톡 아이디를 알려주세요',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '서로 수락하고 신뢰 확인을 마친 상대에게만 공개돼요.',
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: '카카오톡 아이디',
                        placeholder: '예: campusmate_22',
                        initialValue: state.kakaoIdInput,
                        onChanged: viewModel.changeKakaoId,
                        helper: '설정 > 계정에서 언제든 바꿀 수 있어요',
                        errorText: state.errorMessage,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const NoticeCard(
                        isEmphasis: true,
                        title: '꼭 확인해 주세요',
                        body: '카카오톡에서 \'ID 검색 허용\'을 켜주셔야 상대가 내 아이디를 검색할 수 있어요. '
                            '꺼져 있으면 신뢰 확인을 마쳐도 연락이 닿지 않아요.',
                        footer: '카카오톡 > 설정 > 프로필 관리 > 카카오톡 ID 에서 켤 수 있어요',
                        child: _KakaoSettingExample(),
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

/// 카카오톡 설정 화면이 어떻게 생겼는지 보여주는 그림(pen `sN9Il` 의 `W2tFQt`)이다 —
/// 우리 화면이 아니라 남의 앱 화면을 옮겨 그린 것이라 눌러도 아무 일이 없다.
class _KakaoSettingExample extends StatelessWidget {
  const _KakaoSettingExample();

  @override
  Widget build(BuildContext context) {
    // 조각을 하나씩 읽어 봐야 소용이 없는 그림이라 통째로 한 문장으로 읽힌다.
    return Semantics(
      label: '카카오톡 설정 예시, ID 검색 허용 켜짐',
      image: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '카카오톡 설정 화면 예시',
            // 토큰 badge(11/600)에서 굵기만 pen 값으로 낮춘다.
            style: AppTypography.badge.copyWith(color: AppColors.disabled, fontWeight: FontWeight.w500),
          ),
          // 캡션과 패널 사이는 카드 gap 과 같은 12 다(pen 실측).
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: _kakaoPanel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ID 검색 허용', style: AppTypography.labelSmall.copyWith(color: AppColors.onInk)),
                const _KakaoToggleImage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 켜져 있는 카카오톡 토글 그림. 트랙 44×24 · 손잡이 20 (pen `W2tFQt`).
class _KakaoToggleImage extends StatelessWidget {
  const _KakaoToggleImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 24,
      padding: const EdgeInsets.all(2),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: _kakaoYellow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
        child: const Icon(AppIcons.check, size: 12, color: _kakaoCheckMark),
      ),
    );
  }
}
