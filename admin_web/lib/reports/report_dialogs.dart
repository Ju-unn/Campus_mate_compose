import 'package:campus_mate_admin/reports/report_controller.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_checkbox.dart';
import 'package:campus_mate_admin/widgets/admin_text_field.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:flutter/material.dart';

/// 대화상자가 처리 실패 말고는 닫히며 돌려주는 것 — 결과와 덤(채팅 앞뒤 줄들)
typedef DialogOutcome<T> = (ActionResult, T?);

const String dialogFailedText = '처리하지 못했어요. 다시 시도해 주세요.';

/// pen Web/Dialog(p8OOG) 틀: 가운데 · web-surface · 모서리 14 · 안쪽 24. 처리 중이면 Esc · 바깥 누름으로 닫히지 않는다.
class DialogFrame extends StatelessWidget {
  const DialogFrame({super.key, required this.dialogKey, required this.width, required this.busy, required this.child});

  /// 시험이 찾는 대화상자 상자(Material)의 열쇠
  final Key dialogKey;
  final double width;
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Center(
        child: ConstrainedBox(
          // 글자를 키우거나 창이 낮아 대화상자가 화면보다 길어지면 화면 90% 까지만 늘고 안이 스크롤된다(맞으면 pen 크기 그대로)
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Material(
            key: dialogKey,
            color: AdminColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadius.md)),
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(AdminSpacing.lg), child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 대화상자 제목 20/700 web-ink(화면 읽기 제목)
Widget dialogTitle(String text) => Semantics(header: true, child: Text(text, style: AdminTypography.lg.copyWith(color: AdminColors.ink)));

/// 설명 14 web-muted(줄 1.5)
Widget dialogBody(String text) => Text(text, style: AdminTypography.sm.copyWith(color: AdminColors.muted));

/// 오른쪽 끝 [취소](보조) + 확인, 사이 8(pen eRiZZ)
Widget dialogButtons({required VoidCallback? onCancel, required Widget confirm}) {
  return Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      spacing: AdminSpacing.xs,
      runSpacing: AdminSpacing.xs,
      children: [AdminButton(label: '취소', variant: AdminButtonVariant.secondary, onPressed: onCancel), confirm],
    ),
  );
}

/// 사유 입력 대화상자(pen C4uUUH 정지 · yNu8b 채팅 보기): 폭 480 · 세로 16 — 제목 20/700 → 설명 14 web-muted(줄 1.5) →
/// 입력 96(사유 필수, 500자) → (실패 오류 줄, 위 8) → [취소] + 확인(정지는 위험 · 그 밖은 주). 사유가 비면 확인이 잠긴다.
/// 처리 중: 확인에 도는 아이콘, 취소 · 입력 잠김. 실패만 대화상자에 남고(오류 줄) 나머지 결과는 닫으며 돌려준다.
class ReasonDialog<T> extends StatefulWidget {
  const ReasonDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.onSubmit,
    this.danger = false,
    this.onDone,
    this.hint = '사유 (필수)',
    this.withdrawnText,
  });

  final String title;
  final String body;
  final String confirmLabel;

  /// 입력 칸 자리 글자(사유 · 메모마다 다르다 — pen 메모 "메모 내용 (글자 수 제한 있음)")
  final String hint;

  /// 탈퇴 계정 409([ActionResult.withdrawn])일 때 오류 줄 글자. 없으면 일반 실패 글자.
  final String? withdrawnText;
  final bool danger;
  final Future<DialogOutcome<T>> Function(String reason) onSubmit;

  /// 있으면 닫지 않고 결과를 넘긴다(같은 자리에서 다음 내용으로 바꿀 때 — [ChatContextFlow])
  final ValueChanged<DialogOutcome<T>>? onDone;

  @override
  State<ReasonDialog<T>> createState() => _ReasonDialogState<T>();
}

