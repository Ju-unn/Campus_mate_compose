import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_ui_state.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 화면 문구 — pen U0dkgR(2026-09-28 값표). 오류 문구는 서버 errors.py 문구를 그대로 보여 준다.
const _badgeLabel = '마지막 단계'; // pen zNhbv
const _headline = '친구에게 받은 코드가 있나요?'; // pen De0I8
const _description = '코드를 입력하면 친구가 남긴 따뜻한 한마디를 프로필에 담을 수 있어요.'; // pen Bl97e
const _fieldLabel = '추천 코드'; // pen hrqDX
// pen e8YTTe 옛 글 "예: CAMPUS-2409" 는 코드 형식(6자)과 달랐다 — 대장이 pen 을 "예: K7M2QX" 로 고친다(2026-09-29).
const _fieldHint = '예: K7M2QX';
const _confirmLabel = '코드 확인하기'; // pen w4Fzb
const _skipLabel = '건너뛰기'; // pen XtL3I

// 토큰에 없는 pen 값.
const _bodyTop = 52.0; // pen IzMEA padding top
const _sectionGap = 20.0; // pen IzMEA vertical gap
const _badgeGap = 6.0; // pen h1CMd gap
const _badgePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 7); // pen h1CMd padding [7,12]
const _mascotSize = 128.0; // pen usyj0
const _confirmHeight = 52.0; // pen eI62H — AppButton(56 · r16)과 모서리가 달라 화면 안에서 그린다(common 은 고치지 않는다)
const _skipHeight = 48.0; // pen bTBCQ
const _textHeight = 1.5; // pen De0I8 · Bl97e · w4Fzb 줄 높이

/// 추천 코드 입력 화면(DESIGN.md 화면 20, pen U0dkgR). 온보딩 끝에서 두 번째 — 06-3 뒤, 20d 앞이다.
/// 서버 온보딩 단계가 아니라 앱에서만 잇는다(2026-09-28 대장 D2). 앱바가 없고 건너뛸 수 있다.
class ReferralCodeScreen extends ConsumerWidget {
  const ReferralCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(referralCodeViewModelProvider.select((s) => s.referrerId), (previous, next) async {
      if (next == null) {
        return;
      }
      // 코드를 준 친구에게 리뷰(20b)를 남길 수 있게 띄우고, 남기든 닫든 20d 로 간다(결함 A3). 성공 토스트는 없다(대장 결정).
      await showFriendReviewComposeSheet(context, next);
      if (context.mounted) {
        context.go(AppRoutes.onboardingAcquisition);
      }
    });
    final state = ref.watch(referralCodeViewModelProvider);
    final viewModel = ref.read(referralCodeViewModelProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          // pen IzMEA padding [52,16,28,16]
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, _bodyTop, AppSpacing.md, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: SingleChildScrollView(child: _Content(state: state, onChanged: viewModel.changeCode))),
              const SizedBox(height: _sectionGap),
              // 확인 중에는 버튼만 끈다(대장 결정).
              _ConfirmButton(onPressed: state.canSubmit ? viewModel.submit : null),
              const SizedBox(height: _sectionGap),
              _SkipButton(onTap: () => context.go(AppRoutes.onboardingAcquisition)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 배지 · 마스코트 · 헤드라인 · 설명 · 코드 칸. 사이 간격은 모두 20(pen IzMEA).
class _Content extends StatelessWidget {
  const _Content({required this.state, required this.onChanged});

  final ReferralCodeUiState state;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _StepBadge()),
        const SizedBox(height: _sectionGap),
        Center(
          child: Image.asset('assets/images/mascot-female.png', width: _mascotSize, height: _mascotSize),
        ),
        const SizedBox(height: _sectionGap),
        Text(_headline, style: AppTypography.headline.copyWith(color: AppColors.ink, height: _textHeight)),
        const SizedBox(height: _sectionGap),
        Text(_description, style: AppTypography.body.copyWith(color: AppColors.body, height: _textHeight)),
        const SizedBox(height: _sectionGap),
        // pen b27UyR · Wgm4Y. 오류 줄은 04-1 닉네임과 같은 LabeledField 오류 모양이다(대장 결정).
        LabeledField(
          label: _fieldLabel,
          placeholder: _fieldHint,
          initialValue: state.code,
          onChanged: onChanged,
          errorText: state.errorMessage,
          inputFormatters: [
            _UpperCaseNoSpaceFormatter(),
            LengthLimitingTextInputFormatter(referralCodeLength),
          ],
        ),
      ],
    );
  }
}

/// "마지막 단계" 배지(pen zNhbv · 마스터 h1CMd): sparkles 16 + 12/600 #C4224B, #FFF0F2 알약.
class _StepBadge extends StatelessWidget {
  const _StepBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _badgePadding,
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.sparkles, size: 16, color: AppColors.primaryText),
          const SizedBox(width: _badgeGap),
          Text(
            _badgeLabel,
            style: AppTypography.caption.copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "코드 확인하기"(pen eI62H): 52 높이 · 모서리 8 주색, 글자 18/700 흰색. 비활성 색은 AppButton 과 같다.
/// 높이는 최소값이라 글자를 키우면 따라 늘어난다.
// 백로그 58 에서 AppButton 으로 합칠 것(52/r8 버튼이 15·19·시트들에도 있다, 2026-09-28 대장).
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('referral-confirm'),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(_confirmHeight),
        padding: EdgeInsets.zero,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.primaryDisabled,
        disabledForegroundColor: AppColors.disabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      child: Text(_confirmLabel, style: AppTypography.label.copyWith(height: _textHeight)),
    );
  }
}

/// 복사해 붙인 "  k7qmx2 " 도 같은 코드로 받는다 — 공백을 빼고 대문자로 바꾼다(홈탭 부탁, 서버 `upper(btrim())` 와 같은 규칙).
class _UpperCaseNoSpaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// 건너뛰기(pen bTBCQ · XtL3I, §13-93 스타일 예외): 328×48 배경 #F2F2F2 {radius.sm} + 글자 #C4224B 14/600.
/// 16f 취소 버튼 `tXumG` 와 색은 같지만 그쪽은 52 높이 시트 버튼이라 재사용하지 않는다(계획서 A2).
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 바탕을 Material 이 칠해 눌림 효과가 버튼에 붙는다(COMMON §4-2) — Container(color:) 로 바꾸면 잉크가 Scaffold 에 뜬다.
    return Material(
      key: const Key('referral-skip'),
      color: AppColors.surfaceStrong,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // 높이는 최소값 — 글자를 키우면 따라 늘어난다(ui 인수인계 메모 minHeight 방식).
          constraints: const BoxConstraints(minHeight: _skipHeight),
          child: Center(
            child: Text(_skipLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
          ),
        ),
      ),
    );
  }
}
