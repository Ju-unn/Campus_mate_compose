import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 인증코드 입력 화면 (DESIGN.md 화면 03, pen `VuiDi` / 오류 `Vn6w4`).
///
/// pen `VuiDi` 원본에는 앱바가 있으나(제목 비활성) 화면 02 와 같은 이유로 뺐다.
/// CTA 는 pen 실측(52/radius 8) 대신 이미 승인된 `AppButton`(56/radius 16)을 쓴다.
class VerifyCodeScreen extends ConsumerWidget {
  const VerifyCodeScreen({required this.email, super.key});

  final UniversityEmail email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(verifyCodeViewModelProvider(email));
    final viewModel = ref.read(verifyCodeViewModelProvider(email).notifier);
    final expiresAt = state.codeExpiresAt;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text('인증 코드를 입력해요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${email.toRequestValue()} 로 6자리 숫자를 보냈어요',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.xl),
              _CodeBoxes(
                code: state.codeInput,
                isRejected: state.isCodeRejected,
                onChanged: viewModel.changeCode,
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: AppTypography.caption.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (expiresAt != null) _ExpiryTimer(expiresAt: expiresAt),
              const SizedBox(height: 2),
              _ResendButton(availableAt: state.resendAvailableAt, onResend: viewModel.resend),
              const Spacer(),
              // 기한이 지나는 순간 버튼이 꺼져야 해서 타이머와 같은 박자로 다시 그린다.
              if (expiresAt == null)
                AppButton(
                  label: '확인',
                  onPressed: state.canSubmit(DateTime.now()) ? viewModel.submit : null,
                )
              else
                CountdownBuilder(
                  deadlineAt: expiresAt,
                  builder: (context, remaining) => AppButton(
                    label: '확인',
                    onPressed: state.canSubmit(DateTime.now()) ? viewModel.submit : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "메일 다시 받기". 60초 쿨다운 동안에는 눌러도 아무 일이 없으므로 **버튼을 꺼 두고**
/// 남은 초를 같이 보여준다 — 눌리지 않는 이유를 화면이 말하지 않으면 고장으로 읽힌다.
class _ResendButton extends StatelessWidget {
  const _ResendButton({required this.availableAt, required this.onResend});

  final DateTime? availableAt;
  final Future<void> Function() onResend;

  @override
  Widget build(BuildContext context) {
    final at = availableAt;
    if (at == null) {
      return _button(label: '메일 다시 받기', onPressed: onResend);
    }
    return CountdownBuilder(
      deadlineAt: at,
      builder: (context, remaining) => remaining == Duration.zero
          ? _button(label: '메일 다시 받기', onPressed: onResend)
          : _button(label: '메일 다시 받기 (${remaining.inSeconds + 1}초)', onPressed: null),
    );
  }

  Widget _button({required String label, required VoidCallback? onPressed}) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: EdgeInsets.zero,
        foregroundColor: AppColors.primaryText,
        disabledForegroundColor: AppColors.disabled,
        textStyle: AppTypography.labelSmall,
      ),
      child: Text(label),
    );
  }
}

/// 숫자 여섯 칸(pen `WnXeu`, 칸 `uhbG3`). 보이지 않는 입력칸 하나가 키보드를 받고
/// 칸들은 그 값을 한 글자씩 그리기만 한다 — 칸마다 입력칸을 두면 붙여넣기·지우기가 꼬인다.
///
/// 컨트롤러를 두는 이유는 **밖에서 값이 비워질 때**(메일 다시 받기) 입력칸에 남은 글자와
/// 그려진 칸이 어긋나기 때문이다. 상태가 늘 주인이고 입력칸이 따라온다.
class _CodeBoxes extends StatefulWidget {
  const _CodeBoxes({required this.code, required this.isRejected, required this.onChanged});

  final String code;
  final bool isRejected;
  final ValueChanged<String> onChanged;

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> {
  late final TextEditingController _controller = TextEditingController(text: widget.code);

  @override
  void didUpdateWidget(_CodeBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.code,
        selection: TextSelection.collapsed(offset: widget.code.length),
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
    final code = widget.code;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          // 칸은 그림일 뿐이라 토크백이 읽을 것이 없다 — 아래 입력칸 하나만 읽힌다.
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _CodeBox(
                      digit: i < code.length ? code[i] : null,
                      isRejected: widget.isRejected,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: widget.onChanged,
                keyboardType: TextInputType.number,
                // 문자 메시지·메일의 인증 코드를 키보드 위에서 바로 채울 수 있게 한다.
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
                // 라벨은 화면에 보이지 않고(불투명 0) 토크백만 읽는다.
                decoration: const InputDecoration(
                  labelText: '인증 코드 6자리',
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.digit, required this.isRejected});

  final String? digit;
  final bool isRejected;

  @override
  Widget build(BuildContext context) {
    final isFilled = digit != null;
    final Color borderColor;
    if (isRejected) {
      borderColor = AppColors.error;
    } else if (isFilled) {
      borderColor = AppColors.ink;
    } else {
      borderColor = AppColors.hairline;
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isFilled || isRejected ? AppColors.surfaceSoft : AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: borderColor, width: isRejected ? 2 : 1),
      ),
      child: Text(digit ?? '', style: AppTypography.headline.copyWith(color: AppColors.ink)),
    );
  }
}

/// "04:32 뒤에 만료돼요". 기한이 지나면 새 코드를 받으라고 바꿔 말한다.
class _ExpiryTimer extends StatelessWidget {
  const _ExpiryTimer({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      deadlineAt: expiresAt,
      builder: (context, remaining) {
        final minutes = remaining.inMinutes.toString().padLeft(2, '0');
        final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        return Row(
          children: [
            const Icon(AppIcons.timer, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(
              remaining == Duration.zero ? '코드가 만료됐어요. 메일을 다시 받아 주세요' : '$minutes:$seconds 뒤에 만료돼요',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }
}
