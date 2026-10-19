import 'package:campus_mate_admin/reports/report_controller.dart' show ActionResult;
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_motion.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_field.dart';
import 'package:campus_mate_admin/widgets/admin_text_field.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 한 번에 더하거나 뺄 수 있는 하트 수(서버 ADJUST_MAX · DB 함수 c_max_adjust 와 같은 값)
const int heartAdjustMax = 1000;

/// 안내 한 칸(pen c7JpKU · lcIIF · nf9ZF): 바탕색 · 모서리 8 · 안쪽 12.
Widget _box({required Color color, required Widget child, Key? key}) {
  return Container(
    key: key,
    padding: const EdgeInsets.all(AdminSpacing.sm),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AdminRadius.sm)),
    child: child,
  );
}

/// 하트 수 칸에 넣을 수 있는 글자: 앞의 부호(+ · -)와 숫자 여섯 자까지. 그 밖의 글자는 들어가지 않는다(붙여넣기도).
class _AmountFormatter extends TextInputFormatter {
  static final RegExp _allowed = RegExp(r'^[+-]?\d{0,6}$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return _allowed.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// 칸 글자 → 하트 수. 0 · 부호만 · ±[heartAdjustMax] 넘음 · 숫자가 아님은 null(확인이 잠긴다).
int? parseHeartAmount(String text) {
  final value = int.tryParse(text.trim());
  if (value == null || value == 0 || value.abs() > heartAdjustMax) return null;
  return value;
}

/// 하트 조정 대화상자(pen kFJPd · A5_하트_조정_대화상자 · _잔액_모자람 측정): 폭 480 · 세로 16 — 제목 → 설명 → 입력 묶음(세로 12:
/// 결제 안내 → 하트 수 칸 → 안내 12 muted(항상) → 사유 96 → (오류 줄)) → [취소] + [조정]. 하트 수 · 사유가 맞아야 [조정] 이 풀린다.
/// 잔액이 모자라면(409) 오류 줄 "잔액이 모자라요". 성공하면 닫으며 돌려준다.
class HeartAdjustDialog extends StatefulWidget {
  const HeartAdjustDialog({super.key, required this.nickname, required this.onSubmit});

  final String nickname;
  final Future<ActionResult> Function(int amount, String reason) onSubmit;

  @override
  State<HeartAdjustDialog> createState() => _HeartAdjustDialogState();
}

class _HeartAdjustDialogState extends State<HeartAdjustDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parseHeartAmount(_amount.text);
    if (amount == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSubmit(amount, _reason.text);
    if (!mounted) return;
    final error = switch (result) {
      ActionResult.insufficientHearts => '잔액이 모자라요',
      ActionResult.withdrawn => '이미 탈퇴한 계정이에요',
      ActionResult.failed => dialogFailedText,
      _ => null,
    };
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop<ActionResult>(result);
  }

  @override
  Widget build(BuildContext context) {
    final ready = parseHeartAmount(_amount.text) != null && _reason.text.trim().isNotEmpty;
    final error = _error;
    return DialogFrame(
      dialogKey: const ValueKey('heart-dialog'),
      width: 480,
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle('하트를 조정할까요?'),
          const SizedBox(height: AdminSpacing.md),
          dialogBody('${widget.nickname} 의 하트를 더하거나 빼요. 빼면 잔액이 모자랄 때 거절돼요.'),
          const SizedBox(height: AdminSpacing.md),
          _box(
            key: const ValueKey('heart-notice'),
            color: AdminColors.primaryWash,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.info, size: 16, color: AdminColors.primaryText),
                const SizedBox(width: AdminSpacing.xs),
                Expanded(
                  child: Text(
                    '결제 문의라면 먼저 결제 조회로 이미 지급됐는지 확인해 주세요. 손으로 주면 앱이 영수증을 다시 보낼 때 두 번 지급될 수 있어요.',
                    style: AdminTypography.xs.copyWith(color: AdminColors.primaryText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AdminSpacing.sm),
          AdminField(
            label: '하트 수 (더하면 +, 빼면 -)',
            controller: _amount,
            hint: '+50',
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            inputFormatters: [_AmountFormatter()],
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AdminSpacing.sm),
          Text('한 번에 1,000개까지 더하거나 뺄 수 있어요', style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
          const SizedBox(height: AdminSpacing.sm),
          AdminTextField(controller: _reason, hint: '사유 (필수)', multiline: true, enabled: !_busy, onChanged: (_) => setState(() {})),
          if (error != null) ...[const SizedBox(height: AdminSpacing.sm), ErrorRow(error, lineHeight: AdminTypography.xsBox)],
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: _busy ? null : () => Navigator.of(context).pop(),
            confirm: AdminButton(label: '조정', loading: _busy, onPressed: ready ? _submit : null),
          ),
        ],
      ),
    );
  }
}

/// 전화 · 카톡 열람 한 번: 사유 대화상자(pen zcICW) → 결과(A5_전화카톡_열람_결과)를 **한 대화상자 자리에서** 바꾼다
/// (채팅 앞뒤 보기와 같은 흐름). 받은 값은 이 위젯의 State 만 들고 있다 — 닫으면 버린다(전역 provider · 캐시 없음).
class PrivateViewFlow extends StatefulWidget {
  const PrivateViewFlow({super.key, required this.onSubmit});

