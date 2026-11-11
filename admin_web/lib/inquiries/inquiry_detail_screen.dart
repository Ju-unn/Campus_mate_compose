import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/inquiries/inquiry_controller.dart';
import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:campus_mate_admin/inquiries/inquiry_list_screen.dart' show inquiryStatusTone;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_link.dart';
import 'package:campus_mate_admin/widgets/admin_text_field.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 서버 MEMO_MAX(backend/app/inquiries/reasons.py)와 같다
const int inquiryMemoMax = 1000;

/// 문의 상세(`/inquiries/{id}`). pen 에 문의 화면이 없어 신고 상세(A4)의 틀을 따른다: 내용 32 안쪽, 머리줄 26 → 24 → 두 열(사이 24) —
/// 왼쪽 문의 내용(본문 전체 · 보낸 사람 · 시각 · 답장 메일 복사), 오른쪽 처리(상태 바꾸기 · 메모 저장).
/// 서버에 한 건 조회가 없어 [item](목록에서 고른 줄)이 있어야 열린다 — 주소로 바로 열면 null 이라 목록으로 안내한다.
/// 답장은 이 화면이 보내지 않는다. 운영자가 메일함에서 알림 메일에 '답장'(Reply-To = 사용자가 적은 메일)으로 보내고 여기서는 상태 · 메모만 다룬다.
class InquiryDetailScreen extends StatelessWidget {
  const InquiryDetailScreen({super.key, required this.id, this.item});

  final String id;
  final InquiryItem? item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    if (item == null) {
      return Padding(
        padding: const EdgeInsets.all(AdminSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Head(item: null),
            const SizedBox(height: AdminSpacing.lg),
            AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.searchX, size: 32, color: AdminColors.disabled),
              title: '문의를 찾을 수 없어요',
              body: '주소로 바로 열면 내용을 불러올 수 없어요. 목록에서 다시 골라 주세요.',
              action: AdminButton(label: '문의 목록', variant: AdminButtonVariant.secondary, onPressed: () => context.go(AdminSection.inquiries.path)),
            ),
          ],
        ),
      );
    }
    return _Loaded(seed: item);
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({required this.seed});

  final InquiryItem seed;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  late final TextEditingController _memo = TextEditingController(text: widget.seed.adminMemo ?? '');

  @override
  void initState() {
    super.initState();
    _memo.addListener(() => setState(() {})); // 저장 단추를 켜고 끈다
  }

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  InquiryDetailController get _controller => ref.read(inquiryDetailProvider(widget.seed).notifier);

  Future<void> _after(Future<bool> saving) async {
    final saved = await saving;
    if (saved && mounted) AdminToast.show(context, '저장했어요');
  }

  Future<void> _copyEmail(String email) async {
    await Clipboard.setData(ClipboardData(text: email));
    if (mounted) AdminToast.show(context, '답장 메일을 복사했어요');
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(inquiryDetailProvider(widget.seed));
    final item = detail.item;
    final memoChanged = _memo.text.trim() != (item.adminMemo ?? '');
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(item: item),
          const SizedBox(height: AdminSpacing.lg),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ContentCard(item: item, onCopyEmail: () => _copyEmail(item.replyEmail))),
                  const SizedBox(width: AdminSpacing.lg),
                  Expanded(
                    child: _ActionCard(
                      detail: detail,
                      memo: _memo,
                      memoChanged: memoChanged,
                      onStatus: (status) => _after(_controller.setStatus(status)),
                      onSaveMemo: () => _after(_controller.saveMemo(_memo.text)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 머리줄(신고 상세 b30Jt 와 같다): 높이 26 · 사이 12 — "← 문의 목록" 14/600 web-primary-text, 제목 16/700(폭 가득), 상태 배지(오른쪽 끝).
class _Head extends StatelessWidget {
  const _Head({required this.item});

  final InquiryItem? item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return SizedBox(
      key: const ValueKey('inquiry-head'),
      height: 26,
      child: Row(
        children: [
          TapBox(
            key: const ValueKey('inquiry-back'),
            onTap: () => context.go(AdminSection.inquiries.path),
            radius: AdminRadius.sm,
            child: Text(
              '← 문의 목록',
              semanticsLabel: '문의 목록으로 돌아가기',
              style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.primaryText),
            ),
          ),
          const SizedBox(width: AdminSpacing.sm),
          Expanded(
            child: item == null
                ? const SizedBox.shrink()
                : Semantics(
                    header: true,
                    child: Text(
                      '${inquiryReasonLabel(item.reason)} 문의',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
                    ),
                  ),
          ),
          if (item != null) StatusBadge(item.status.label, tone: inquiryStatusTone(item.status)),
        ],
      ),
    );
  }
}

/// 카드 공통(신고 상세와 같다): web-surface · web-outline 1 · 모서리 14 · 안쪽 24 · 제목 16/700 → 줄들(사이 [gap]).
class _Card extends StatelessWidget {
  const _Card({required this.cardKey, required this.title, required this.children, this.gap = AdminSpacing.xs});

  final Key cardKey;
  final String title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    return Container(
      key: cardKey,
      width: double.infinity,
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
          ),
          for (final child in children) ...[SizedBox(height: gap), child],
        ],
      ),
    );
  }
}

