import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/view/info_note.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 고른 서류 종류. 폼 안이 아니라 화면이 들고 있어야 반려 배너가 붙어도 초기화되지 않는다.
  _DocumentType _documentType = _DocumentType.studentId;

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
      // pen `Rg1VT`·`EFK7V`·`uin4L` 제목줄.
      appBar: AppBar(
        title: Text('학생 인증', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        centerTitle: false,
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        // 이 화면에는 `go` 로만 들어와 뒤로가기가 저절로 생기지 않는다 — `OnboardingAppBar` 처럼
        // 자리를 항상 잡아 둔다. 갈 곳이 있으면 화살표, 없으면 빈 48 칸이다.
        // 8 + 48 에 titleSpacing 4 — pen 처럼 화살표 가운데 x32, 제목 x60 이 된다.
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Navigator.of(context).canPop()
              ? IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, color: AppColors.ink),
                )
              : const SizedBox(width: 48, height: 48),
        ),
      ),
      // 여백은 화면 모양마다 다르다 — 확인 중 두 화면은 pen 이 [0,32,48,32] 로 따로 잡아 뒀다.
      body: SafeArea(top: false, child: _body(state)),
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
      return const _WaitingView(
        mascot: 'assets/images/mascot-female.png',
        headline: '확인하고 있어요',
        description: '보통 금방 끝나요. 앱을 나가도 완료되면 알려드릴게요.',
      );
    }
    if (state.status == _pendingStatus) {
      return const _WaitingView(
        mascot: 'assets/images/mascot-male.png',
        headline: '조금 더 확인이 필요해요',
        description: '담당자가 서류를 확인하고 있어요. 완료되면 알림으로 알려드릴게요.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 28),
      child: _SubmitForm(
        state: state,
        viewModel: ref.read(studentVerificationViewModelProvider.notifier),
        documentType: _documentType,
        onDocumentTypeChanged: (type) => setState(() => _documentType = type),
      ),
    );
  }
}

