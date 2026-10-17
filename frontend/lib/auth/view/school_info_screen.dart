import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/view/info_note.dart';
import 'package:campus_mate/auth/viewmodel/school_info_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/school_info_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 학과·학번을 직접 입력받는 화면 (DESIGN.md 화면 3c, pen 03c 화면 `B9Hu7`).
///
/// 학교명은 학교 메일 인증(03)으로 이미 확정돼 읽기 전용으로만 보여준다.
/// 학과·학번은 OCR 대조가 없는 자기 입력값이다(§9 3c, 검증 수단 부재는 §13 미결66).
///
/// 앱바 제목(pen `Tn7yn` "학교 정보")만 두고 뒤로가기는 두지 않는다 — 03 을 통과해야 들어오는 화면이라
/// 돌아갈 곳이 없다(화면 02·03 에서 앱바를 통째로 뺀 것과 같은 이유).
class SchoolInfoScreen extends ConsumerWidget {
  const SchoolInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _appBar(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: _body(ref),
        ),
      ),
    );
  }

  /// §8.8 — 높이 56, 캔버스와 같은 색, 스크롤해도 그림자·색이 변하지 않는다.
  PreferredSizeWidget _appBar() {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: AppColors.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      title: Text('학교 정보', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
    );
  }

  /// 학교 확인 행이 폼 맨 위에 있어 학교명이 도착해야 폼 전체를 그릴 수 있다.
  Widget _body(WidgetRef ref) {
    return ref.watch(schoolNameProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _SchoolNameError(onRetry: () => ref.invalidate(schoolNameProvider)),
          data: (schoolName) => _form(ref, schoolName),
        );
  }

  Widget _form(WidgetRef ref, String schoolName) {
    return _SchoolInfoForm(
      schoolName: schoolName,
      state: ref.watch(schoolInfoViewModelProvider),
      viewModel: ref.read(schoolInfoViewModelProvider.notifier),
    );
  }
}

/// 학교명 조회 실패. 이 화면을 지나야 온보딩이 이어지므로 다시 불러올 길을 남긴다.
/// 실패 사유를 그대로 보여줄 것이 없어 공통 안내 문구를 쓴다.
class _SchoolNameError extends StatelessWidget {
  const _SchoolNameError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            const UnknownFailure().toDisplayMessage(),
            style: AppTypography.body.copyWith(color: AppColors.body),
          ),
          AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// 헤드라인 → 학교 확인 행 → 학과 → 학번 → 공개 범위 안내 → 하단 CTA.
/// CTA 는 `Spacer` 가 아니라 스크롤 영역 밖에 고정해 키보드가 올라와도 자리를 지킨다.
class _SchoolInfoForm extends StatelessWidget {
  const _SchoolInfoForm({required this.schoolName, required this.state, required this.viewModel});

  final String schoolName;
  final SchoolInfoUiState state;
  final SchoolInfoViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SingleChildScrollView(child: _content())),
        const SizedBox(height: AppSpacing.md),
        AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
      ],
    );
  }

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('학과와 학번을 알려주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '학교는 인증으로 확인했어요. 학과와 학번은 직접 알려주셔야 해요.',
          style: AppTypography.body.copyWith(color: AppColors.body),
        ),
        const SizedBox(height: AppSpacing.xl),
        ..._fields(),
      ],
    );
  }

  List<Widget> _fields() {
    return [
      _SchoolConfirmedRow(schoolName: schoolName),
      const SizedBox(height: AppSpacing.lg),
      _LabeledTextField(
        label: '학과 · 필수',
        placeholder: '예: 컴퓨터공학과',
        initialValue: state.departmentInput,
        onChanged: viewModel.changeDepartment,
      ),
      const SizedBox(height: AppSpacing.md),
      _LabeledTextField(
        label: '학번 · 필수',
        placeholder: '예: 21',
        initialValue: state.studentNumberInput,
        onChanged: viewModel.changeStudentNumber,
      ),
      const SizedBox(height: AppSpacing.sm),
      const InfoNote(icon: AppIcons.eye, text: '학교·학과·학번은 카드와 프로필에 공개돼요.'),
      if (state.errorMessage != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
      ],
    ];
  }
}

/// 읽기 전용 학교 확인 행 — [원 40 · 3D 졸업모 22 | 학교 로고 + 학교명 | "확인됨" 뱃지] (§9 3c, pen 03c 화면 `B9Hu7` 학교 줄
/// 328×68 · 안쪽 14 · surface-soft · 모서리 14, 대장 전달 값). 종전의 "학교" 작은 글자 줄은 pen 에 없어 뺐다.
/// 입력칸이 아니라는 것이 한눈에 보이도록 `surface-soft` 카드에 얹어 필드 앞에 둔다.
class _SchoolConfirmedRow extends StatelessWidget {
  const _SchoolConfirmedRow({required this.schoolName});

  final String schoolName;

  @override
  Widget build(BuildContext context) {
    return Container(
      // pen 실측 14. 간격 토큰 sm(12)·md(16) 사이 값이라 토큰으로 갈음하지 않는다
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: _row(),
    );
  }

  Widget _row() {
    return Row(
      children: [
        _icon(),
        const SizedBox(width: AppSpacing.sm),
        // 로고는 학교명 글자(16)보다 2 큰 18 — SchoolLabel 이 글자 크기로 정한다. 로고가 없으면 이름만.
        Expanded(child: SchoolLabel(schoolName, style: AppTypography.bodyStrong.copyWith(color: AppColors.ink))),
        const _VerifiedBadge(),
      ],
    );
  }

  /// 원형 아이콘 표면 (pen `e1vPBC`). 카드가 `surface-soft` 라 원은 캔버스 색으로 띄운다.
  /// `circle` 은 위젯 크기의 50% 라 토큰이 아니라 [BoxShape.circle] 로 쓴다(§5.1).
  Widget _icon() {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
      child: const Icon3d(AppIcon3d.graduationCap, size: 22),
    );
  }
}

/// "확인됨" 뱃지 — `primary-wash` 채움 pill 에 `primary-text` 아이콘 14 · 글자 12/600 · 안쪽 10×6(pen 실측(B9Hu7 KzZH8)).
/// 종전 주석은 이 값의 출처를 `B9Hu7` 실측이라 적고 11/600(`AppTypography.badge`)을 썼다 — pen 값은 12/600 이다.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      // pen 실측(B9Hu7 KzZH8) 가로 10 · 세로 6. 간격 토큰(xs 8 · sm 12, xxs 4 · xs 8) 사이 값이라 토큰으로 갈음하지 않는다.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: _label(),
    );
  }

  Widget _label() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.badgeCheck, size: 14, color: AppColors.primaryText),
        const SizedBox(width: AppSpacing.xxs),
        Text('확인됨', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryText)),
      ],
    );
  }
}

/// 라벨 + `text-field` (§8.5) — surface-soft 채움, outline 1px, radius sm, 높이 56, 패딩 16×14.
///
/// 제출이 실패해 폼이 다시 만들어져도 입력칸이 비어 보이는데 CTA 만 켜져 있는 일이 없게
/// [initialValue] 로 상태를 되살린다.
class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.placeholder,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String placeholder;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        _field(),
      ],
    );
  }

  Widget _field() {
    return Container(
      constraints: const BoxConstraints(minHeight: 52), // pen TDM1r. 글자 확대 때는 늘어난다
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: _input(),
    );
  }

  Widget _input() {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      style: AppTypography.body.copyWith(color: AppColors.ink),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: placeholder,
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
      ),
    );
  }
}
