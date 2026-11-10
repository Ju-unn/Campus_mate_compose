import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/phone_number_formatter.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_ui_state.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/profile/basic/viewmodel/phone_verify_ui_state.dart';
import 'package:campus_mate/profile/onboarding/view/hint_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 휴대폰 번호 줄(datingApp.pen PhoneVerifyField `SKvqx`, 폭 312, 04-1 2c ① ② ⑥ ⑦ ⑩ ⑫).
/// 번호 칸 → 8 → "인증번호 받기"(⑥ 은 "번호 바꾸기"), 바닥 맞춤. 상태 줄(인증됐어요 · 오류)은 그 8 아래.
class PhoneVerifyField extends StatelessWidget {
  const PhoneVerifyField({required this.state, required this.viewModel, super.key});

  final BasicInfoUiState state;
  final BasicInfoViewModel viewModel;

  /// 11자리를 다 채우면 키보드를 내린다 — 다음 할 일은 "인증번호 받기" 다.
  void _changePhoneNumber(BuildContext context, String value) {
    viewModel.changePhoneNumber(value);
    if (value.replaceAll(RegExp(r'\D'), '').length == PhoneNumberFormatter.maxDigits) {
      FocusScope.of(context).unfocus();
    }
  }

  void _send(BuildContext context) {
    FocusScope.of(context).unfocus();
    unawaited(viewModel.sendCode());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phone = state.phoneVerify;
    final isVerified = phone.step == PhoneVerifyStep.verified;
    final statusError = state.phoneStatusError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _VerifyInput(
                label: l10n.profileBasicInfoPhoneLabel,
                placeholder: '010-0000-0000',
                text: state.phoneNumberInput,
                onChanged: (value) => _changePhoneNumber(context, value),
                keyboardType: TextInputType.phone,
                inputFormatters: const [PhoneNumberFormatter()],
                isLocked: phone.isPhoneLocked,
                hasError: phone.isInUse,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (isVerified)
              // Change Button(UqCmR 변형) 52 높이 · 안쪽 [0,12] · primary-text.
              _TextAction(
                label: l10n.profileBasicInfoPhoneChange,
                color: AppColors.primaryText,
                height: 52,
                horizontalPadding: AppSpacing.sm,
                onPressed: viewModel.changePhoneAgain,
              )
            else
              AppButton(
                label: phone.isSending ? l10n.profileBasicInfoPhoneSending : l10n.profileBasicInfoPhoneSend,
                isInline: true,
                isLoading: phone.isSending,
                // ③ 이후(인증번호 줄이 열린 뒤)에는 회색 — 다시 받기는 인증번호 줄 아래 글자가 맡는다.
                onPressed: phone.step == PhoneVerifyStep.idle && state.canSendCode ? () => _send(context) : null,
              ),
          ],
        ),
        if (isVerified)
          _StatusLine.success(l10n.profileBasicInfoPhoneVerified, top: AppSpacing.xs)
        else if (statusError != null)
          _StatusLine.error(context.errorText(statusError), top: AppSpacing.xs),
      ],
    );
  }
}

/// 인증번호 줄(datingApp.pen OtpEntryRow `EqLaR`, 폭 312, 04-1 2c ③ ④ ⑤ ⑪ ⑬).
/// 입력 줄(인증번호 칸 + 타이머 → 8 → 확인) → 8 → 안내 · 오류 · 진행 줄 하나 → 8 → 다시 받기(48).
class OtpEntryRow extends StatelessWidget {
  const OtpEntryRow({required this.state, required this.viewModel, super.key});

  final BasicInfoUiState state;
  final BasicInfoViewModel viewModel;

  /// 6자리가 되면 키보드를 내린다 — 뷰모델이 바로 확인한다(⑪).
  void _changeCode(BuildContext context, String value) {
    if (value.length == verificationCodeLength) {
      FocusScope.of(context).unfocus();
    }
    unawaited(viewModel.changeCode(value));
  }

