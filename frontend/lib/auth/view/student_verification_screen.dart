import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사람이 재검토 중일 때 상태를 다시 물어보는 간격.
/// 재검토는 분·시간 단위라 실시간 구독 없이 폴링으로 충분하다(2026-09-19 결정).
const Duration _pollInterval = Duration(seconds: 30);

const String _pendingStatus = 'pending';
const String _rejectedStatus = 'rejected';

/// 학생증 사진과 실명을 제출하는 화면 (DESIGN.md 화면 3b).
///
/// 업로더는 카탈로그의 `id-card-uploader`(촬영 전용, 미리보기 없음) 대신
/// **갤러리 선택 + 미리보기**로 만든다(2026-09-19 Task A8 결정).
class StudentVerificationScreen extends ConsumerStatefulWidget {
  const StudentVerificationScreen({super.key});

  @override
  ConsumerState<StudentVerificationScreen> createState() => _StudentVerificationScreenState();
}

class _StudentVerificationScreenState extends ConsumerState<StudentVerificationScreen> {
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentVerificationViewModelProvider);
    _syncPolling(state.status);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: _body(state),
        ),
      ),
    );
  }

  /// 대기 상태일 때만 폴링을 돌린다. 다른 상태로 넘어가면 타이머를 접는다.
  void _syncPolling(String status) {
    if (status != _pendingStatus) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => _refreshStatus());
  }

  void _refreshStatus() {
    unawaited(ref.read(studentVerificationViewModelProvider.notifier).refreshStatus());
  }

  Widget _body(StudentVerificationUiState state) {
    if (state.isLoadingStatus) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isSubmitting) {
      return const _WaitingView(headline: '확인하고 있어요', description: '잠시만 기다려 주세요');
    }
    if (state.status == _pendingStatus) {
      return const _WaitingView(headline: '조금 더 확인이 필요해요', description: '완료되면 알려드릴게요');
    }
    return _SubmitForm(state: state, viewModel: ref.read(studentVerificationViewModelProvider.notifier));
  }
}

/// 마스코트 128dp + 문구 (DESIGN.md §5.4 "인증·검수 대기" 표).
/// 재시도 버튼은 두지 않는다 — 폴링이 알아서 다음 화면으로 넘겨준다.
class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.headline, required this.description});

  final String headline;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 128,
            height: 128,
            child: Image(image: AssetImage('assets/images/mascot-male-waiting.png'), fit: BoxFit.contain),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(headline, style: AppTypography.headline.copyWith(color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text(description, style: AppTypography.body.copyWith(color: AppColors.body)),
        ],
      ),
    );
  }
}

/// 히어로 → 안내 문구 → 실명 `text-field` → 사진 업로더 → 하단 CTA.
class _SubmitForm extends StatelessWidget {
  const _SubmitForm({required this.state, required this.viewModel});

  final StudentVerificationUiState state;
  final StudentVerificationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SingleChildScrollView(child: _content())),
        const SizedBox(height: AppSpacing.md),
        AppButton(label: '확인 요청하기', onPressed: state.canSubmit ? viewModel.submit : null),
      ],
    );
  }

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Hero(),
        ..._fields(),
        if (state.status != _rejectedStatus && state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }

  List<Widget> _fields() {
    return [
      if (state.status == _rejectedStatus && state.errorMessage != null) ...[
        _RejectedBanner(reason: state.errorMessage!),
        const SizedBox(height: AppSpacing.lg),
      ],
      Text('실명', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
      const SizedBox(height: AppSpacing.xs),
      _RealNameField(initialValue: state.realNameInput, onChanged: viewModel.changeRealName),
      const SizedBox(height: AppSpacing.xs),
      Text('학생증에 적힌 이름과 같게 입력하세요', style: AppTypography.caption.copyWith(color: AppColors.muted)),
      Text('학생증 확인에만 쓰고 다른 사람에게는 안 보여요', style: AppTypography.caption.copyWith(color: AppColors.muted)),
      const SizedBox(height: AppSpacing.lg),
      _PhotoZone(photo: state.selectedPhoto, onTap: viewModel.pickPhoto),
      const SizedBox(height: AppSpacing.sm),
      const _PrivacyNote(),
    ];
  }
}

/// `campus-trust-icon-v1` 히어로 + 안내 문구 (§5.4 — 장식 글리프, 기능 아이콘 아님).
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: double.infinity,
          height: 120,
          child: Image(image: AssetImage('assets/images/campus-trust-icon-v1.png'), fit: BoxFit.contain),
        ),
        Text('학생증으로 학교를 확인해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text('재학생만 만날 수 있도록 한 번만 확인할게요.', style: AppTypography.body.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// 반려 사유 배너. 폼은 그대로 살아 있어 바로 다시 제출할 수 있다(재제출 상한 없음).
/// §5.3 아이콘 표에 경고 아이콘이 없어, 색 대신 제목 문구로 뜻을 전한다.
class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('학생증을 다시 올려주세요', style: AppTypography.labelSmall.copyWith(color: AppColors.error)),
          const SizedBox(height: AppSpacing.xxs),
          Text(reason, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
      ),
    );
  }
}

/// `text-field` (§8.5) — surface-soft 채움, outline 1px, radius sm, 높이 56, 패딩 16×14.
///
/// 제출이 실패해 대기 화면에서 폼으로 돌아오면 필드가 다시 만들어지므로,
/// 입력칸이 비어 보이는데 CTA 만 켜져 있는 일이 없게 [initialValue] 로 상태를 되살린다.
class _RealNameField extends StatelessWidget {
  const _RealNameField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        style: AppTypography.body.copyWith(color: AppColors.ink),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: '학생증에 표기된 이름',
          hintStyle: AppTypography.body.copyWith(color: AppColors.disabled),
        ),
      ),
    );
  }
}

/// 사진 업로드 존. §10 대로 테두리 없이 `surface-soft` 채움 + 내부 아이콘·라벨로 탭 영역을 알린다.
/// 비율은 실제 학생증(85.6×54mm, 약 8:5)을 따른다.
class _PhotoZone extends StatelessWidget {
  const _PhotoZone({required this.photo, required this.onTap});

  final File? photo;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(onTap()),
      child: AspectRatio(
        aspectRatio: 8 / 5,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: photo == null ? const _PhotoPrompt() : Image.file(photo!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// 업로드 존 아래 공개 범위 안내 (pen `Rg1VT` 실측).
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(AppIcons.lock, size: 14, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            '인증 서류는 프로필에 공개되지 않아요.',
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

class _PhotoPrompt extends StatelessWidget {
  const _PhotoPrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(AppIcons.imagePlus, size: 28, color: AppColors.muted),
        const SizedBox(height: AppSpacing.xs),
        Text('학생증 사진 올리기', style: AppTypography.labelSmall.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xxs),
        Text('얼굴과 이름이 잘 보이게 찍어주세요', style: AppTypography.caption.copyWith(color: AppColors.muted)),
      ],
    );
  }
}
