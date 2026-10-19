import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/heart_tasks/proof_photo_viewer.dart';
import 'package:campus_mate_admin/reports/report_controller.dart';
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/reports/report_list_screen.dart' show reportStatusTone;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A4 신고 상세(pen gHMhM · 1440×900). 주소 `/reports/{id}` — 디스코드 알림 링크도 여기로 온다.
/// 내용 32 안쪽: 머리줄 26(b30Jt) → 24 → 두 열(gEEQE, 사이 24 · 열 안 16) — 왼쪽 사본 · 대상 요약, 오른쪽 다른 신고 · 조치.
/// [summary] 는 목록에서 고른 줄(받는 동안 머리줄을 그린다). 링크로 열면 null.
class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({super.key, required this.id, this.summary});

  final String id;
  final ReportSummary? summary;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  /// 기각은 됐는데 이어 부른 가림 해제가 실패했다 — 조치 카드 오류 줄(다음 조치까지)
  bool _unhideFailed = false;

  ReportDetailController get _controller => ref.read(reportDetailProvider(widget.id).notifier);

  Future<void> _after(ActionResult? result) async {
    if (!mounted || result == null) return;
    switch (result) {
      case ActionResult.done:
        AdminToast.show(context, '처리했어요');
      case ActionResult.unhideFailed:
        setState(() => _unhideFailed = true);
      case ActionResult.alreadyDone:
        await showAdminDialog<void>(
          context,
          (_) => const AdminDialog(title: '이미 처리된 항목이에요', body: '다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.'),
        );
      case ActionResult.failed || ActionResult.insufficientHearts || ActionResult.withdrawn:
        break;
    }
  }

  /// 사유 필수 조치(정지 · 해제 · 가림 해제 · 글 가림 · 글 해제)
  Future<void> _withReason({
    required String title,
    required String body,
    required String confirm,
    bool danger = false,
    required Future<ActionResult> Function(String reason) action,
  }) async {
    setState(() => _unhideFailed = false);
    final outcome = await showAdminDialog<DialogOutcome<void>>(
      context,
      (_) => ReasonDialog<void>(
        title: title,
        body: body,
        confirmLabel: confirm,
        danger: danger,
        onSubmit: (reason) async => (await action(reason), null),
      ),
    );
    await _after(outcome?.$1);
  }

  Future<void> _resolve(ReportDetail detail, ReportStatus outcome) async {
    setState(() => _unhideFailed = false);
    // 대화상자의 "열린 신고 n건" 과 서버로 보내는 id 를 같은 목록에서 만든다
    final seen = detail.openOtherIds;
    final result = await showAdminDialog<DialogOutcome<void>>(
      context,
      (_) => ResolveDialog(
        outcome: outcome,
        openOthers: seen.length,
        canUnhide: detail.summary.target?.isAutoHidden ?? false,
        onSubmit: (note, sameTarget, unhide) =>
            _controller.resolve(outcome, note: note, sameTarget: sameTarget, unhide: unhide, seenReportIds: seen),
      ),
    );
    await _after(result?.$1);
  }

  Future<void> _viewChat() => showAdminDialog<void>(context, (_) => ChatContextFlow(onSubmit: _controller.viewChat));

  List<Widget> _actionButtons(ReportDetail detail) {
    final summary = detail.summary;
    final target = summary.target;
    final name = target?.displayName ?? missingValue;
    final contentName = summary.type == ReportTargetType.poll ? '투표 글' : '지인 리뷰';
    final people = <Widget>[
      if (target != null && target.isSuspended)
        AdminButton(
          label: '정지 해제',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _withReason(
            title: '정지를 해제할까요?',
            body: '$name 의 정지를 풀어요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '정지 해제',
            action: (reason) => _controller.actOnProfile(ProfileAction.unsuspend, reason),
          ),
        )
      else if (target != null && target.canSuspend)
        AdminButton(
          label: '정지',
          variant: AdminButtonVariant.danger,
          onPressed: () => _withReason(
            title: '사용자를 정지할까요?',
            body: '$name 를 정지해요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '정지',
            danger: true,
            action: (reason) => _controller.actOnProfile(ProfileAction.suspend, reason),
          ),
        ),
      if (target != null && target.isAutoHidden)
        AdminButton(
          label: '가림 해제',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _withReason(
            title: '가림을 해제할까요?',
            body: '$name 의 자동 가림을 풀고, 이 화면에서 본 열린 신고만 기각돼요(그 뒤 들어온 신고는 남아요). 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '가림 해제',
            action: (reason) => _controller.actOnProfile(ProfileAction.unhide, reason),
          ),
        ),
      if (summary.type.isContent && detail.contentStatus == ContentStatus.visible)
        AdminButton(
          label: '글 가림',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _withReason(
            title: '글을 가릴까요?',
            body: '이 $contentName 을 앱에서 가려요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '글 가림',
            action: (reason) => _controller.setContent(blind: true, reason: reason),
          ),
        ),
      if (summary.type.isContent && detail.contentStatus == ContentStatus.blinded)
        AdminButton(
          label: '글 가림 해제',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _withReason(
            title: '글 가림을 해제할까요?',
            body: '가린 $contentName 을 앱에 다시 보여요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '글 가림 해제',
            action: (reason) => _controller.setContent(blind: false, reason: reason),
          ),
        ),
    ];
    final report = <Widget>[
      if (summary.isOpen) ...[
        AdminButton(label: '조치 완료', onPressed: () => _resolve(detail, ReportStatus.actioned)),
        AdminButton(
          label: '기각',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _resolve(detail, ReportStatus.dismissed),
        ),
      ],
      if (summary.type == ReportTargetType.message)
        AdminButton(label: '채팅 앞뒤 보기', variant: AdminButtonVariant.secondary, onPressed: _viewChat),
    ];
    // 열린 신고는 두 줄(사람 · 글 / 닫기 · 채팅), 닫힌 신고는 남은 단추를 한 줄에(pen A4_상세_닫힌_신고 — 대장 검토 10-18)
    final rows = summary.isOpen ? [people, report] : [[...people, ...report]];
    return [
      for (final row in rows)
        if (row.isNotEmpty) Wrap(spacing: AdminSpacing.xs, runSpacing: AdminSpacing.xs, children: row),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportDetailProvider(widget.id));
    final detail = state.value;
    final summary = detail?.summary ?? widget.summary;
    final Widget content;
    if (state.hasError) {
      final error = state.error;
      final missing = error is AdminApiFailure && (error.statusCode == 404 || error.statusCode == 422);
      content = missing
          ? AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.searchX, size: 32, color: AdminColors.disabled),
              title: '신고를 찾을 수 없어요',
              body: '지워졌거나 주소가 틀렸어요. 목록에서 다시 골라 주세요.',
              action: AdminButton(
                label: '신고 목록',
                variant: AdminButtonVariant.secondary,
                onPressed: () => context.go(AdminSection.reports.path),
              ),
            )
          : AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
              title: '신고를 불러오지 못했어요',
              body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
              action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: _controller.retry),
              alert: true,
            );
    } else if (detail == null) {
      content = const AdminTableEmpty(framed: false, leading: AdminLoader(color: AdminColors.muted), body: '신고 내용을 불러오고 있어요');
    } else {
      content = Expanded(
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _CopyCard(detail: detail, onOpenPhoto: (url) => showPhotoZoom(context, url)),
                    const SizedBox(height: AdminSpacing.md),
                    _TargetCard(detail: detail),
                  ],
                ),
              ),
              const SizedBox(width: AdminSpacing.lg),
              Expanded(
                child: Column(
                  children: [
                    _OthersCard(detail: detail),
                    const SizedBox(height: AdminSpacing.md),
                    _ActionCard(detail: detail, buttons: _actionButtons(detail), unhideFailed: _unhideFailed),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(summary: summary, reporters: detail?.openReporters),
          const SizedBox(height: AdminSpacing.lg),
          content,
        ],
      ),
    );
  }
}