  /// 남은 초를 m:ss 로(pen "2:59" · "0:45").
  static String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phone = state.phoneVerify;
    final isClosed = phone.isCodeExpired || phone.isCodeLocked;
    final codeError = phone.codeError;
    final canResend = state.canSendCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _VerifyInput(
                label: l10n.profileBasicInfoCodeLabel,
                placeholder: l10n.profileBasicInfoCodePlaceholder,
                text: phone.codeInput,
                onChanged: (value) => _changeCode(context, value),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(verificationCodeLength),
                ],
                autofillHints: const [AutofillHints.oneTimeCode],
                // 줄이 열리면 바로 칸을 잡는다 — 문자 자동 채움 제안이 키보드 위에 뜬다.
                autofocus: true,
                isReadOnly: phone.isVerifying || isClosed,
                isLocked: phone.isCodeLocked,
                hasError: codeError is PhoneCodeMismatchFailure || phone.isCodeLocked,
                valueColor: phone.isCodeLocked ? AppColors.disabled : null,
                // TrailingIcon 자리의 타이머 14/600. 시간이 다 됐거나(⑤) 잠기면(⑬) 회색.
                trailing: Text(
                  _clock(phone.codeSecondsLeft),
                  style: AppTypography.labelSmall.copyWith(color: isClosed ? AppColors.disabled : AppColors.primaryText),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppButton(
              label: phone.isVerifying ? l10n.profileBasicInfoCodeVerifying : l10n.commonConfirm,
              isInline: true,
              isLoading: phone.isVerifying,
              onPressed: phone.canVerify ? () => unawaited(viewModel.verifyCode()) : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (codeError != null)
          _StatusLine.error(context.errorText(codeError))
        else if (phone.isVerifying)
          _StatusLine.pending(l10n.profileBasicInfoCodeChecking)
        else
          HintLine(l10n.profileBasicInfoCodeHint),
        const SizedBox(height: AppSpacing.xs),
        // Resend(UqCmR 변형) 48 높이 · 안쪽 0 · 왼쪽 정렬. 기다리는 동안 회색 "m:ss 뒤 다시 받기", 되면 분홍 "다시 받기".
        _TextAction(
          label: phone.resendSecondsLeft > 0
              ? l10n.profileBasicInfoCodeResendIn(time: _clock(phone.resendSecondsLeft))
              : l10n.profileBasicInfoCodeResend,
          color: canResend ? AppColors.primaryText : AppColors.disabled,
          height: 48,
          horizontalPadding: 0,
          onPressed: canResend ? () => unawaited(viewModel.sendCode()) : null,
        ),
      ],
    );
  }
}

/// 라벨 14/600 body → 8 → 상자(datingApp.pen TextInput `PccKZ`: 52 · 모서리 12 · 안쪽 [0,16]). 04-1 의 다른 칸(`LabeledField`)과
/// 같은 모양에 이 줄에만 있는 세 가지를 더했다 — 잠김(⑥ ⑩ ⑪ ⑬: #F2F2F2 · #EBEBEB 1 · 값 body, 입력 막힘), 칸 밖 오류 줄 없이
/// 빨간 테두리만(⑦ ④ ⑬), 오른쪽 끝 글자(타이머). 오류 문구는 줄 밖 상태 줄이 맡는다(pen "상자 안 ErrorRow 는 여기선 안 씀").
class _VerifyInput extends StatefulWidget {
  const _VerifyInput({
    required this.label,
    required this.placeholder,
    required this.text,
    required this.onChanged,
    required this.keyboardType,
    required this.inputFormatters,
    this.isLocked = false,
    this.isReadOnly = false,
    this.hasError = false,
    this.valueColor,
    this.trailing,
    this.autofillHints,
    this.autofocus = false,
  });

  final String label;
  final String placeholder;

  /// 칸의 글자. 뷰모델이 지우면(다시 받기 · 번호 바꾸기) 칸도 따라 비운다.
  final String text;
  final ValueChanged<String> onChanged;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final bool isLocked;
  final bool isReadOnly;
  final bool hasError;
  final Color? valueColor;
  final Widget? trailing;
  final Iterable<String>? autofillHints;
  final bool autofocus;

