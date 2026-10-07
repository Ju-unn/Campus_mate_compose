import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 투표 보기의 두 쪽. 찬성(O) 쪽은 파랑 [pollAgreeBlue], 반대(X) 쪽은 빨강 [AppColors.primary].
enum VoteSide { agree, disagree }

enum _VoteOptionKind { mark, text, input }

/// 투표 보기 칸 하나(pen 마스터 `VoteOption · O` `g6Cxp` · `· X` `fmSNT` · `· Input · Blue` `xlCc2` · `· Red` `k9Bdo8`).
/// 질문 작성(17b)의 O/X · 직접 적기 칸과 PollCard 의 투표 버튼이 **같은 파랑 · 빨강 · 높이 72 · 모서리 8** 을 여기서만 읽는다.
///
/// - [VoteOption.mark]: 글자 없는 흰 원(O) · 흰 x(X) 34. 읽기는 [semanticLabel]("찬성" · "반대").
/// - [VoteOption.text]: 직접 적은 보기 글자 — 흰 20/700, 밑줄 없음, 좌우 안쪽 8. 칸보다 길면 줄여서 한 줄에 맞춘다.
/// - [VoteOption.input]: 질문 작성에서 보기 글자를 적는 칸 — 흰 20/700 글자 + 흰 2px 밑줄.
class VoteOption extends StatelessWidget {
  const VoteOption.mark({required this.side, this.semanticLabel, this.onPressed, this.interactive = true, super.key})
      : _kind = _VoteOptionKind.mark,
        label = null,
        controller = null,
        hint = null,
        fieldKey = null,
        inputFormatters = const [],
        onChanged = null;

  const VoteOption.text({required this.side, required String this.label, this.onPressed, super.key})
      : _kind = _VoteOptionKind.text,
        interactive = true,
        semanticLabel = null,
        controller = null,
        hint = null,
        fieldKey = null,
        inputFormatters = const [],
        onChanged = null;

  const VoteOption.input({
    required this.side,
    required TextEditingController this.controller,
    required String this.hint,
    this.fieldKey,
    this.inputFormatters = const [],
    this.onChanged,
    super.key,
  })  : _kind = _VoteOptionKind.input,
        interactive = false,
        semanticLabel = null,
        label = null,
        onPressed = null;

  /// 입력 칸의 흰 밑줄(2px). 시험이 길이를 잰다.
  static const underlineKey = Key('vote-option-underline');

  /// pen 값: 높이 72, 모서리 8([AppRadius.sm]), 글자 흰 20.
  static const double height = 72;
  static const double _markSize = 34;
  static const double _textPadding = 8; // 보기 글자 칸 padding [0,8] — 6자 20px(≈120)가 줄바꿈 없이 들어간다
  static const double _inputPadding = 16; // 입력 칸 padding [0,16]
  static const double _inputGap = 6;
  static const double _underline = 2;

  final VoteSide side;
  final _VoteOptionKind _kind;
  final String? semanticLabel;
  final String? label;
  final VoidCallback? onPressed;

  /// false 면 누르는 버튼이 아니라 그냥 칸이다(질문 작성의 O/X 미리보기).
  final bool interactive;
  final TextEditingController? controller;
  final String? hint;
  final Key? fieldKey;
  final List<TextInputFormatter> inputFormatters;
  final VoidCallback? onChanged;

  Color get _fill => side == VoteSide.agree ? pollAgreeBlue : AppColors.primary;

  static const double _lineHeight = 1.2;

  /// 입력 칸의 글자 배율 상한 — 칸 폭 158(안쪽 126)에 6자 20px 가 한 줄로 들어가는 한계(실제 글꼴 Pretendard 로 잼).
  static const double _maxTextScale = 1.15;

  static TextStyle _whiteText(FontWeight weight) =>
      TextStyle(fontSize: 20, fontWeight: weight, height: _lineHeight, color: AppColors.onPrimary);

  @override
  Widget build(BuildContext context) {
    return switch (_kind) {
      _VoteOptionKind.mark => _frame(
          Icon(side == VoteSide.agree ? AppIcons.circle : AppIcons.x,
              size: _markSize, color: AppColors.onPrimary, semanticLabel: semanticLabel),
          interactive: interactive,
        ),
      _VoteOptionKind.text => _frame(
          FittedBox(fit: BoxFit.scaleDown, child: Text(label!, maxLines: 1, style: _whiteText(FontWeight.w700))),
          interactive: true,
          horizontalPadding: _textPadding,
        ),
      _VoteOptionKind.input => _frame(_inputBody(context), interactive: false, fillChild: true),
    };
  }

  Widget _frame(Widget child, {required bool interactive, double horizontalPadding = 0, bool fillChild = false}) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm));
    if (interactive) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _fill,
          foregroundColor: AppColors.onPrimary,
          // 투표 중(onPressed null)에 칸이 흰색으로 비면 투표마다 깜빡인다 — 같은 색을 반투명으로 둔다.
          disabledBackgroundColor: _fill.withValues(alpha: 0.5),
          disabledForegroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(height),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          shape: shape,
        ),
        child: child,
      );
    }
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: _fill, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: fillChild ? child : Center(child: child),
        ),
      ),
    );
  }

  /// 칸 전체가 입력칸(158 × 72)이라 어디를 눌러도 글자 입력이 시작되고 누르는 곳이 48 을 넘는다.
  /// pen 은 [글자 줄 · 간격 6 · 밑줄 2] 를 칸 가운데에 두므로, 글자는 아래 여백 8 만큼 위로 올려 가운데 두고
  /// (글자 줄 중심 = (72 − 8) / 2) 밑줄은 글자 줄 아래 6 에 따로 얹는다. 글자를 키우면 둘이 같이 내려간다.
  ///
  /// 보기는 한 줄 1~6자다(서버 `OPTION_MAX_LENGTH`): 줄바꿈을 막고(Enter = 완료), 158 폭에 6자가 꺾이지 않도록
  /// **이 입력 칸에서만** 글자 배율을 [_maxTextScale] 까지로 막는다.
  Widget _inputBody(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _maxTextScale);
    final textHeight = scaler.scale(_whiteText(FontWeight.w700).fontSize!) * _lineHeight;
    final underlineTop = (height - (textHeight + _inputGap + _underline)) / 2 + textHeight + _inputGap;
    return Stack(
      children: [
        MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          // 파랑 · 빨강 칸 위라 기본 테마의 선택 색 · 핸들 색이 겹쳐 보인다 — 흰색 계열로 맞춘다.
          child: TextSelectionTheme(
            data: TextSelectionThemeData(
              cursorColor: AppColors.onPrimary,
              selectionColor: AppColors.onPrimary.withValues(alpha: 0.4),
              selectionHandleColor: AppColors.onPrimary,
            ),
            child: TextField(
              key: fieldKey,
              controller: controller,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')), ...inputFormatters],
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              expands: true,
              maxLines: null,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              style: _whiteText(FontWeight.w700),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(_inputPadding, 0, _inputPadding, _inputGap + _underline),
                hintText: hint,
                hintStyle: _whiteText(FontWeight.w500),
              ),
              onChanged: (_) => onChanged?.call(),
            ),
          ),
        ),
        Positioned(
          left: _inputPadding,
          right: _inputPadding,
          top: underlineTop,
          height: _underline,
          child: const IgnorePointer(child: ColoredBox(key: underlineKey, color: AppColors.onPrimary)),
        ),
      ],
    );
  }
}
