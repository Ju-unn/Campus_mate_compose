import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 입력칸(오류가 있으면 오류 문구) 바로 아래 안내 한 줄(pen HintLine `MOmaZ`, 사용자 10-16 "스팸함도 확인 해달라고").
const String verifyCodeSpamHint = '메일이 보이지 않으면 스팸함도 확인해 주세요.';

/// 인증코드 입력 화면 (DESIGN.md 화면 03, pen `VuiDi` / 오류 `Vn6w4`).
///
/// 앱바는 pen 대로 뒤로만 둔다(제목 없음, 사용자 10-16 "온보딩화면에 뒤로가기 버튼이 없는게 있는거 같아") — 뒤로는 02 로 간다.
/// 02(학교 메일 입력)는 앱바 없이 그대로다(02-c 다음 관문이라 돌아갈 곳이 없다).
/// CTA 는 pen 실측(52/radius 8) 대신 이미 승인된 `AppButton`(56/radius 16)을 쓴다.
class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({required this.email, super.key});

  final UniversityEmail email;

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  /// 02 로 돌아가는 중 — 정리(startOver)가 끝나기 전의 두 번째 누름 · 시스템 뒤로가기를 막는다.
  bool _leaving = false;

  UniversityEmail get email => widget.email;

  /// 코드를 확인하는 중 · 확인을 마쳐 다음 관문으로 가는 중 · 이미 돌아가는 중이면 뒤로를 받지 않는다.
  bool _canGoBack(VerifyCodeUiState state) => !_leaving && !state.isSubmitting && !state.verified;

  /// 앱바 뒤로 · 시스템 뒤로가기 · "다른 학교 메일 입력" 이 같이 쓴다 — 임시 연결과 이 화면 상태를 비우고 02 로 간다.
  /// 02 와 03 은 같은 관문(학교 메일)이라 라우터가 02 로 가는 것을 막지 않는다(`AuthRedirect._isOnGate`).
  Future<void> _backToEmail() async {
    if (!_canGoBack(ref.read(verifyCodeViewModelProvider(email)))) return;
    setState(() => _leaving = true);
    await ref.read(verifyCodeViewModelProvider(email).notifier).startOver();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(verifyCodeViewModelProvider(email));
    final viewModel = ref.read(verifyCodeViewModelProvider(email).notifier);

    // 안드로이드 시스템 뒤로가기도 앱바 화살표처럼 02 로 간다(라우터는 이 화면을 두르지 않는다 — 두 겹이면 안내까지 뜬다).
    return BackExitScope(
      onBack: _backToEmail,
      child: Scaffold(
        appBar: _BackAppBar(onBack: _canGoBack(state) ? _backToEmail : null),
        body: SafeArea(
          // 보통 글자에선 확인 버튼이 아래에 붙고, 글자를 키워 넘치면 같이 스크롤된다(DESIGN §11.2, 시작 화면과 같은 방식).
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
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
                      if (state.isTakenBySocial)
                        ..._takenBySocial(state, viewModel)
                      else
                        ..._codeEntry(state, viewModel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 코드를 넣는 평소 03(pen `VuiDi` / 틀린 코드 `Vn6w4`) — 옛 이메일 방식 계정이 쥔 메일(409 email)도 이 배치 그대로다.
  List<Widget> _codeEntry(VerifyCodeUiState state, VerifyCodeViewModel viewModel) {
    final expiresAt = state.codeExpiresAt;
    return [
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
        // 둘째 줄(errorHint)은 소셜 계정이 쥔 메일에만 있다 — 그때는 아래 [_takenBySocial] 배치다.
        // 이 메일로는 끝낼 수 없다(409 · 422 · 미확인) — 02 로 돌아가 다른 학교 메일을 넣는다(입력값은 비운다).
        if (state.canChooseAnotherEmail)
          Align(
            alignment: Alignment.centerLeft,
            child: MutedTextButton(label: '다른 학교 메일 입력', onPressed: _backToEmail),
          ),
      ],
      // 입력칸(오류가 있으면 오류 문구) → 8 → 스팸함 안내 → 16 → 만료 줄(pen VuiDi · Vn6w4).
      const SizedBox(height: AppSpacing.xs),
      const HintLine(verifyCodeSpamHint),
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
    ];
  }

  /// 03 오류 변형(pen, 소셜 계정이 이미 쥔 학교 메일 — 설계 5-3 B안, 10-17). 이 메일로는 시도가 끝나 임시 연결도 비웠다 —
  /// 코드 칸 · 만료 줄 · 다시 받기 · 스팸함 안내 · 확인 없이 안내 두 줄과 단추만 둔다.
  /// 다른 소셜이면 주 단추 "카카오로 다시 로그인"(누를 때만 로그아웃) 아래 8 에 "다른 학교 메일 입력", 같은 소셜이면 뒤의 것만.
  List<Widget> _takenBySocial(VerifyCodeUiState state, VerifyCodeViewModel viewModel) {
    final relogin = state.reloginLabel;
    final hint = state.errorHint;
    return [
      // 부제 → 첫 줄 간격은 pen 값을 받지 못했다 — 평소 03 의 코드 칸 자리(부제 아래 32)를 그대로 쓴다.
      const SizedBox(height: AppSpacing.xl),
      Row(
        children: [
          const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(state.errorMessage ?? '', style: AppTypography.labelSmall.copyWith(color: AppColors.error)),
          ),
        ],
      ),
      if (hint != null)
        // pen 둘째 줄: 폭 312 · padding [4,0,0,18](첫 줄 글자 시작 = 아이콘 14 + 간격 4) · 14/400 body · 줄높이 1.5.
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs, left: 14 + AppSpacing.xxs),
            child: Text(hint, style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5)),
          ),
        ),
      const Spacer(),
      if (relogin != null) ...[
        AppButton(label: relogin, onPressed: viewModel.relogin),
        const SizedBox(height: AppSpacing.xs),
      ],
      MutedTextButton(label: '다른 학교 메일 입력', onPressed: _backToEmail),
    ];
  }
}

/// 03 앱바(pen AppBar · Sub `KH1hX`, 제목 없음): 높이 56 · 왼쪽 여백 12 · 뒤로 48×48(arrow-left 22 ink).
/// [onBack] 이 null 이면 화살표가 꺼진다(확인 중 · 돌아가는 중).
class _BackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _BackAppBar({required this.onBack});

  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: AppColors.canvas,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: AppSpacing.sm + 48,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        // leading 자리는 높이 56 을 꽉 채운다 — 가운데에 두어야 누름 칸이 pen 대로 48×48 이다.
        child: Center(
          child: IconButton(
            tooltip: '뒤로',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: onBack,
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
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
            const Icon3d(AppIcon3d.clock, size: 16), // pen jYwqT · qVa0s
            const SizedBox(width: 6),
            // 글자를 키우면 줄을 바꾼다(고정 Row 면 오른쪽으로 넘친다).
            Flexible(
              child: Text(
                remaining == Duration.zero ? '코드가 만료됐어요. 메일을 다시 받아 주세요' : '$minutes:$seconds 뒤에 만료돼요',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        );
      },
    );
  }
}
