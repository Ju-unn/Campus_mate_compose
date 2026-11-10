import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/view/inquiry_reason_sheet.dart';
import 'package:campus_mate/inquiry/view/inquiry_reason_text.dart';
import 'package:campus_mate/inquiry/viewmodel/inquiry_ui_state.dart';
import 'package:campus_mate/inquiry/viewmodel/inquiry_view_model.dart';
import 'package:campus_mate/profile/onboarding/view/hint_line.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 문의하기(11-08 회의 할 일 6번, pen 21a `o8YoF` · 21b `P15T9` · 21c `unMlh`). 설정 "지원" 의 "문의하기" 줄과
/// FAQ 검색 결과 없음 화면이 push 로 연다. 사유 + 내용 + 답장 받을 메일을 보내면 운영 메일로 가고 관리자 웹에 쌓인다.
/// 보내면 이전 화면으로 돌아가 "문의를 보냈어요" 토스트(pen `de3Sv`)를 띄운다.
class InquiryScreen extends ConsumerStatefulWidget {
  const InquiryScreen({super.key});

  static const reasonSelectKey = Key('inquiry-reason-select');
  static const bodyBoxKey = Key('inquiry-body-box');
  static const bodyKey = Key('inquiry-body');
  static const replyEmailBoxKey = Key('inquiry-reply-email-box');
  static const replyEmailKey = Key('inquiry-reply-email');

  @override
  ConsumerState<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends ConsumerState<InquiryScreen> {
  final TextEditingController _body = TextEditingController();
  late final TextEditingController _replyEmail;
  final FocusNode _bodyFocus = FocusNode();
  final FocusNode _replyEmailFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 계정 메일을 알면 뷰모델이 미리 채워 둔다 — 칸도 같은 글자로 시작한다.
    _replyEmail = TextEditingController(text: ref.read(inquiryViewModelProvider).replyEmail);
    _replyEmailFocus.addListener(_onReplyEmailFocusChange);
  }

  @override
  void dispose() {
    _replyEmailFocus
      ..removeListener(_onReplyEmailFocusChange)
      ..dispose();
    _bodyFocus.dispose();
    _body.dispose();
    _replyEmail.dispose();
    super.dispose();
  }

  void _onReplyEmailFocusChange() {
    // 테두리 색(누르는 중 ink)이 따라가도록 다시 그린다. 칸을 벗어나면 그때부터 형식 오류를 알린다.
    setState(() {});
    if (!_replyEmailFocus.hasFocus) {
      ref.read(inquiryViewModelProvider.notifier).finishReplyEmailEdit();
    }
  }

  Future<void> _pickReason() async {
    final viewModel = ref.read(inquiryViewModelProvider.notifier);
    final picked = await showInquiryReasonSheet(context, current: ref.read(inquiryViewModelProvider).reason);
    if (picked != null) viewModel.selectReason(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inquiryViewModelProvider);
    final viewModel = ref.read(inquiryViewModelProvider.notifier);
    ref.listen(inquiryViewModelProvider, (previous, next) {
      if (!next.submitted || (previous?.submitted ?? false)) return;
      // 설정 · FAQ 로 돌아가도 토스트가 남게 앱 전체 ScaffoldMessenger 로 띄운다(신고 흐름과 같다). pen 토스트는 앞 아이콘이 없다.
      showSafetyToast(ScaffoldMessenger.of(context), context.l10n.inquirySent, icon: null, shrinkToText: true);
      context.pop();
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.inquiryScreenTitle, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        centerTitle: false,
        // pen `bFZwF`: 뒤로 48(`R1bD2`, 왼쪽 8) + 간격 4 → 제목 x60.
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // pen Body `ed81B`: 세로 간격 20, 안쪽 16.
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  // pen `L6pCf` 328×44. 글을 두 줄로 접었을 때 44 보다 낮아지지 않게 최소값만 둔다.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: HintLine(context.l10n.inquiryHint),
                  ),
                  const SizedBox(height: 20),
                  _ReasonField(reason: state.reason, onTap: _pickReason),
                  const SizedBox(height: 20),
                  _BodyField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    onChanged: viewModel.updateBody,
                  ),
                  const SizedBox(height: 20),
                  _ReplyEmailField(
                    controller: _replyEmail,
                    focusNode: _replyEmailFocus,
                    onChanged: viewModel.updateReplyEmail,
                    state: state,
                  ),
                ],
              ),
            ),
            _BottomBar(state: state, onSubmit: viewModel.submit),
          ],
        ),
      ),
    );
  }
}

/// 라벨 14/600 #3F3F3F, pen 렌더 높이 19(속성 줄높이 없음). 칸과의 간격은 8.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: 19 / 14)),
    );
  }
}

/// 문의 사유(pen `yGKcd`). 칸을 누르면 사유 시트가 열린다 — 입력칸이 아니라 고르는 칸이다.
class _ReasonField extends StatelessWidget {
  const _ReasonField({required this.reason, required this.onTap});