/// 머리줄(b30Jt): 높이 26 · 사이 12 — "← 신고 목록" 14/600 web-primary-text, 제목 16/700(폭 가득), 상태 배지(오른쪽 끝).
/// 제목 "{종류} 신고 · n명 신고" 의 n 은 같은 대상의 열린 신고자 수(상세에만 있다 — 받기 전에는 종류만).
class _Head extends StatelessWidget {
  const _Head({required this.summary, required this.reporters});

  final ReportSummary? summary;
  final int? reporters;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final reporters = this.reporters;
    return SizedBox(
      key: const ValueKey('report-head'),
      height: 26,
      child: Row(
        children: [
          TapBox(
            key: const ValueKey('report-back'),
            onTap: () => context.go(AdminSection.reports.path),
            radius: AdminRadius.sm,
            child: Text(
              '← 신고 목록',
              semanticsLabel: '신고 목록으로 돌아가기',
              style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.primaryText),
            ),
          ),
          const SizedBox(width: AdminSpacing.sm),
          Expanded(
            child: summary == null
                ? const SizedBox.shrink()
                : Semantics(
                    header: true,
                    child: Text(
                      reporters == null ? summary.type.detailTitle : '${summary.type.detailTitle} · $reporters명 신고',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
                    ),
                  ),
          ),
          if (summary != null) StatusBadge(summary.status.badgeLabel, tone: reportStatusTone(summary.status)),
        ],
      ),
    );
  }
}

