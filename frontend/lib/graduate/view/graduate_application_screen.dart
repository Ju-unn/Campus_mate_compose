import 'package:campus_mate/common/support_email.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/consent/view/consent_row.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/graduate/view/gate_toast.dart';
import 'package:campus_mate/graduate/view/graduate_photo_slot.dart';
import 'package:campus_mate/graduate/view/graduate_reject_alert.dart';
import 'package:campus_mate/graduate/view/method_back.dart';
import 'package:campus_mate/graduate/view/method_back_app_bar.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_ui_state.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_view_model.dart';
import 'package:campus_mate/graduate/viewmodel/method_back_view_model.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:campus_mate/graduate/view/graduate_photo_slot.dart' show graduatePhotoRemoveKey, graduatePhotoSlotKey;
export 'package:campus_mate/graduate/view/graduate_reject_alert.dart' show graduateRejectAlertKey;

/// 테스트가 이메일 입력칸의 잠금(보내는 중)을 찾는 표식.
const Key graduateEmailLockKey = ValueKey('graduate-email-lock');

/// 이전 학교 메일 형식 오류(서버 `PREVIOUS_EMAIL_INVALID` 와 같은 문구). 값표에 없는 상태라 앱이 정했다.
const String _previousEmailInvalidMessage = '이전 학교 메일 형식을 다시 확인해 주세요';

/// 개인정보 동의 줄(계획서 D11 (나)). **값표(02-g)에 없는 줄**이다 — 뷰모델이 동의를 요구해(`canSubmit`) 앱이 문구를 정했다.
/// pen 에 같은 마스터(`ConsentRow`)로 추가돼야 한다(보고).
const String _consentLabel = '졸업증명서 사진을 확인에 쓰는 것에 동의해요';

/// pen 설명 `zXal3` 16/normal 줄높이 1.5(24).
final TextStyle _descriptionStyle = AppTypography.body.copyWith(color: AppColors.body, height: 1.5);

/// 라벨 `H8Ko7q` 14/600 #3F3F3F — 줄높이 속성 없음 · 렌더 19.6(사진 칸 위 212 와 맞춘다).
final TextStyle _labelStyle = AppTypography.labelSmall.copyWith(color: AppColors.body, height: 1.4);

/// 힌트 `qUJm1` 12/normal 줄높이 1.5 #6A6A6A.
final TextStyle _hintStyle = AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5);

/// 졸업생 인증 신청 폼(화면 02-g, pen `JPJAd`) · 반려 뒤 다시 제출(02-g-3 `u38Oyy`, 맨 위에 반려 알림 `parki`가 더해진다).
///
/// 사진 한 장 + 이전 학교 메일(선택) + 동의 줄 + [제출하기]. 반려 뒤에는 **빈 사진 칸으로 시작**한다(대장 지시).
/// 횟수를 다 썼으면 폼 대신 문의 안내(시안 없음). 앱바 화살표와 시스템 뒤로는 같은 `methodBack` 한 함수다 —
/// 방법 고르기로 돌아가며(서버 값을 비운다), 사진을 올리는 중에는 화살표는 보이되 눌러도 아무 일이 없다.
/// 성공하면 관문이 바뀌고 라우터가 대기 화면으로 옮긴다 — 이 화면은 직접 이동하지 않는다.
class GraduateApplicationScreen extends ConsumerWidget {
  const GraduateApplicationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(graduateApplicationViewModelProvider.select((state) => state.errorMessage), (_, message) {
      if (message != null) showGateToast(context, message);
    });
    ref.listen(methodBackViewModelProvider.select((state) => state.errorMessage), (_, message) {
      if (message != null) showGateToast(context, message);
    });
    final state = ref.watch(graduateApplicationViewModelProvider);
    final goBack = methodBack(ref, isBusy: state.isSubmitting);

    return BackExitScope(
      onBack: goBack,
      child: Scaffold(
        appBar: MethodBackAppBar(onBack: goBack),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // pen 본문 `ctLnK` padding 16.
            padding: const EdgeInsets.all(AppSpacing.md),
            child: state.isExhausted ? const _ExhaustedBody() : _FormBody(state: state),
          ),
        ),
      ),
    );
  }
}

class _FormBody extends ConsumerWidget {
  const _FormBody({required this.state});