class _ReasonDialogState<T> extends State<ReasonDialog<T>> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.onSubmit(_reason.text);
    if (!mounted) return;
    if (outcome.$1 == ActionResult.failed || outcome.$1 == ActionResult.withdrawn) {
      setState(() {
        _busy = false;
        _error = outcome.$1 == ActionResult.withdrawn ? widget.withdrawnText ?? dialogFailedText : dialogFailedText;
      });
      return;
    }
    final onDone = widget.onDone;
    if (onDone != null) return onDone(outcome);
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _reason.text.trim().isNotEmpty;
    return DialogFrame(
      dialogKey: const ValueKey('reason-dialog'),
      width: 480,
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle(widget.title),
          const SizedBox(height: AdminSpacing.md),
          dialogBody(widget.body),
          const SizedBox(height: AdminSpacing.md),
          AdminTextField(
            controller: _reason,
            hint: widget.hint,
            multiline: true,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[const SizedBox(height: AdminSpacing.xs), ErrorRow(_error!)],
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: _busy ? null : () => Navigator.of(context).pop(),
            confirm: AdminButton(
              label: widget.confirmLabel,
              variant: widget.danger ? AdminButtonVariant.danger : AdminButtonVariant.primary,
              loading: _busy,
              onPressed: ready ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 조치 완료 / 기각 대화상자(pen A4_조치_완료 · A4_기각_대화상자, PNG 측정): 폭 480 — 제목 → 16 → 설명 → 16 →
/// "메모 (선택)" 12/600 web-body → 6 → 입력 44(web-outline 1) → 12 → 체크 줄들(사이 12) → 16 → [취소] + 확인(주).
/// 체크: "같은 대상의 열린 신고 n건도 함께 닫기"(n ≥ 1, 기본 켬), 기각 + 자동 가림 중이면 "가림도 함께 해제하기"(기본 켬) +
/// 바로 아래 안내 12 web-muted. 가림 해제가 켜져 있으면 함께 닫기는 켜진 채로 잠긴다 — 서버 가림 해제가 그 사람의 열린 신고를
/// 모두 기각하므로 끈 값은 거짓말이 된다(대장 결정 10-18). 해제를 끄면 잠기기 전 값으로 돌아온다.
class ResolveDialog extends StatefulWidget {
  const ResolveDialog({
    super.key,
    required this.outcome,
    required this.openOthers,
    required this.canUnhide,
    required this.onSubmit,
  });

  final ReportStatus outcome;
  final int openOthers;

  /// 기각이고 대상이 자동 가림 중 — "가림도 함께 해제하기" 를 보인다
  final bool canUnhide;
  final Future<ActionResult> Function(String note, bool sameTarget, bool unhide) onSubmit;

  @override
  State<ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<ResolveDialog> {
  final TextEditingController _note = TextEditingController();
  bool _sameTarget = true;
  bool _unhide = true;
  bool _busy = false;
  bool _failed = false;

  bool get _dismiss => widget.outcome == ReportStatus.dismissed;
  bool get _showUnhide => _dismiss && widget.canUnhide;

  /// 가림 해제가 함께 닫기를 대신한다 — 켜진 채로 잠근다([_sameTarget] 은 사용자가 고른 값으로 남겨 둔다)
  bool get _othersLocked => _showUnhide && _unhide;
  bool get _closesOthers => _othersLocked || _sameTarget;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await widget.onSubmit(_note.text, widget.openOthers > 0 && _closesOthers, _showUnhide && _unhide);
    if (!mounted) return;
    if (result == ActionResult.failed) {
      setState(() {
        _busy = false;
        _failed = true;
      });
      return;
    }
    Navigator.of(context).pop<DialogOutcome<void>>((result, null));
  }

  @override
  Widget build(BuildContext context) {
    final String body;
    if (!_dismiss) {
      body = '신고를 조치 완료로 닫아요. 메모는 작업 기록에 남아요.';
    } else if (widget.canUnhide) {
      body = '이 신고를 기각으로 닫아요. 대상이 자동 가림 중이라 가림 해제 선택이 함께 보여요.';
    } else {
      // pen 에 없는 경우(가림 아님) — 조치 완료 문구와 같은 꼴(대장 보고표)
      body = '이 신고를 기각으로 닫아요. 메모는 작업 기록에 남아요.';
    }
    final checks = [
      if (widget.openOthers > 0)
        AdminCheckbox(
          label: '같은 대상의 열린 신고 ${widget.openOthers}건도 함께 닫기',
          value: _closesOthers,
          onChanged: _busy || _othersLocked ? null : (v) => setState(() => _sameTarget = v),
        ),
      if (_showUnhide)
        AdminCheckbox(label: '가림도 함께 해제하기', value: _unhide, onChanged: _busy ? null : (v) => setState(() => _unhide = v)),
    ];
    final confirmLabel = _dismiss ? '기각' : '조치 완료';
    return DialogFrame(
      dialogKey: const ValueKey('resolve-dialog'),
      width: 480,
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle(_dismiss ? '신고를 기각할까요?' : '조치를 완료할까요?'),
          const SizedBox(height: AdminSpacing.md),
          dialogBody(body),
          const SizedBox(height: AdminSpacing.md),
          Text('메모 (선택)', style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.body)),
          const SizedBox(height: 6), // PNG 측정 — 간격 표에 없는 값
          AdminTextField(
            controller: _note,
            hint: '처리 메모를 남길 수 있어요',
            enabled: !_busy,
            // 한 줄 메모라 Enter 는 확인과 같다(키보드만으로 닫기)
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          for (final check in checks) ...[
            const SizedBox(height: AdminSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: check),
          ],
          if (_showUnhide) ...[
            // 체크 아랫선 ↔ 안내 윗선 12(pen A4_기각_대화상자)
            const SizedBox(height: AdminSpacing.sm),
            Padding(
              // 체크 글자 시작(상자 18 + 10)에 맞춘다
              padding: const EdgeInsets.only(left: AdminCheckbox.labelInset),
              child: Text('가림을 풀면 이 화면에서 본 열린 신고도 함께 기각돼요', style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
            ),
          ],
          if (_failed) ...[const SizedBox(height: AdminSpacing.xs), const ErrorRow(dialogFailedText)],
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: _busy ? null : () => Navigator.of(context).pop(),
            confirm: AdminButton(label: confirmLabel, loading: _busy, onPressed: _submit),
          ),
        ],
      ),
    );
  }
}

/// 채팅 앞뒤 보기 한 번: 사유 대화상자(yNu8b) → 결과(n73XF)를 **한 대화상자 자리에서** 바꾼다. 둘을 따로 띄우면 막(scrim)이
/// 사라졌다 다시 나타나 깜빡인다. 바뀔 때 200ms 투명도 교차(관리자 대화상자 · 관문 카드와 같은 토큰), 동작 줄이기면 바로.
/// 받은 줄은 이 위젯만 들고 있다 — 닫으면 버린다.
class ChatContextFlow extends StatefulWidget {
  const ChatContextFlow({super.key, required this.onSubmit});

  final Future<DialogOutcome<List<ChatLine>>> Function(String reason) onSubmit;

  @override
  State<ChatContextFlow> createState() => _ChatContextFlowState();
}

class _ChatContextFlowState extends State<ChatContextFlow> {
  List<ChatLine>? _lines;

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return AnimatedSwitcher(
      key: const ValueKey('chat-flow'),
      duration: AdminMotion.reduced(context) ? Duration.zero : AdminMotion.enter,
      switchInCurve: AdminMotion.curve,
      switchOutCurve: AdminMotion.curve,
      child: lines == null
          ? ReasonDialog<List<ChatLine>>(
              title: '채팅 앞뒤를 볼까요?',
              body: "신고된 줄 앞뒤 5개씩, 글자만 보여요. 저장되지 않고 작업 기록에 '열람'만 남아요. 사유는 필수예요.",
              confirmLabel: '보기',
              onSubmit: widget.onSubmit,
              onDone: (outcome) => setState(() => _lines = outcome.$2 ?? const []),
            )
          : ChatContextDialog(lines: lines),
    );
  }
}