  final Future<DialogOutcome<PrivateContact>> Function(String reason) onSubmit;

  @override
  State<PrivateViewFlow> createState() => _PrivateViewFlowState();
}

class _PrivateViewFlowState extends State<PrivateViewFlow> {
  PrivateContact? _contact;

  @override
  void dispose() {
    _contact = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    return AnimatedSwitcher(
      key: const ValueKey('private-flow'),
      duration: AdminMotion.reduced(context) ? Duration.zero : AdminMotion.enter,
      switchInCurve: AdminMotion.curve,
      switchOutCurve: AdminMotion.curve,
      child: contact == null
          ? ReasonDialog<PrivateContact>(
              title: '전화·카톡을 열람할까요?',
              body: "그 자리에서만 보여 주고 저장하지 않아요. 작업 기록에 '열람'만 남아요.",
              confirmLabel: '열람',
              withdrawnText: '탈퇴한 계정은 열람할 수 없어요',
              onSubmit: widget.onSubmit,
              onDone: (outcome) => setState(() => _contact = outcome.$2),
            )
          : PrivateContactDialog(contact: contact),
    );
  }
}

/// 열람 결과(pen A5_전화카톡_열람_결과, PNG 측정): 폭 480 · 세로 16 — 제목 "전화·카톡" → 묶음(세로 12: 이름 12/600 web-muted →
/// 6 → 값 16/700 web-ink 두 쌍 → 안내 12 web-muted) → [닫기](주). 값은 끌어서 복사할 수 있다. 없으면 "없음" web-muted.
class PrivateContactDialog extends StatelessWidget {
  const PrivateContactDialog({super.key, required this.contact});

  final PrivateContact contact;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      dialogKey: const ValueKey('private-dialog'),
      width: 480,
      busy: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle('전화·카톡'),
          const SizedBox(height: AdminSpacing.md),
          _ContactValue(name: '전화번호', value: contact.phoneNumber),
          const SizedBox(height: AdminSpacing.sm),
          _ContactValue(name: '카카오톡 아이디', value: contact.kakaoId),
          const SizedBox(height: AdminSpacing.sm),
          Text('창을 닫으면 지워져요. 다시 보려면 다시 열람해야 하고 기록이 한 번 더 남아요.', style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
          const SizedBox(height: AdminSpacing.md),
          Align(alignment: Alignment.centerRight, child: AdminButton(label: '닫기', onPressed: () => Navigator.of(context).pop())),
        ],
      ),
    );
  }
}

class _ContactValue extends StatelessWidget {
  const _ContactValue({required this.name, required this.value});

  final String name;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        const SizedBox(height: 6), // pen A8 결과 칸과 같은 이름 → 값 6 — 간격 표에 없는 값
        // 대화상자는 페이지의 SelectionArea 밖이라 값만 따로 선택할 수 있게 한다
        SelectableText(
          value ?? '없음',
          style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: value == null ? AdminColors.muted : AdminColors.ink),
        ),
      ],
    );
  }
}

/// 탈퇴 대행 대화상자(pen PaxWw · A5_탈퇴_대행_* 측정): 폭 480 · 세로 16 — 제목 → 설명 → 묶음(세로 12: 본인 확인 3줄 → (정지 경고) →
/// 애플 안내 → 확인 방법 → ("@" 경고) → 사유 → (오류 줄)) → [취소] + [탈퇴 대행](위험).
/// 확인 방법 · 사유가 둘 다 차야 [탈퇴 대행] 이 풀리고, 확인 방법에 "@" 가 있으면 잠긴다(메일 주소가 작업 기록에 남지 않게).
/// 본인 확인 줄은 체크 칸이 아니라 안내다 — 학교 메일 줄은 원문 없이 "직접 확인".
class CloseAccountDialog extends StatefulWidget {
  const CloseAccountDialog({super.key, required this.nickname, required this.providers, required this.suspended, required this.onSubmit});