  final GraduateApplicationUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(graduateApplicationViewModelProvider.notifier);
    final rejection = state.rejection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rejection != null) ...[
          GraduateRejectAlert(reason: rejection.reason, attemptsLeft: rejection.attemptsLeft),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('졸업증명서로 인증해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        Text('졸업증명서 사진 한 장을 올려 주세요. 문서확인번호와 학교 이름이 보이게 찍어 주세요.', style: _descriptionStyle),
        const SizedBox(height: AppSpacing.md),
        _PhotoBlock(state: state, viewModel: viewModel),
        const SizedBox(height: AppSpacing.md),
        _EmailBlock(state: state, viewModel: viewModel),
        const SizedBox(height: AppSpacing.md),
        const HintLine('사진은 확인이 끝나면 바로 지워져요'),
        const SizedBox(height: AppSpacing.md),
        ConsentRow(
          label: _consentLabel,
          checked: state.agreed,
          isRequired: true,
          onToggle: () {
            if (!state.isSubmitting) viewModel.changeAgreed(!state.agreed);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: rejection == null ? '제출하기' : '다시 제출하기',
          onPressed: state.canSubmit ? viewModel.submit : null,
          isLoading: state.isSubmitting,
        ),
      ],
    );
  }
}

/// 사진 블록 `n59HH`(세로 간격 8): 머리줄(라벨 + 개수, 간격 8) 아래 사진 칸.
class _PhotoBlock extends StatelessWidget {
  const _PhotoBlock({required this.state, required this.viewModel});

  final GraduateApplicationUiState state;
  final GraduateApplicationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('졸업증명서 사진', style: _labelStyle),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${state.photo == null ? 0 : 1}/1장',
              style: AppTypography.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        GraduatePhotoSlot(
          photo: state.photo,
          isLocked: state.isSubmitting,
          onPick: viewModel.pickPhoto,
          onRemove: viewModel.removePhoto,
        ),
      ],
    );
  }
}

/// 입력 블록 `VXqWc`(세로 간격 6): 입력칸(공용 `LabeledField` = 마스터 `PccKZ`) + 아래 힌트.
/// 선택이라 비워 둬도 된다. 올리는 중에는 칸이 잠긴다.
class _EmailBlock extends StatelessWidget {
  const _EmailBlock({required this.state, required this.viewModel});

  final GraduateApplicationUiState state;
  final GraduateApplicationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: graduateEmailLockKey,
      ignoring: state.isSubmitting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: '이전 학교 이메일 (선택)',
            placeholder: '예: hong@snu.ac.kr',
            keyboardType: TextInputType.emailAddress,
            onChanged: viewModel.changePreviousEmail,
            errorText: state.isPreviousEmailInvalid ? _previousEmailInvalidMessage : null,
          ),
          const SizedBox(height: 6),
          Text('졸업 전에 쓰던 학교 메일이에요. 몰라도 괜찮아요.', style: _hintStyle),
        ],
      ),
    );
  }
}

/// 신청 횟수를 다 쓴 상태(시안 없음 — 값표 §7). 폼 대신 문의 안내와 문의 메일을 글자로 보인다.
/// 앱바 화살표는 남겨 방법 고르기(학교 메일 길)로 돌아갈 수 있다. 마스코트 · 단추는 두지 않는다.
class _ExhaustedBody extends StatelessWidget {
  const _ExhaustedBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('신청 횟수를 모두 썼어요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.md),
        Text('졸업증명서로는 더 신청할 수 없어요. 아래 메일로 문의해 주세요.', style: _descriptionStyle),
        const SizedBox(height: AppSpacing.md),
        const _SupportMailCard(),
      ],
    );
  }
}

/// 문의 메일 카드 — 정지 안내(`JCWwK`)와 같은 칸 모양(안쪽 [14,16] · 모서리 12 · surface-soft · 메일 줄 간격 8).
class _SupportMailCard extends StatelessWidget {
  const _SupportMailCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(AppIcons.mail, size: 20, color: AppColors.body),
          const SizedBox(width: AppSpacing.xs),
          Text('문의 메일', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 22 / 16)),
          const SizedBox(width: AppSpacing.xs),
          // 좁은 기기 · 큰 글자에서 주소가 넘치지 않게 남은 폭 안에서 줄을 바꾼다.
          Flexible(
            child: Text(supportEmail, style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 22 / 14)),
          ),
        ],
      ),
    );
  }
}
