import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/consent/view/consent_row.dart';
import 'package:campus_mate/consent/viewmodel/consent_ui_state.dart';
import 'package:campus_mate/consent/viewmodel/consent_view_model.dart';
import 'package:campus_mate/core/auth/logout_text_button.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 약관 동의(화면 02-c `woJzd` · 재동의 02-c-4 `dxe7K`). 로그인 직후 첫 관문이다 — 동의 전에는
/// 실명 · 학생증(3b)을 받지 않는다. 동의를 마치면 게이트가 바뀌어 라우터가 다음 화면으로 보낸다.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  /// 저장 실패 · 브라우저 못 엶 안내(pen 에 없음 — 계획서 편차 2). 가입 화면 안내와 같은 자리 · 3초.
  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _view(Uri link) async {
    bool opened;
    try {
      opened = await ref.read(openUrlProvider)(link);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) _showNotice(const UnknownFailure().toDisplayMessage());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(consentViewModelProvider.select((state) => state.errorMessage), (_, message) {
      if (message != null) _showNotice(message);
    });
    final state = ref.watch(consentViewModelProvider);
    final viewModel = ref.read(consentViewModelProvider.notifier);
    // 화면에 있는 동안 게이트 값은 바뀌지 않는다(바뀌면 라우터가 이 화면을 닫는다).
    final isRenewal = ref.read(verificationGateListenableProvider).value == VerificationGate.needsConsentRenewal;
    final notice = _notice;
    return PopScope(
      // 관문이다 — 뒤로 갈 곳이 없다. 나갈 길은 아래 로그아웃뿐이다(대장 결정 pen ②).
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          toolbarHeight: 56,
          backgroundColor: AppColors.canvas,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          title: Text('약관 동의', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // 글자를 키우면 줄이 길어진다 — 본문만 스크롤하고 아래 버튼은 제자리에 둔다.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
                  child: _Body(state: state, isRenewal: isRenewal, viewModel: viewModel, onView: _view),
                ),
              ),
              if (notice != null) ...[
                Center(
                  child: AppToast(
                    leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                    label: notice,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // pen `v4oOf` padding [0,16,16,16] · 간격 4.
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppButton(
                      label: '동의하고 계속하기',
                      onPressed: state.canSubmit ? viewModel.submit : null,
                      isLoading: state.isSubmitting,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    const LogoutTextButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.isRenewal, required this.viewModel, required this.onView});

  final ConsentUiState state;
  final bool isRenewal;
  final ConsentViewModel viewModel;
  final void Function(Uri) onView;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isRenewal ? '약관이 바뀌었어요' : '서비스 이용을 위해 동의해 주세요',
          style: AppTypography.headline.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          isRenewal ? '바뀐 내용을 확인하고 다시 동의해 주세요.' : '필수 항목에 모두 동의하면 시작할 수 있어요.\n마케팅 알림은 선택이에요.',
          style: AppTypography.body.copyWith(color: AppColors.body),
        ),
        const SizedBox(height: AppSpacing.lg),
        ConsentRow(label: '전체 동의', checked: state.allChecked, onToggle: viewModel.toggleAll, isAllAgree: true),
        // pen 구분선 `CqBWB` #EBEBEB 1.
        const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
        for (final item in ConsentItem.values)
          ConsentRow(
            label: item.label,
            checked: state.checked.contains(item),
            onToggle: () => viewModel.toggle(item),
            isRequired: item.isRequired,
            onView: switch (item.link) {
              final link? => () => onView(link),
              null => null,
            },
          ),
      ],
    );
  }
}

/// 로그아웃 글자 버튼(pen `xeQen`). 높이 48 · 14/600 #6A6A6A — AppButton 글자 버튼(primaryText)과 색이 달라 여기 둔다.