/// 채팅 앞뒤 결과(pen n73XF · 이름표 p2BSQ, PNG A4_채팅앞뒤_이름표_스크롤 측정): 폭 560 · 안쪽 24 · 세로 12 — 제목 → 설명 →
/// 목록(web-canvas · 모서리 8 · 안쪽 12, 줄 사이 8 — 줄 = 이름표 12 web-muted → 4 → 말풍선) → [닫기](주) 오른쪽.
/// 대화상자는 화면 90% 까지, 넘치면 목록 칸만 스크롤(스크롤바 6 은 목록 오른쪽 4 바깥 — A3 목록과 같은 색).
/// 받은 줄은 이 위젯만 들고 있다 — 닫으면 버린다. 줄이 없으면(대화방 삭제) 같은 제목에 "대화가 지워져 볼 수 없어요".
class ChatContextDialog extends StatefulWidget {
  const ChatContextDialog({super.key, required this.lines});

  final List<ChatLine> lines;

  @override
  State<ChatContextDialog> createState() => _ChatContextDialogState();
}

class _ChatContextDialogState extends State<ChatContextDialog> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const title = '신고된 채팅 앞뒤 보기';
    final close = AdminButton(label: '닫기', onPressed: () => Navigator.of(context).pop());
    if (widget.lines.isEmpty) {
      return DialogFrame(
        dialogKey: const ValueKey('chat-dialog-empty'),
        width: 480,
        busy: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dialogTitle(title),
            const SizedBox(height: AdminSpacing.md),
            dialogBody('대화가 지워져 볼 수 없어요'),
            const SizedBox(height: AdminSpacing.md),
            Align(alignment: Alignment.centerRight, child: close),
          ],
        ),
      );
    }
    const radius = Radius.circular(3);
    // 스크롤바를 목록 칸 오른쪽 바깥(대화상자 안쪽 여백)에 그리려고 오른쪽 안쪽을 10 줄이고 목록 줄만 다시 넓힌다.
    const barGap = 10.0;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            key: const ValueKey('chat-dialog'),
            color: AdminColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadius.md)),
            child: SizedBox(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AdminSpacing.lg, AdminSpacing.lg, AdminSpacing.lg - barGap, AdminSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(padding: const EdgeInsets.only(right: barGap), child: dialogTitle(title)),
                    const SizedBox(height: AdminSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(right: barGap),
                      child: dialogBody("신고된 줄 앞뒤 5개씩, 글자만 보여요. 저장되지 않아요. 작업 기록에는 '열람'만 남아요."),
                    ),
                    const SizedBox(height: AdminSpacing.sm),
                    Flexible(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: RawScrollbar(
                          controller: _scroll,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 6,
                          radius: radius,
                          trackRadius: radius,
                          thumbColor: AdminColors.outlineStrong,
                          trackColor: AdminColors.outline,
                          trackBorderColor: Colors.transparent,
                          crossAxisMargin: 0,
                          // 트랙은 목록 위 14 · 아래 20 안쪽(PNG 측정 240 → 669)
                          padding: const EdgeInsets.only(top: 14, bottom: 20),
                          child: Padding(
                            padding: const EdgeInsets.only(right: barGap),
                            child: Container(
                              key: const ValueKey('chat-list'),
                              decoration: BoxDecoration(color: AdminColors.canvas, borderRadius: BorderRadius.circular(AdminRadius.sm)),
                              child: SingleChildScrollView(
                                controller: _scroll,
                                padding: const EdgeInsets.all(AdminSpacing.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final (i, line) in widget.lines.indexed) ...[
                                      if (i > 0) const SizedBox(height: AdminSpacing.xs),
                                      _ChatBubble(line: line),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AdminSpacing.sm),
                    Padding(padding: const EdgeInsets.only(right: barGap), child: Align(alignment: Alignment.centerRight, child: close)),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

/// pen Web/Chat Bubble · Labeled(GG9J6): 이름표 12 web-muted("신고 대상" / "상대" — 서버 from_target) → 4 → 말풍선
/// (폭 가득 · web-surface-strong · 모서리 14 · 안쪽 [10, 14] · 14 web-ink 줄 1.5). 신고된 줄(pFDqD)은 web-danger-wash 바탕 ·
/// web-danger 1 테두리 · 글자 700 web-danger. 글자는 서버가 준 그대로 일반 Text 로 그린다.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.line});

  final ChatLine line;

  @override
  Widget build(BuildContext context) {
    final reported = line.reported;
    return Column(
      key: ValueKey('chat-line-${line.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          line.fromTarget ? '신고 대상' : '상대',
          style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted),
        ),
        const SizedBox(height: AdminSpacing.xxs),
        Container(
          key: ValueKey('chat-bubble-${line.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), // pen Mrfpw [10, 14] — 간격 표에 없는 값
          decoration: BoxDecoration(
            color: reported ? AdminColors.dangerWash : AdminColors.surfaceStrong,
            borderRadius: BorderRadius.circular(AdminRadius.md),
            border: reported ? Border.all(color: AdminColors.danger) : null,
          ),
          child: Text(
            line.body,
            // 색 · 굵기만으로 알리지 않는다 — 화면 읽기에도 신고된 줄이라고 읽힌다
            semanticsLabel: reported ? '신고된 줄: ${line.body}' : null,
            style: AdminTypography.sm.copyWith(
              color: reported ? AdminColors.danger : AdminColors.ink,
              fontWeight: reported ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
