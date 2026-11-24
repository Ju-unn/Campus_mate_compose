import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/notices/notice_item.dart';
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_field.dart';
import 'package:campus_mate_admin/widgets/admin_text_field.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:flutter/material.dart';

/// 공지 쓰기 대화상자. pen 에 없어 사유 대화상자(ReasonDialog)의 틀을 따른다: 폭 560 · 세로 16 — 제목 → 설명 → 제목 칸(40자) →
/// "내용" + 입력 96(2000자) → 그림(선택: [그림 고르기] · 미리보기 + [그림 빼기]) → (오류 줄) → [취소] + [올리기].
/// 제목 · 내용이 비면 [올리기]가 잠긴다. 처리 중에는 입력 · 단추가 잠기고, 실패는 대화상자에 남는다(오류 줄). 성공하면 true 로 닫는다.
class NoticeCreateDialog extends StatefulWidget {
  const NoticeCreateDialog({super.key, required this.onPick, required this.onSubmit});

  final Future<NoticeImage?> Function() onPick;

  /// 성공이면 null, 실패면 그 실패
  final Future<AdminApiFailure?> Function(String title, String body, NoticeImage? image) onSubmit;

  @override
  State<NoticeCreateDialog> createState() => _NoticeCreateDialogState();
}

class _NoticeCreateDialogState extends State<NoticeCreateDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  NoticeImage? _image;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    NoticeImage? picked;
    var tooLarge = false;
    try {
      picked = await widget.onPick();
    } on NoticeImageTooLarge {
      tooLarge = true; // 브라우저 고르기가 읽기 전에 크기로 거절했다
    }
    if (!mounted || (picked == null && !tooLarge)) return;
    // 서버 상한을 넘는 그림은 보내기 전에 막는다(올리다 끊겨 연결 실패로 보이지 않게)
    tooLarge = tooLarge || picked!.bytes.length > maxNoticeImageBytes;
    setState(() {
      _image = tooLarge ? _image : picked;
      _error = tooLarge ? noticeImageTooLargeText : null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onSubmit(_title.text, _body.text, _image);
    if (!mounted) return;
    if (failure == null) return Navigator.of(context).pop(true);
    setState(() {
      _busy = false;
      _error = noticeSaveErrorText(failure);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    final image = _image;
    return DialogFrame(
      dialogKey: const ValueKey('notice-dialog'),
      width: 560,
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dialogTitle('공지를 올릴까요?'),
          const SizedBox(height: AdminSpacing.md),
          dialogBody('앱 커뮤니티 맨 위에 바로 보여요. 올린 뒤에는 고칠 수 없고 지우기만 할 수 있어요.'),
          const SizedBox(height: AdminSpacing.md),
          AdminField(
            key: const ValueKey('notice-title'),
            label: '제목',
            controller: _title,
            hint: '제목 (40자까지)',
            maxChars: 40,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AdminSpacing.sm),
          Text('내용', style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.body)),
          const SizedBox(height: 6), // AdminField 라벨 → 칸과 같은 값
          AdminTextField(
            key: const ValueKey('notice-body'),
            controller: _body,
            hint: '내용 (2000자까지)',
            multiline: true,
            maxChars: 2000,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AdminSpacing.sm),
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AdminRadius.sm),
              child: Image.memory(
                image.bytes,
                key: const ValueKey('notice-image-preview'),
                height: 160,
                fit: BoxFit.contain,
                // 풀 수 없는 파일 — 서버가 image_type 으로 거절한다. 미리보기 자리만 비운다.
                errorBuilder: (_, _, _) => const SizedBox(height: 160),
              ),
            ),
            const SizedBox(height: AdminSpacing.xs),
          ],
          Wrap(
            spacing: AdminSpacing.xs,
            runSpacing: AdminSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminButton(label: '그림 고르기', variant: AdminButtonVariant.secondary, onPressed: _busy ? null : _pick),
              if (image != null)
                AdminButton(label: '그림 빼기', variant: AdminButtonVariant.text, onPressed: _busy ? null : () => setState(() => _image = null)),
              Text('선택 · JPG · PNG · WEBP, 10MB 까지', style: AdminTypography.xs.copyWith(color: AdminColors.muted)),
            ],
          ),
          if (_error != null) ...[const SizedBox(height: AdminSpacing.xs), ErrorRow(_error!)],
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: _busy ? null : () => Navigator.of(context).pop(),
            confirm: AdminButton(label: '올리기', loading: _busy, onPressed: ready ? _submit : null),
          ),
        ],
      ),
    );
  }
}
