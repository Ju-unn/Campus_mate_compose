import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/code_input.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A1 등록 · 입력이 같이 쓰는 아래쪽: 6칸 → (오류 줄) → "확인"(주 단추, 가득), 사이 20(PNG 측정).
/// 확인에 성공하면 세션이 aal2 가 되고 관문이 알아서 다음 화면으로 보낸다 — 여기서 화면을 옮기지 않는다.
/// 6자리를 다 치면(붙여넣기 포함) 확인 단추를 누르지 않아도 바로 확인한다. 고쳐 치기 시작하면 오류 줄을 내린다.
class CodeForm extends ConsumerStatefulWidget {
  const CodeForm({super.key, required this.factorId});

  final String factorId;

  @override
  ConsumerState<CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends ConsumerState<CodeForm> {
  final TextEditingController _code = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String code) {
    if (_error != null) setState(() => _error = null);
    if (code.length == CodeInput.length) _submit();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.length != CodeInput.length) {
      setState(() => _error = '6자리 숫자를 모두 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref.read(adminAuthProvider).verifyTotp(factorId: widget.factorId, code: _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (outcome) {
        VerifyOutcome.ok => null,
        VerifyOutcome.wrongCode => '코드가 맞지 않아요. 다시 확인해 주세요.',
        VerifyOutcome.failed => '연결하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeInput(controller: _code, focusNode: _focus, onSubmitted: _submit, onChanged: _onChanged),
        if (error != null) ...[
          const SizedBox(height: AdminSpacing.gateBlock),
          ErrorRow(error),
        ],
        const SizedBox(height: AdminSpacing.gateBlock),
        AdminButton(label: '확인', expand: true, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