/// 이름 88 14 web-muted · 사이 12 · 값 14/600 web-ink (신고 상세 QLdLH 와 같다). [trailing] 은 값 오른쪽 끝 단추.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.name, required this.value, this.trailing});

  final String name;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 88, child: Text(name, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))),
        const SizedBox(width: AdminSpacing.sm),
        Expanded(child: Text(value, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.ink))),
        if (trailing != null) ...[const SizedBox(width: AdminSpacing.sm), trailing!],
      ],
    );
  }
}

/// 문의 내용 카드: 사유 · 보낸 사람 · 접수 시각 · (답변 시각) · 답장 메일(+ 복사) → 본문 전체(줄바꿈 그대로, 말줄임 없음).
/// 사용자가 쓴 글이라 일반 Text 로만 그린다(HTML · 마크다운으로 읽지 않는다).
class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.item, required this.onCopyEmail});

  final InquiryItem item;
  final VoidCallback onCopyEmail;

  @override
  Widget build(BuildContext context) {
    final answeredAt = item.answeredAt;
    return _Card(
      cardKey: const ValueKey('inquiry-content-card'),
      title: '문의 내용',
      children: [
        _InfoRow(name: '사유', value: inquiryReasonLabel(item.reason)),
        _InfoRow(name: '보낸 사람', value: item.writerLabel),
        _InfoRow(name: '접수 시각', value: formatSubmittedAt(item.createdAt)),
        if (answeredAt != null) _InfoRow(name: '답변 시각', value: formatSubmittedAt(answeredAt)),
        _InfoRow(
          name: '답장 메일',
          value: item.replyEmail,
          trailing: AdminLink(key: const ValueKey('inquiry-copy-email'), label: '복사', onTap: onCopyEmail),
        ),
        const SizedBox(height: AdminSpacing.xs),
        Container(
          key: const ValueKey('inquiry-body'),
          width: double.infinity,
          padding: const EdgeInsets.all(AdminSpacing.md),
          decoration: BoxDecoration(color: AdminColors.surfaceStrong, borderRadius: BorderRadius.circular(AdminRadius.sm)),
          child: Text(item.body, style: AdminTypography.sm.copyWith(color: AdminColors.body)),
        ),
      ],
    );
  }
}

/// 처리 카드: 상태 칩 3(누르면 바로 저장) → 메모 칸 + [메모 저장] → 오류 줄 → 안내.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.detail,
    required this.memo,
    required this.memoChanged,
    required this.onStatus,
    required this.onSaveMemo,
  });

  final InquiryDetail detail;
  final TextEditingController memo;
  final bool memoChanged;
  final ValueChanged<InquiryStatus> onStatus;
  final VoidCallback onSaveMemo;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.body);
    final failure = detail.failure;
    return _Card(
      cardKey: const ValueKey('inquiry-action-card'),
      title: '처리',
      gap: AdminSpacing.sm,
      children: [
        Text('상태', style: labelStyle),
        Wrap(
          spacing: AdminSpacing.xs,
          runSpacing: AdminSpacing.xs,
          children: [
            for (final status in InquiryStatus.values)
              AdminChip(
                key: ValueKey('inquiry-status-${status.code}'),
                label: status.label,
                selected: detail.item.status == status,
                onTap: () => onStatus(status),
              ),
          ],
        ),
        Text('메모 (운영자만 봐요)', style: labelStyle),
        AdminTextField(key: const ValueKey('inquiry-memo'), controller: memo, hint: '처리 내용을 적어 두세요', multiline: true, maxChars: inquiryMemoMax),
        Align(
          alignment: Alignment.centerLeft,
          child: AdminButton(
            label: '메모 저장',
            variant: AdminButtonVariant.secondary,
            loading: detail.saving,
            onPressed: memoChanged ? onSaveMemo : null,
          ),
        ),
        if (failure != null)
          ErrorRow(
            detail.isGone ? '이미 지워진 문의예요. 목록에서 다시 확인해 주세요.' : '저장하지 못했어요. 다시 시도해 주세요.',
            lineHeight: AdminTypography.xsBox,
          ),
        Text(
          '답장은 메일함에서 알림 메일의 "답장"으로 보내 주세요. 보낸 뒤 상태를 "답변 완료"로 바꿔 두면 돼요.',
          style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted),
        ),
      ],
    );
  }
}