/// 카드 공통(pen): web-surface · web-outline 1 · 모서리 14 · 안쪽 24 · 제목 16/700 → 줄들(사이 [gap] — 조치 카드 12, 그 밖 8).
class _Card extends StatelessWidget {
  const _Card({required this.cardKey, required this.title, required this.children, this.gap = AdminSpacing.xs});

  /// 시험이 찾는 카드 상자의 열쇠
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
            child: Text(
              title,
              style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
            ),
          ),
          for (final child in children) ...[SizedBox(height: gap), child],
        ],
      ),
    );
  }
}

TextStyle get _bodyText => AdminTypography.sm.copyWith(color: AdminColors.body);

TextStyle get _bodyLine => AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.body);

/// 이름 · 값 한 줄(QLdLH): 이름 88 14 web-muted · 사이 12 · 값 14/600 web-ink(또는 배지), 줄 19(배지 줄 26).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.name, this.value, this.badge});

  final String name;
  final String? value;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: badge == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 88,
          child: Text(name, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
        ),
        const SizedBox(width: AdminSpacing.sm),
        Expanded(
          child: badge == null
              ? Text(
                  value ?? missingValue,
                  style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.ink),
                )
              : Align(alignment: Alignment.centerLeft, child: badge),
        ),
      ],
    );
  }
}

/// 신고 당시 사본(b3uykT) — 맨 위 "신고 사유" 줄 + "기타" 메모(reason_note, 있을 때만 — 대장 지시 10-18, pen 도 같이 고침),
/// 그 아래 종류마다(⑥): 메시지 글 · 프로필(닉네임 · 소개 · 썸네일) · 투표 글(질문 · 선택지 2) · 지인 리뷰(태그 · 한마디)
class _CopyCard extends StatelessWidget {
  const _CopyCard({required this.detail, required this.onOpenPhoto});

