import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/locked_fact_row.dart';
import 'package:campus_mate/me/viewmodel/basic_info_edit_view_model.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/view/choice_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15-6 기본 정보 수정(pen `mhdYA` · 15-6-2 `ZuPTD`, 계획서 2026-09-28-me-profile.md A16 · 2026-10-10 확대). 15-5 "수정 ›"(`A8LX2`)이 연다.
/// 닉네임 → 16 → 키 → "바꿀 수 있는 정보"(내 MBTI · 종교 · 흡연 · 내 동물상 · 내 인상, 구역 사이 24) →
/// "바꿀 수 없는 정보"(출생연도 · 성별 · 학과 잠금 행) → "저장". 저장하면 `true` 를 돌려주며 15-5 로 돌아간다 — 15-5 가
/// "저장했어요" 를 띄운다(B4). 실명 · 전화번호 · 학번은 나오지 않는다(서버가 내려 주지 않는다).
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
              // 본문 `fP8cs` 좌우 24, 위 여백 `We4y3` 32, 닉네임 ↔ 키 `MNhYr` 16. 긴 화면이라(구역 5개 + 잠금 구역) 스크롤로 내준다 —
              // pen 은 저장 버튼까지 한 장으로 그렸지만 앱은 버튼을 아래에 고정한다. 스크롤 안 글은 ListView 가 아니라
              // Column 으로 한 번에 짠다(1500 남짓이라 가볍고, 화면 밖 칸도 시험이 찾을 수 있다).
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: AppSpacing.lg),
                    _EditSections(state: state, viewModel: viewModel),
                    _LockedSection(state: state),
                  ],
                ),
              ),
            ),
            _Footer(
              error: state.errorMessage,
              showsRecalculationNote: state.showsRecalculationNote,
              isSaving: state.isSubmitting,
              onSave: state.canSave ? viewModel.save : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 닉네임 칸 아래 한 줄 — 잠김(15-6-2) > 오류 > 확인 중 > 사용 가능 > 평소 안내(`G1tl8`). 04-1 과 같은 순서에 잠김만 더했다.
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
  static const Widget _spinner = _Spinner14(color: AppColors.muted);
}

/// 라벨 14/600 body — 줄높이 속성 없음 · 렌더 20(pen `VCwQo`).
final _labelStyle = AppTypography.labelSmall.copyWith(height: 20 / 14, color: AppColors.body);

/// 값 16/400 — 줄높이 속성 없음 · 렌더 23(pen `p3T9Jb`). body 토큰 줄높이 1.6 이면 상자가 57.6 이 된다.
final _valueStyle = AppTypography.body.copyWith(height: 23 / 16);

/// helper 12/400 — 줄높이 속성 없음 · 렌더 17(pen `XATaU`).
final _noteStyle = AppTypography.caption.copyWith(height: 17 / 12);

/// 지름 14 · 선 2 의 도는 원 — 04-1 "확인 중…" 과 저장 중 안내(pen `sMuCd` 14)가 쓴다.
class _Spinner14 extends StatelessWidget {
  const _Spinner14({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color));
  }
}

/// "바꿀 수 있는 정보"(pen `hyt7p`) — 닉네임 · 키 아래 24 에서 시작해 구역 사이 24.
/// 구역마다 라벨 14/600 → 8 → 고르는 칸. 라벨 색은 pen 이 구역마다 다르게 칠했다(MBTI · 종교 · 흡연 `#3F3F3F`, 동물상 · 인상 `#222222`).
class _EditSections extends StatelessWidget {
  const _EditSections({required this.state, required this.viewModel});

  final BasicInfoEditUiState state;
  final BasicInfoEditViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          label: '내 MBTI',
          child: MbtiPoleToggle(
            selected: state.mbtiPoles,
            onTap: viewModel.toggleMbtiPole,
            unknownLabel: '모름',
            isUnknownSelected: state.isMbtiUnknown,
            onUnknownTap: viewModel.toggleMbtiUnknown,
          ),
        ),
        _Section(
          label: '종교',
          child: ReligionPicker(selected: state.religion, onSelected: viewModel.changeReligion),
        ),
        _Section(
          label: '흡연',
          child: SmokePicker(isSmoker: state.isSmoker, onSelected: viewModel.changeIsSmoker),
        ),
        _Section(
          label: '내 동물상',
          color: AppColors.ink,
          child: AnimalTypePicker(
            selected: {?state.animalType},
            onTap: viewModel.changeAnimalType,
          ),
        ),
        _Section(
          label: '내 인상',
          color: AppColors.ink,
          isLast: true,
          child: ImpressionTypePicker(
            selected: {?state.impressionType},
            onTap: viewModel.changeImpressionType,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.color = AppColors.body, this.isLast = false});

  final String label;
  final Widget child;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle.copyWith(color: color)),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// "바꿀 수 없는 정보"(pen `ltx1u`) — 위 32 · 라벨 → 8 → 상자(`OBj2z`) → 8 → 안내(`wuU5P`).
/// 상자는 surface-soft · 모서리 12 · 테두리 hairline 1 · 안쪽 [4,16](테두리가 안쪽이라 pen 높이 152 = 4 + 48×3 + 4).
class _LockedSection extends StatelessWidget {
  const _LockedSection({required this.state});