  @override
  State<_VerifyInput> createState() => _VerifyInputState();
}

class _VerifyInputState extends State<_VerifyInput> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(_VerifyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idle = widget.hasError
        ? _errorBorder
        : _border(widget.isLocked ? AppColors.hairlineSoft : AppColors.hairline);
    final trailing = widget.trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          autofillHints: widget.autofillHints,
          autofocus: widget.autofocus,
          readOnly: widget.isLocked || widget.isReadOnly,
          style: AppTypography.body.copyWith(
            color: widget.valueColor ?? (widget.isLocked ? AppColors.body : AppColors.ink),
          ),
          decoration: InputDecoration(
            hintText: widget.placeholder,
            hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
            filled: true,
            fillColor: widget.isLocked ? AppColors.surfaceStrong : AppColors.surfaceSoft,
            constraints: const BoxConstraints(minHeight: _boxHeight),
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            // 상자 오른쪽 안쪽 16 은 글자 뒤에 둔다 — 끝 글자가 있으면 입력기는 그쪽 안쪽 여백을 넣지 않는다.
            suffixIcon: trailing == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(start: AppSpacing.xxs, end: AppSpacing.md),
                    child: trailing,
                  ),
            suffixIconConstraints: const BoxConstraints(),
            border: idle,
            enabledBorder: idle,
            // 잠긴 칸은 눌러도 테두리가 바뀌지 않는다. 오류는 누른 동안에도 빨갛다.
            focusedBorder: widget.hasError || widget.isLocked ? idle : _focusBorder,
          ),
        ),
      ],
    );
  }

  /// 상자 높이(최소값 — 글자를 키우면 늘어난다, DESIGN §11.2).
  static const double _boxHeight = 52;

  static final OutlineInputBorder _errorBorder = _border(AppColors.error, width: 2);
  static final OutlineInputBorder _focusBorder = _border(AppColors.ink, width: 2);

  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// 상태 줄(datingApp.pen ValidationStatus `DtNAW`): 표식 14 → 4 → 12/400, 17 높이. 오류 · 인증됨 · 확인 중을 색만으로 말하지 않게
/// 표식을 같이 둔다. 확인 중 표식은 pen 의 정지 그림(loader-circle) 대신 도는 원이다(LabeledField 확인 중과 같다).
class _StatusLine extends StatelessWidget {
  const _StatusLine.error(this.text, {this.top = 0})
      : leading = const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
        color = AppColors.error;

  const _StatusLine.success(this.text, {this.top = 0})
      : leading = const Icon(AppIcons.circleCheck, size: 14, color: AppColors.success),
        color = AppColors.success;

  const _StatusLine.pending(this.text)
      : leading = const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
        ),
        color = AppColors.muted,
        top = 0;

  final Widget leading;
  final Color color;
  final String text;

  /// 위 간격. 번호 줄 아래에서는 8(pen y=85), 인증번호 줄 안에서는 줄의 간격이 따로 있다.
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.xxs),
          Flexible(child: Text(text, style: AppTypography.caption.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// 글자 버튼(datingApp.pen TextButton `UqCmR`: 14/600, 채움 · 밑줄 · 아이콘 없음). 높이 · 안쪽 여백 · 색은 쓰는 자리의 pen 인스턴스 값이다
/// — "번호 바꾸기" 52 · [0,12], "다시 받기" 48 · 0. 꺼지면([onPressed] null) 눌리지 않고 부른 쪽이 회색을 준다.
/// 공용 `MutedTextButton`(muted 고정 · 늘 켜짐)과 AppButton text 변형(16/600)이 이 모양과 달라 이 화면 안에 둔다.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.color,
    required this.height,
    required this.horizontalPadding,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final double height;
  final double horizontalPadding;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Center(
                widthFactor: 1,
                child: Text(label, style: AppTypography.labelSmall.copyWith(color: color)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