  final ReportDetail detail;
  final ValueChanged<String> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final snapshot = detail.snapshot;
    String text(String key) => snapshot.text(key) ?? missingValue;
    final summary = detail.summary;
    final type = summary.type;
    final note = summary.reasonNote;
    final reason = [
      _InfoRow(name: '신고 사유', value: reportReasonLabel(summary.reason)),
      // 신고자가 쓴 글 그대로 — 줄을 바꿔 다 보인다(일반 Text). 공백뿐이면 줄을 두지 않는다.
      if (note != null && note.trim().isNotEmpty) Text('메모: $note', style: _bodyText),
    ];
    final content = switch (type) {
      ReportTargetType.message => [Text('신고된 메시지: "${text('body')}"', style: _bodyText)],
      ReportTargetType.profile => _profile(snapshot),
      ReportTargetType.poll => [
        Text('질문: ${text('question')}', style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.ink)),
        Text('선택지 1 · ${text('option_a_label')}', style: _bodyLine),
        Text('선택지 2 · ${text('option_b_label')}', style: _bodyLine),
      ],
      ReportTargetType.friendReview => [
        if (snapshot.tags.isNotEmpty)
          Wrap(
            spacing: AdminSpacing.xs,
            runSpacing: AdminSpacing.xs,
            children: [for (final (i, tag) in snapshot.tags.indexed) _TagChip(key: ValueKey('review-tag-$i'), label: tag)],
          ),
        Text('한마디: ${text('comment')}', style: _bodyText),
      ],
    };
    return _Card(cardKey: const ValueKey('report-copy'), title: type.copyTitle, children: [...reason, ...content]);
  }

  List<Widget> _profile(ReportSnapshot snapshot) {
    final avatar = snapshot.avatarUrl;
    final photos = snapshot.photoUrls;
    return [
      _InfoRow(name: '닉네임', value: snapshot.text('nickname')),
      Text('소개: ${snapshot.text('bio') ?? missingValue}', style: _bodyText),
      Wrap(
        spacing: AdminSpacing.md,
        runSpacing: AdminSpacing.xs,
        children: [
          _Thumb(thumbKey: const ValueKey('report-thumb-avatar'), url: avatar, caption: '공개 아바타', onOpen: onOpenPhoto),
          if (photos.isEmpty)
            _Thumb(thumbKey: const ValueKey('report-thumb-photo-0'), url: null, caption: '실사진', onOpen: onOpenPhoto)
          else
            for (final (i, url) in photos.indexed)
              _Thumb(thumbKey: ValueKey('report-thumb-photo-$i'), url: url, caption: '실사진', onOpen: onOpenPhoto),
        ],
      ),
      if (avatar != null || photos.isNotEmpty)
        Text('썸네일을 누르면 크게 보여요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
    ];
  }
}

/// 리뷰 태그 칩 — 누를 수 없는 Web/Chip(꺼짐 xL1CC) 모양: 높이 36 · 좌우 14 · 14/600 web-body · web-outline 1 · 알약
class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AdminSizes.chip,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AdminRadius.pill),
        border: Border.all(color: AdminColors.outline),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(label, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.body)),
      ),
    );
  }
}

/// pen Web/Thumb(vKr36 · No Photo Iy6MD, PNG 측정): 72×72 · web-surface-strong · web-outline 1 · 모서리 8 → 6 → 이름표 12 web-muted.
/// 사진은 꽉 채움(cover), 받는 동안 image 24 web-disabled. 없거나 못 그리면 image-off 24 + 4 + "사진 없음" 12 web-muted(누를 수 없음).
/// 누르면 A3 와 같은 크게 보기.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.thumbKey, required this.url, required this.caption, required this.onOpen});

  static const double size = 72;

  final Key thumbKey;
  final String? url;
  final String caption;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final noPhoto = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.imageOff, size: 24, color: AdminColors.disabled),
          const SizedBox(height: AdminSpacing.xxs),
          Text('사진 없음', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TapBox(
          key: thumbKey,
          onTap: url == null ? null : () => onOpen(url),
          cursor: SystemMouseCursors.zoomIn,
          semanticLabel: url == null ? null : '$caption 크게 보기',
          color: AdminColors.surfaceStrong,
          side: const BorderSide(color: AdminColors.outline),
          width: size,
          height: size,
          child: url == null
              ? noPhoto
              : ProofImage(
                  url: url,
                  fit: BoxFit.cover,
                  onError: (_) {},
                  loading: const Center(child: Icon(LucideIcons.image, size: 24, color: AdminColors.disabled)),
                  fallback: noPhoto,
                ),
        ),
        const SizedBox(height: 6), // PNG 측정 — 간격 표에 없는 값
        Text(caption, style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
      ],
    );
  }
}