  final BasicInfoEditUiState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('바꿀 수 없는 정보', style: _labelStyle),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 1, vertical: AppSpacing.xxs - 1),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                children: [
                  LockedFactRow(label: '출생연도', value: state.birthYear?.toString() ?? _unknown),
                  LockedFactRow(label: '성별', value: _genderLabel(state.gender)),
                  LockedFactRow(label: '학과', value: state.major ?? _unknown),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon3d(AppIcon3d.infoBlue, size: 18),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    '가입할 때 확인한 정보라 바꿀 수 없어요',
                    style: _noteStyle.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 서버가 값을 안 주면(옛 서버 · 온보딩 전) 빈 칸 대신 줄표 — 15-5 의 키 · 학과 줄과 같다.
  static const String _unknown = '-';

  static String _genderLabel(String? gender) => switch (gender) {
        'male' => '남성',
        'female' => '여성',
        _ => _unknown,
      };
}

/// 라벨 → 8 → 상자 → 8 → helper 에서 입력 칸 하나. TextInput `PccKZ` — 상자는 surface-soft · 모서리 12 · 테두리 hairline 1 · 안쪽 [0,16]
/// · 세로 가운데(2026-10-01 개편 — 옛 56 · 8 · outline). 모양은 04-1 `LabeledField` 와 같고(오류 때 테두리 error 2, 누르면 ink 2)
/// 상자 높이 · 여백 · helper 표식만 pen 값이라 여기서 그린다. 52 는 최소값이다 — 글자를 키우면 상자가 늘어난다(DESIGN §11.2).
///
/// [isLocked] 면 15-6-2 `V3sicJ` — 입력 불가, 테두리 hairline, 값 disabled, 오른쪽 lock 20(오른쪽 16 · 값과 8).
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

  /// 저장 중 — 모양은 그대로 두고 입력만 막는다. 키보드가 열린 채 계속 치면 보내는 값과 화면 값이 갈라진다(15-7 도 저장 중엔
  /// 칸을 막는다).
  final bool isSaving;
  final TextInputType? keyboardType;
  final Widget? note;

  /// 상자 `TDM1r` 높이(최소값).
  static const double _boxHeight = 52;

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
            // 위아래는 (52 - 값 23) / 2 — 값과 자물쇠가 상자 한가운데에 온다(pen 자물쇠 y18).
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: (_boxHeight - 23) / 2),
            // 값 ↔ 자물쇠 8 = 입력기가 넣는 4 + 여기 4. 자물쇠 뒤 16 은 상자 오른쪽 안쪽 여백.
            suffixIcon: isLocked
                ? const Padding(
                    padding: EdgeInsetsDirectional.only(start: AppSpacing.xxs, end: AppSpacing.md),
                    child: Icon(AppIcons.lock, size: 20, color: AppColors.disabled),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(),
            border: _border(AppColors.hairline),
            enabledBorder: hasError ? _errorBorder : _border(AppColors.hairline),
            focusedBorder: hasError ? _errorBorder : _focusBorder,
            disabledBorder: _border(AppColors.hairline),
          ),
        ),
        ?note,
      ],
    );
  }

  static final OutlineInputBorder _errorBorder = _border(AppColors.error, width: 2);
  static final OutlineInputBorder _focusBorder = _border(AppColors.ink, width: 2);

  /// `gapPadding` 0 — Material 3 는 외곽선 칸의 값 양옆에 이만큼 더 띄운다(떠오르는 라벨 자리). 라벨이 밖에 있어 필요 없고,
  /// 두면 값이 pen 16 이 아니라 20 에서 시작한다.
  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
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

/// 버튼 위 안내 한 줄 → "저장"(`fx0HX` 312×52). 안내는 둘 중 하나다 — 저장 중 "점수를 다시 계산하는 중이에요"(`Z6N24` 도는 원 14 + 12/400
/// muted, MBTI · 동물상 · 인상이 바뀐 때만) 또는 저장 실패(`C3oV5u` circle-alert 14 + 12/400 error). 둘 다 표식 → 4 → 글자, 버튼 위 8.
/// 버튼을 화면 아래에 붙이고 바 안쪽 [8,24,8,24](Bottom Bar CTA `A8INC6`, 2026-10-01 개편 — 옛 위 16 · 아래 28)를 두는 것은 15c · 15-7 과 같다.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.error,
    required this.showsRecalculationNote,
    required this.isSaving,
    required this.onSave,
  });

  final String? error;
  final bool showsRecalculationNote;
  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Padding(
      padding: AppSpacing.bottomCta,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null)
            _FooterNote(
              leading: const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
              color: AppColors.error,
              text: error,
            )
          else if (showsRecalculationNote)
            const _FooterNote(
              leading: _Spinner14(color: AppColors.muted),
              color: AppColors.muted,
              text: '점수를 다시 계산하는 중이에요. 몇 초 걸려요',
            ),
          AppButton(label: '저장', onPressed: onSave, isLoading: isSaving),
        ],
      ),
    );
  }
}

/// 버튼 위 안내 한 줄(pen `Z6N24` · `C3oV5u` — 표식 14 → 4 → 12/400, 줄높이 1.4, 아래 8 은 버튼과의 간격).
class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.leading, required this.color, required this.text});

  final Widget leading;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: AppTypography.caption.copyWith(color: color))),
        ],
      ),
    );
  }
}
