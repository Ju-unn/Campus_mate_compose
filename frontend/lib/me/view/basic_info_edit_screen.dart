import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/basic_info_edit_view_model.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15d 기본 정보 수정(pen `mhdYA` · 15d-2 `ZuPTD`, 계획서 2026-09-28-me-profile.md A16). 15-5 "수정 ›"(`A8LX2`)이 연다.
/// 닉네임 → 16 → 키 → (빈 자리) → "저장". 저장하면 `true` 를 돌려주며 15-5 로 돌아간다 — 15-5 가 "저장했어요" 를 띄운다(B4).
/// 출생연도 · 성별은 못 고치고 실명은 나오지 않는다(U6).
class BasicInfoEditScreen extends ConsumerStatefulWidget {
  const BasicInfoEditScreen({super.key});

  @override
  ConsumerState<BasicInfoEditScreen> createState() => _BasicInfoEditScreenState();
}

class _BasicInfoEditScreenState extends ConsumerState<BasicInfoEditScreen> {
  /// 치던 값은 컨트롤러가 들고 있다 — 처음 값만 서버 값(뷰모델)에서 받는다.
  late final TextEditingController _nickname =
      TextEditingController(text: ref.read(basicInfoEditViewModelProvider).nicknameInput);
  late final TextEditingController _height =
      TextEditingController(text: ref.read(basicInfoEditViewModelProvider).heightInput);

  @override
  void dispose() {
    _nickname.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(basicInfoEditViewModelProvider);
    final viewModel = ref.read(basicInfoEditViewModelProvider.notifier);
    ref.listen(basicInfoEditViewModelProvider, (previous, next) {
      if (next.completed && !(previous?.completed ?? false)) context.pop(true);
    });
    return Scaffold(
      appBar: const EditAppBar(title: '기본 정보 수정'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              // 본문 `fP8cs` 좌우 24, 위 여백 `We4y3` 32, 닉네임 ↔ 키 `MNhYr` 16. 큰 글씨에서 넘치면 스크롤로 내준다.
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                children: [
                  _InputField(
                    label: '닉네임',
                    controller: _nickname,
                    onChanged: viewModel.changeNickname,
                    isLocked: state.isNicknameLocked,
                    isSaving: state.isSubmitting,
                    hasError: state.nicknameError != null,
                    inputFormatters: nicknameInputFormatters,
                    note: _nicknameNote(state),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _InputField(
                    label: '키 (cm)',
                    controller: _height,
                    onChanged: viewModel.changeHeight,
                    isSaving: state.isSubmitting,
                    hasError: state.heightError != null,
                    keyboardType: TextInputType.number,
                    inputFormatters: heightInputFormatters,
                    note: switch (state.heightError) {
                      final message? => _FieldNote.error(message),
                      null => null,
                    },
                  ),
                ],
              ),
            ),
            _Footer(error: state.errorMessage, isSaving: state.isSubmitting, onSave: state.canSave ? viewModel.save : null),
          ],
        ),
      ),
    );
  }

  /// 닉네임 칸 아래 한 줄 — 잠김(15d-2) > 오류 > 확인 중 > 사용 가능 > 평소 안내(`G1tl8`). 04-1 과 같은 순서에 잠김만 더했다.
  static _FieldNote _nicknameNote(BasicInfoEditUiState state) {
    if (state.nicknameUnlockText case final text?) {
      return _FieldNote(leading: const Icon(AppIcons.clock3, size: 14, color: AppColors.muted), color: AppColors.muted, text: text);
    }
    if (state.nicknameError case final text?) {
      return _FieldNote.error(text);
    }
    if (state.nicknameChecking case final text?) {
      return _FieldNote(leading: _spinner, color: AppColors.muted, text: text);
    }
    if (state.nicknameSuccess case final text?) {
      return _FieldNote(
        leading: const Icon(AppIcons.circleCheck, size: 14, color: AppColors.success),
        color: AppColors.success,
        text: text,
      );
    }
    return const _FieldNote(
      leading: Icon(AppIcons.info, size: 14, color: AppColors.muted),
      color: AppColors.muted,
      text: '30일에 한 번 바꿀 수 있어요',
    );
  }

  /// 04-1 확인 중 표식(`LabeledField`)과 같은 14 · 선 2 의 도는 원.
  static const Widget _spinner = SizedBox.square(
    dimension: 14,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
  );
}

/// 라벨 14/600 body — 줄높이 속성 없음 · 렌더 20(pen `VCwQo`).
final _labelStyle = AppTypography.labelSmall.copyWith(height: 20 / 14, color: AppColors.body);