/// 대상 요약(QLdLH): 닉네임(리뷰는 작성자) · 학교 · 상태(투표 · 리뷰는 글 상태 배지) · 받은 신고
class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.detail});

  final ReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final target = summary.target;
    final type = summary.type;
    final Widget status;
    if (type.isContent) {
      final (label, tone) = switch (detail.contentStatus) {
        ContentStatus.visible => ('보임', StatusTone.success),
        ContentStatus.blinded => ('가려짐', StatusTone.danger),
        // 글이 지워졌다 — pen 에 없는 값(대장 보고표)
        null => ('지워짐', StatusTone.neutral),
      };
      status = _InfoRow(name: '글 상태', badge: StatusBadge(label, tone: tone));
    } else {
      status = _InfoRow(name: '상태', value: target?.statusLabel);
    }
    return _Card(
      cardKey: const ValueKey('report-target'),
      title: '대상 요약',
      children: [
        _InfoRow(name: type == ReportTargetType.friendReview ? '작성자' : '닉네임', value: target?.displayName),
        _InfoRow(name: '학교', value: target?.university),
        status,
        _InfoRow(name: '받은 신고', value: '${detail.openReporters}명'),
      ],
    );
  }
}

/// 같은 대상의 다른 신고(kZJtf): 줄마다 "사유 · 시각 · 상태" 14 web-body(최근 순 최대 20 — 서버)
class _OthersCard extends StatelessWidget {
  const _OthersCard({required this.detail});

  final ReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final others = detail.otherReports;
    return _Card(
      cardKey: const ValueKey('report-others'),
      title: '같은 대상의 다른 신고',
      children: others.isEmpty
          // pen 에 없는 상태(대장 보고표)
          ? [Text('다른 신고가 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))]
          : [
              for (final other in others)
                Text('${reportReasonLabel(other.reason)} · ${formatSubmittedAt(other.createdAt)} · ${other.status.label}', style: _bodyLine),
            ],
    );
  }
}

/// 조치(eKM6S): 사이 12 — 단추 줄(사람 · 글) → 단추 줄(닫기 · 채팅) → (닫힌 신고 "처리됨 · 시각" 14 web-muted) → 안내 12 web-muted.
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.detail, required this.buttons, required this.unhideFailed});

  final ReportDetail detail;
  final List<Widget> buttons;
  final bool unhideFailed;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final resolvedAt = summary.resolvedAt;
    final muted = AdminTypography.xs.copyWith(color: AdminColors.muted);
    return _Card(
      cardKey: const ValueKey('report-actions'),
      title: '조치',
      gap: AdminSpacing.sm,
      children: [
        ...buttons,
        if (!summary.isOpen)
          Text(
            resolvedAt == null ? '처리됨' : '처리됨 · ${formatSubmittedAt(resolvedAt)}',
            style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted),
          ),
        if (unhideFailed) const ErrorRow('신고는 기각했지만 가림은 해제하지 못했어요. [가림 해제]로 다시 시도해 주세요.'),
        // pen YZM0o 하나(닫힌 신고도 같은 문구 — 대장 결정 10-18)
        Text('정지·가림 해제는 사유 입력이 필요해요. 같은 대상의 열린 신고를 한꺼번에 닫을 수도 있어요.', style: muted),
      ],
    );
  }
}