  final String nickname;

  /// 로그인 방식 코드들(없거나 모르면 null · 빈 목록)
  final List<String>? providers;

  /// 정지 중인 계정 — 경고 줄을 보인다
  final bool suspended;
  final Future<DialogOutcome<CloseAccountResult>> Function(String reason, String verifiedBy) onSubmit;

  @override
  State<CloseAccountDialog> createState() => _CloseAccountDialogState();
}

class _CloseAccountDialogState extends State<CloseAccountDialog> {
  final TextEditingController _verified = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _verified.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.onSubmit(_reason.text, _verified.text);
    if (!mounted) return;
    final result = outcome.$1;
    if (result == ActionResult.failed || result == ActionResult.withdrawn) {
      setState(() {
        _busy = false;
        _error = result == ActionResult.withdrawn ? '이미 탈퇴한 계정이에요' : dialogFailedText;
      });
      return;
    }
    Navigator.of(context).pop<DialogOutcome<CloseAccountResult>>(outcome);
  }

  Widget _checkLine(String text) {
    return Row(
      children: [
        const Icon(LucideIcons.squareCheck, size: 18, color: AdminColors.success),
        const SizedBox(width: AdminSpacing.xs),
        Expanded(child: Text(text, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.ink))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.providers;
    final login = providers == null || providers.isEmpty ? '직접 확인' : providers.map(loginProviderName).join(' · ');
    final hasAt = _verified.text.contains('@');
    final ready = _verified.text.trim().isNotEmpty && !hasAt && _reason.text.trim().isNotEmpty;
    final error = _error;
    const gap = SizedBox(height: AdminSpacing.sm);
    return DialogFrame(
      dialogKey: const ValueKey('close-dialog'),
      width: 480,
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle('탈퇴를 대행할까요?'),
          const SizedBox(height: AdminSpacing.md),
          dialogBody('되돌릴 수 없어요. 본인 확인을 마친 뒤에만 실행해요.'),
          const SizedBox(height: AdminSpacing.md),
          _box(
            key: const ValueKey('close-identity'),
            color: AdminColors.canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '본인 확인 (요청과 맞는지 확인해 주세요)',
                  style: AdminTypography.xs.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.xsBox, color: AdminColors.body),
                ),
                const SizedBox(height: AdminSpacing.xs),
                _checkLine('로그인 방식: $login'),
                const SizedBox(height: AdminSpacing.xs),
                _checkLine('학교 메일: 요청과 맞는지 직접 확인'),
                const SizedBox(height: AdminSpacing.xs),
                _checkLine('닉네임: ${widget.nickname} 와 일치'),
              ],
            ),
          ),
          if (widget.suspended) ...[
            gap,
            _box(
              key: const ValueKey('close-suspended'),
              color: AdminColors.warningWash,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 18, color: AdminColors.warning),
                  const SizedBox(width: AdminSpacing.xs),
                  Expanded(
                    child: Text('정지 중인 계정이에요. 탈퇴시키면 같은 학교 메일 재가입이 기간 없이 막혀요.', style: AdminTypography.sm.copyWith(color: AdminColors.warning)),
                  ),
                ],
              ),
            ),
          ],
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.info, size: 16, color: AdminColors.muted),
              const SizedBox(width: AdminSpacing.xs),
              Expanded(child: Text('애플 철회와 전체 로그아웃은 본인 토큰이 필요해서 대행할 수 없어요.', style: AdminTypography.xs.copyWith(color: AdminColors.muted))),
            ],
          ),
          gap,
          AdminField(
            label: '어떻게 확인했나요 (필수)',
            controller: _verified,
            hint: '예: 가입 메일로 답장을 받아 확인했어요',
            enabled: !_busy,
            maxChars: 200, // 서버 VERIFIED_BY_MAX
            onChanged: (_) => setState(() {}),
          ),
          if (hasAt) ...[
            gap,
            Text('메일 주소는 적지 마세요(기록에 남아요)', style: AdminTypography.xs.copyWith(color: AdminColors.danger)),
          ],
          gap,
          AdminField(label: '사유 (필수)', controller: _reason, hint: '사유를 적어 주세요', enabled: !_busy, onChanged: (_) => setState(() {})),
          if (error != null) ...[gap, ErrorRow(error)],
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: _busy ? null : () => Navigator.of(context).pop(),
            confirm: AdminButton(label: '탈퇴 대행', variant: AdminButtonVariant.danger, loading: _busy, onPressed: ready ? _submit : null),
          ),
        ],
      ),
    );
  }
}