/// 값 16/400 — 줄높이 속성 없음 · 렌더 23(pen `p3T9Jb`). body 토큰 줄높이 1.6 이면 상자가 57.6 이 된다.
final _valueStyle = AppTypography.body.copyWith(height: 23 / 16);

/// helper 12/400 — 줄높이 속성 없음 · 렌더 17(pen `XATaU`).
final _noteStyle = AppTypography.caption.copyWith(height: 17 / 12);

/// TextInput `PccKZ` — 라벨 → 8 → 상자 → 8 → helper. 상자는 surface-soft · 모서리 8 · 테두리 outline 1 · 안쪽 [0,16]
/// · 세로 가운데. 모양은 04-1 `LabeledField` 와 같고(오류 때 테두리 error 2, 누르면 primary) 상자 높이 · 여백 · helper 표식만
/// pen 값이라 여기서 그린다. 56 은 최소값이다 — 글자를 키우면 상자가 늘어난다(DESIGN §11.2).
///
/// [isLocked] 면 15d-2 `V3sicJ` — 입력 불가, 테두리 hairline, 값 disabled, 오른쪽 lock 20(오른쪽 16 · 값과 8).
class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.hasError,
    required this.inputFormatters,
    this.isLocked = false,
    this.isSaving = false,
    this.keyboardType,
    this.note,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hasError;
  final List<TextInputFormatter> inputFormatters;
  final bool isLocked;

  /// 저장 중 — 모양은 그대로 두고 입력만 막는다. 키보드가 열린 채 계속 치면 보내는 값과 화면 값이 갈라진다(15e 도 저장 중엔
  /// 칸을 막는다).
  final bool isSaving;
  final TextInputType? keyboardType;
  final Widget? note;

  /// 상자 `TDM1r` 높이(최소값).
  static const double _boxHeight = 56;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          onChanged: onChanged,
          enabled: !isLocked,
          readOnly: isSaving,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: _valueStyle.copyWith(color: isLocked ? AppColors.disabled : AppColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceSoft,
            constraints: const BoxConstraints(minHeight: _boxHeight),
            // 위아래는 (56 - 값 23) / 2 — 값과 자물쇠가 상자 한가운데에 온다(pen 자물쇠 y18).
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: (_boxHeight - 23) / 2),
            // 값 ↔ 자물쇠 8 = 입력기가 넣는 4 + 여기 4. 자물쇠 뒤 16 은 상자 오른쪽 안쪽 여백.
            suffixIcon: isLocked
                ? const Padding(
                    padding: EdgeInsetsDirectional.only(start: AppSpacing.xxs, end: AppSpacing.md),
                    child: Icon(AppIcons.lock, size: 20, color: AppColors.disabled),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(),
            border: _border(AppColors.outline),
            enabledBorder: hasError ? _errorBorder : _border(AppColors.outline),
            focusedBorder: hasError ? _errorBorder : _border(AppColors.primary),
            disabledBorder: _border(AppColors.hairline),
          ),
        ),
        ?note,
      ],
    );
  }

  static final OutlineInputBorder _errorBorder = _border(AppColors.error, width: 2);

  /// `gapPadding` 0 — Material 3 는 외곽선 칸의 값 양옆에 이만큼 더 띄운다(떠오르는 라벨 자리). 라벨이 밖에 있어 필요 없고,
  /// 두면 값이 pen 16 이 아니라 20 에서 시작한다.
  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: color, width: width),
      gapPadding: 0,
    );
  }
}

/// helper 줄 `a1eaV` — 상자 8 아래, 표식 14 → 4 → 12/400. 오류는 circle-alert error(B5, 마스터 기본값 · 04-1 과 같다).
class _FieldNote extends StatelessWidget {
  const _FieldNote({required this.leading, required this.color, required this.text});

  const _FieldNote.error(this.text)
      : leading = const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
        color = AppColors.error;

  final Widget leading;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: _noteStyle.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// 저장 실패 글(caption · error, 버튼 위 8 — 04-1 · 15e 와 같은 자리) → "저장"(`fx0HX` 312×56). 버튼을 화면 아래에 붙이고
/// 아래 28 을 두는 것은 15c · 15e 와 같다(Spacer `YXKHl` 뒤, 본문 아래 28).
class _Footer extends StatelessWidget {
  const _Footer({required this.error, required this.isSaving, required this.onSave});

  final String? error;
  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Text(error, style: AppTypography.caption.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(label: '저장', onPressed: onSave, isLoading: isSaving),
        ],
      ),
    );
  }
}