  final InquiryReason? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(l10n.inquiryReasonLabel),
        Semantics(
          button: true,
          // 칸 이름은 라벨, 값은 고른 사유(안 골랐으면 안내 글)로 읽힌다.
          label: l10n.inquiryReasonLabel,
          // 눌림 효과가 스크롤과 같이 움직이게 칸 안에 Material 을 둔다(COMMON §4-2).
          child: Material(
            key: InquiryScreen.reasonSelectKey,
            color: AppColors.surfaceSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                // pen `fP9ud` 52. 최소값이라 글자를 키우면 칸이 따라 커진다.
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected == null ? l10n.inquiryReasonPlaceholder : selected.label(l10n),
                          style: AppTypography.body.copyWith(
                            color: selected == null ? AppColors.muted : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(AppIcons.chevronDown, size: 20, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 내용(pen `okXzb`). Textarea 마스터 `Zhq9p`: #F7F7F7 · 모서리 8 · 테두리 #767676 1 · 안쪽 12 · 높이 160, 카운터는 상자 안 아래 왼쪽.
class _BodyField extends StatelessWidget {
  const _BodyField({required this.controller, required this.focusNode, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(l10n.inquiryBodyLabel),
        // 상자 어디를 눌러도 글을 쓸 수 있게 한다(글이 짧으면 TextField 는 첫 줄만 차지한다).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: focusNode.requestFocus,
          child: Container(
            key: InquiryScreen.bodyBoxKey,
            // 높이는 최소값만 — 여러 줄을 쓰거나 글자를 키우면 상자가 늘어난다.
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            // 테두리를 decoration 에 두면 Container 가 테두리 두께만큼 여백을 더한다 — pen 여백 12 는 바깥선 기준이다.
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: AppColors.outline),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextField(
                  key: InquiryScreen.bodyKey,
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  // 1000자는 코드포인트로 센다 — 서버 len() 이 그렇게 센다(채팅 입력 바 · 신고 메모와 같은 formatter).
                  inputFormatters: [codePointLimitFormatter(inquiryBodyMaxLength)],
                  style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
                  decoration: InputDecoration.collapsed(
                    hintText: l10n.inquiryBodyHint,
                    hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => Text(
                    l10n.inquiryBodyCounter(count: value.text.runes.length, max: inquiryBodyMaxLength),
                    // pen `BCwSP` 12 / normal / muted / 1.4.
                    style: AppTypography.caption.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 답장 받을 메일(pen `mLQA8`). 앞 메일 아이콘 20, 맞는 모양이면 오른쪽에 체크 20(주색). 틀린 모양은 칸을 벗어난 뒤 빨간 줄로 알린다.
/// 입력칸 공용 `LabeledField` 에 앞 · 뒤 아이콘 자리가 없어 pen `DNyay` 구조(아이콘 · 값 · 체크, 간격 8)를 여기서 그린다.
class _ReplyEmailField extends StatelessWidget {
  const _ReplyEmailField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.state,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final InquiryUiState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = state.emailError;
    // 오류 때는 테두리도 빨간 2px, 누르는 중에는 ink 2px 다(LabeledField 와 같다).
    final border = error != null
        ? const BorderSide(color: AppColors.error, width: 2)
        : (focusNode.hasFocus ? const BorderSide(color: AppColors.ink, width: 2) : const BorderSide(color: AppColors.hairline));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(l10n.inquiryReplyEmailLabel),
        Container(
          key: InquiryScreen.replyEmailBoxKey,
          // pen `H9RnL` 52. 최소값이라 글자를 키우면 칸이 따라 커진다.
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          // 테두리 두께가 바뀌어도 안쪽이 밀리지 않게 위에 덧그린다.
          foregroundDecoration: BoxDecoration(
            border: Border.fromBorderSide(border),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Row(
            children: [
              const Icon(AppIcons.mail, size: 20, color: AppColors.muted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  key: InquiryScreen.replyEmailKey,
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppTypography.body.copyWith(color: AppColors.ink),
                  decoration: InputDecoration.collapsed(
                    hintText: l10n.inquiryReplyEmailHint,
                    hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
                  ),
                ),
              ),
              if (state.isReplyEmailValid) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(AppIcons.check, size: 20, color: AppColors.primary),
              ],
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(child: Text(context.errorText(error), style: AppTypography.caption.copyWith(color: AppColors.error))),
              ],
            ),
          ),
      ],
    );
  }
}

/// 아래 바(pen `CXOcJ` 360×84, 안쪽 [12,16,20,16]). 보내기 실패는 pen 에 없어 버튼 위에 빨간 한 줄로 둔다.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onSubmit});

  final InquiryUiState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final error = state.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Text(context.errorText(error), style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            label: context.l10n.inquirySubmit,
            isLoading: state.isSubmitting,
            onPressed: state.canSubmit ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}
