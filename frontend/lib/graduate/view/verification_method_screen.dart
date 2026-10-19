import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/logout_text_button.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:campus_mate/graduate/view/gate_toast.dart';
import 'package:campus_mate/graduate/viewmodel/verification_method_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// pen 02-0 의 위쪽 앱바 자리 `EHHg3`(높이 56). Leading · 제목이 꺼져 있고 PNG 에도 아무것도 안 보여 **빈 자리**로 둔다 —
/// 소셜 로그인 직후 첫 단계라 뒤로가기가 없다(나갈 길은 맨 아래 로그아웃).
const double _appBarSlot = 56;

/// pen 카드 안 줄높이: 제목 `eE104` 16/600 은 속성 없음 · 렌더 22, 설명 `w5usmG` 14/normal 은 렌더 줄 간격 22(PNG 실측).
const double _cardTitleLine = 22;
const double _cardBodyLine = 22;

/// pen 설명 `dh9X5` 16/normal — 줄높이 속성 없음 · 렌더 22(PNG 실측: 설명 끝에서 카드 위까지가 24 와 맞는다).
const double _bodyLine = 22;

/// 선택됨 표식(circle-check) 한 변.
const double _markSize = 20;

/// 인증 방법 고르기(화면 02-0, pen `M1L5Yg`). 학교 메일 카드 · 졸업증명서 카드 중 하나를 골라 [다음] 을 누른다.
///
/// 카드를 누르는 것은 앱 안 선택일 뿐 서버에 쓰지 않는다 — 서버에 쓰는 것은 [다음] 하나다
/// ([VerificationMethodViewModel]). 성공하면 관문이 바뀌고 화면은 라우터가 옮긴다.
/// 앱바가 없다 — 이 화면이 맨 아래 한 장이라 시스템 뒤로는 종료 안내다(화면이 스스로 [BackExitScope] 를 한 겹 두른다).
class VerificationMethodScreen extends ConsumerWidget {
  const VerificationMethodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(verificationMethodViewModelProvider.select((state) => state.errorMessage), (_, message) {
      if (message != null) showGateToast(context, message);
    });
    final state = ref.watch(verificationMethodViewModelProvider);
    final viewModel = ref.read(verificationMethodViewModelProvider.notifier);

    return BackExitScope(
      child: Scaffold(
        body: SafeArea(
          // 보통 글자에선 [다음] 이 아래에 붙고, 글자를 키워 넘치면 같이 스크롤된다(DESIGN §11.2).
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  // pen 본문 `H78Cl` padding [0,24] · Bottom Actions `hzYme` 아래 16.
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: _appBarSlot),
                      Text('인증 방법을 골라 주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '가입하려면 학교 인증이 필요해요.',
                        style: AppTypography.body.copyWith(color: AppColors.body, height: _bodyLine / 16),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _MethodCard(
                        title: '학교 메일로 인증',
                        body: '재학생 · 학교 메일이 있는 분. 메일로 받은 코드로 바로 확인해요.',
                        isSelected: state.selected == VerificationMethod.schoolEmail,
                        onTap: () => viewModel.select(VerificationMethod.schoolEmail),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _MethodCard(
                        title: '졸업증명서로 인증',
                        body: '졸업해서 학교 메일이 없는 분. 졸업증명서로 확인해요. 확인에 시간이 걸릴 수 있어요.',
                        isSelected: state.selected == VerificationMethod.graduateCertificate,
                        onTap: () => viewModel.select(VerificationMethod.graduateCertificate),
                      ),
                      const Spacer(),
                      // pen [다음] `itG98` 은 02 의 프레임 복사(높이 52 · 모서리 8 · 18/700)라 마스터가 아니다 —
                      // 02 와 같이 공용 AppButton(52 · 모서리 14 · 16/700)을 쓴다(02 · 03 과 한 길이라 어긋나지 않게).
                      AppButton(
                        label: '다음',
                        onPressed: state.canGoNext ? viewModel.next : null,
                        isLoading: state.isSubmitting,
                      ),
                      // pen Bottom Actions `hzYme` 세로 간격 4.
                      const SizedBox(height: AppSpacing.xxs),
                      const LogoutTextButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 방법 카드(pen 마스터 `sPWwm` Card · Outline — 안쪽 20 · 세로 간격 12 · 모서리 16 · 흰 바탕 · 테두리 hairline 1).
/// 선택됨은 테두리만 primary 1 로 바뀐다(라디오 표시 없음, 마스터 설명). 눌림 효과는 카드 크기의 자기 Material 에 그린다(COMMON §4-2).
class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.title, required this.body, required this.isSelected, required this.onTap});

  final String title;
  final String body;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: AppColors.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 선택 표식 자리(20 + 8)만큼 제목 오른쪽을 비운다 — 글자를 키워도 표식과 겹치지 않는다.
                      Padding(
                        padding: const EdgeInsets.only(right: _markSize + AppSpacing.xs),
                        child: Text(
                          title,
                          style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: _cardTitleLine / 16),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        body,
                        style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: _cardBodyLine / 14),
                      ),
                    ],
                  ),
                ),
                // 선택됨 표식(대장 결정 10-19, pen 수정 대기): 안쪽 오른쪽 20 · 위 20 의 circle-check 20 primary.
                // 색만으로 전하지 않으려는 것이다. 낭독은 카드의 selected 가 이미 읽어 주므로 그림은 읽히지 않는다.
                if (isSelected)
                  const Positioned(
                    top: AppSpacing.card,
                    right: AppSpacing.card,
                    child: Icon(AppIcons.circleCheck, size: _markSize, color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