/// 마스코트 128dp + 문구 + "나중에 확인하기" (pen `EFK7V`·`uin4L`).
/// 재시도 버튼은 두지 않는다 — 폴링이 알아서 다음 화면으로 넘겨준다.
/// "나중에 확인하기"는 앱을 내린다. 다음에 열면 이 화면에서 이어진다(DESIGN.md §9 3b).
class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.mascot, required this.headline, required this.description});

  final String mascot;
  final String headline;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // pen 여백 [위 0 · 오른쪽 32 · 아래 48 · 왼쪽 32]. 본문은 그 안을 꽉 채우고
      // 세로·가로 모두 가운데다(pen `EFK7V`·`uin4L`).
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
      child: Center(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(mascot, width: 128, height: 128, fit: BoxFit.contain),
          const SizedBox(height: 14),
          Text(headline, style: AppTypography.headline.copyWith(color: AppColors.ink)),
          const SizedBox(height: 14),
          SizedBox(
            width: 296,
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => unawaited(SystemNavigator.pop()),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                textStyle: AppTypography.labelSmall,
              ),
              child: const Text('나중에 확인하기'),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// 인증 서류 종류(pen `Rg1VT` ④ 탭). **서버로는 보내지 않는다** — 어느 서류든 같은 판독이다.
/// 고른 값은 실명 칸 힌트와 업로드 안내 문구만 바꾼다(2026-09-23 사용자 결정).
enum _DocumentType {
  studentId('학생증', '학생증에 표기된 이름', '이름·학교·유효기간이 선명하게 보여야 해요'),
  graduation('졸업증명서', '졸업증명서에 표기된 이름', '이름·학교·졸업 일자가 선명하게 보여야 해요');

  const _DocumentType(this.label, this.nameHint, this.photoHint);

  final String label;
  final String nameHint;
  final String photoHint;
}

/// 히어로 → 안내 문구 → 실명 `text-field` → 사진 업로더 → 하단 CTA.
class _SubmitForm extends StatelessWidget {
  const _SubmitForm({
    required this.state,
    required this.viewModel,
    required this.documentType,
    required this.onDocumentTypeChanged,
  });

  final StudentVerificationUiState state;
  final StudentVerificationViewModel viewModel;

  /// 고른 탭은 **화면이 아니라 부모가** 들고 있다 — 반려 배너가 붙었다 떨어지면
  /// 자식 위젯 자리가 밀려 `State` 가 새로 만들어지고 고른 탭이 학생증으로 돌아간다(권고 7).
  final _DocumentType documentType;
  final ValueChanged<_DocumentType> onDocumentTypeChanged;

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
        // 거절 상태는 마스코트·제목·부제 자리를 배너가 대신한다(pen `yrG1J`, 2026-09-24 사용자 결정).
        if (state.status == _rejectedStatus) ...[
          _RejectedBanner(reason: state.rejectReason),
          const SizedBox(height: 20),
        ] else
          const _Hero(),
        ..._fields(),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }

  List<Widget> _fields() {
    return [
      _DocumentTypeTabs(selected: documentType, onChanged: onDocumentTypeChanged),
      const SizedBox(height: 20),
      Text('실명 · 필수', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
      const SizedBox(height: AppSpacing.xs),
      _RealNameField(
        initialValue: state.realNameInput,
        hintText: documentType.nameHint,
        onChanged: viewModel.changeRealName,
      ),
      if (state.realNameError != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(state.realNameError!, style: AppTypography.caption.copyWith(color: AppColors.error)),
      ],
      const SizedBox(height: 20),
      _PhotoZone(
        photo: state.selectedPhoto,
        hint: documentType.photoHint,
        onTap: viewModel.pickPhoto,
      ),
      const SizedBox(height: 20),
      const InfoNote(icon: AppIcons.shieldCheck, text: '인증 서류는 프로필에 공개되지 않아요.'),
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
          height: 112,
          child: Image(image: AssetImage('assets/images/campus-trust-icon-v1.png'), fit: BoxFit.contain),
        ),
        const SizedBox(height: 20),
        Text('학교와 재학 상태를 확인해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: 20),
        Text(
          '학생증이나 졸업증명서 한 장이면 충분해요. 확인 후 원본은 안전하게 처리해요.',
          style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 인증 거절 배너(pen Alert 마스터 `teNRJ` 인스턴스, 3b `yrG1J` 의 `b1kMW`).
/// 폼은 그대로 살아 있어 바로 다시 제출할 수 있다(재제출 상한 없음).
/// 모서리를 둥글리지 않고 좌우로 가득 채운다 — 폼 맨 위를 가로지르는 띠다.
class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner({required this.reason});

  /// 서버가 준 반려 사유. 없으면 "사유:" 를 빼고 안내만 보여준다.
  final String? reason;

  static const String _retryGuide = '다시 올리면 다시 확인해요';

  @override
  Widget build(BuildContext context) {
    final detail = reason == null || reason!.isEmpty ? _retryGuide : '사유: $reason · $_retryGuide';
    return Container(
      width: double.infinity,
      color: AppColors.primaryWash,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(AppIcons.circleX, size: 20, color: AppColors.primaryText),
          // pen 실측 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 줄높이만 pen 값(1.5)으로 덮는다 — 토큰은 14/600 · 12/400 까지 같다.
                Text(
                  '인증이 거절됐어요',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 1.5),
                ),
                const SizedBox(height: 2),
                Text(detail, style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
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
  const _RealNameField({
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
  });

  final String initialValue;

  /// 고른 서류 종류에 맞는 힌트(학생증 / 졸업증명서).
  final String hintText;
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
          hintText: hintText,
          hintStyle: AppTypography.body.copyWith(color: AppColors.disabled),
        ),
      ),
    );
  }
}

/// 사진 업로드 존(pen `KeC6D`, 높이 264). 테두리 없이 `surface-soft` 채움 + 내부 아이콘·라벨로 탭 영역을 알린다.
class _PhotoZone extends StatelessWidget {
  const _PhotoZone({required this.photo, required this.hint, required this.onTap});

  final File? photo;

  /// 고른 서류 종류에 맞는 안내(유효기간 / 졸업 일자).
  final String hint;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(onTap()),
      child: SizedBox(
        height: 264,
        width: double.infinity,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: photo == null ? _PhotoPrompt(hint: hint) : Image.file(photo!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PhotoPrompt extends StatelessWidget {
  const _PhotoPrompt({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
          // pen `Rg1VT` 인스턴스가 덮어쓴 값이라 업로더 기본형(`imagePlus`)과 다르다.
          child: const Icon(AppIcons.badgeCheck, size: 30, color: AppColors.primaryText),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('사진을 첨부해주세요', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 260,
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// 서류 종류 탭(pen `Rg1VT` ④). 고른 값은 서버로 가지 않고 화면 문구만 바꾼다.
class _DocumentTypeTabs extends StatelessWidget {
  const _DocumentTypeTabs({required this.selected, required this.onChanged});

  final _DocumentType selected;
  final ValueChanged<_DocumentType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          for (final type in _DocumentType.values) ...[
            if (type != _DocumentType.values.first) const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Semantics(
                button: true,
                selected: type == selected,
                child: GestureDetector(
                  onTap: () => onChanged(type),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: type == selected ? AppColors.canvas : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      type.label,
                      style: AppTypography.labelSmall.copyWith(
                        color: type == selected ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
