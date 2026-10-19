import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart' show formatSubmittedAt;
import 'package:campus_mate_admin/heart_tasks/proof_photo_viewer.dart' show ProofImage;
import 'package:campus_mate_admin/reports/report_controller.dart' show ActionResult;
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show ProfileAction, missingValue;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/users/user_controller.dart';
import 'package:campus_mate_admin/users/user_dialogs.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/stat_card.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A5 사용자 상세(pen f3jq1 · 1440×900). 주소 `/users/{id}`. 내용 32 안쪽, 세로 16: (경고 띠) → 머리 카드(HWaL9) → 통계 줄(n7leT1, 사이 24) →
/// 표 두 칸(Q9Dxbh, 사이 24 · 열 안 8) → 메모 카드(AXEJJ) → 단추 줄(oyyMx, 사이 8). 탈퇴한 계정은 단추 줄 대신 "탈퇴한 계정이에요".
/// 전화 · 카톡 열람 값은 대화상자만 들고 있다가 닫으면 버린다(이 화면 · provider 에 두지 않는다).
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  /// 탈퇴 대행은 됐는데 바깥 정리가 일부 실패했다 — 화면 위 경고 띠(이 사람 화면을 떠나면 사라진다)
  String? _banner;

  UserDetailController get _controller => ref.read(userDetailProvider(widget.id).notifier);

  Future<void> _after(ActionResult? result, {String done = '처리했어요'}) async {
    if (!mounted || result == null) return;
    switch (result) {
      case ActionResult.done:
        AdminToast.show(context, done);
      case ActionResult.alreadyDone:
        await showAdminDialog<void>(
          context,
          (_) => const AdminDialog(title: '이미 처리된 항목이에요', body: '다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.'),
        );
      case ActionResult.failed || ActionResult.unhideFailed || ActionResult.insufficientHearts || ActionResult.withdrawn:
        break;
    }
  }

  Future<void> _adjust(UserSummary user) async {
    final result = await showAdminDialog<ActionResult>(
      context,
      (_) => HeartAdjustDialog(nickname: user.nickname ?? missingValue, onSubmit: _controller.adjustHearts),
    );
    await _after(result, done: '하트를 조정했어요');
  }

  /// 메모(pen t1G1R) — 사유 대화상자와 같은 틀, 자리 글자만 다르다. 성공하면 메모 목록만 새로 받는다(controller) — 안내 토스트는 pen 에 없다.
  Future<void> _note() {
    return showAdminDialog<DialogOutcome<void>>(
      context,
      (_) => ReasonDialog<void>(
        title: '메모를 남길까요?',
        body: '조치 없이 기록만 남겨요. 전화번호·실명을 적지 마세요.',
        hint: '메모 내용 (글자 수 제한 있음)',
        confirmLabel: '저장',
        onSubmit: (text) async => (await _controller.addNote(text), null),
      ),
    );
  }

  /// 정지 · 정지 해제 — W2 와 같은 사유 대화상자(D2 경로)
  Future<void> _withReason({
    required String title,
    required String body,
    required String confirm,
    required ProfileAction action,
    bool danger = false,
  }) async {
    final outcome = await showAdminDialog<DialogOutcome<void>>(
      context,
      (_) => ReasonDialog<void>(
        title: title,
        body: body,
        confirmLabel: confirm,
        danger: danger,
        onSubmit: (reason) async => (await _controller.actOnProfile(action, reason), null),
      ),
    );
    await _after(outcome?.$1);
  }

  Future<void> _viewPrivate() => showAdminDialog<void>(context, (_) => PrivateViewFlow(onSubmit: _controller.viewPrivate));

  Future<void> _close(UserDetail detail) async {
    final outcome = await showAdminDialog<DialogOutcome<CloseAccountResult>>(
      context,
      (_) => CloseAccountDialog(
        nickname: detail.summary.nickname ?? missingValue,
        providers: detail.loginProviders,
        suspended: detail.summary.isSuspended,
        onSubmit: (reason, verifiedBy) => _controller.closeAccount(reason: reason, verifiedBy: verifiedBy),
      ),
    );
    if (!mounted || outcome == null) return;
    final closed = outcome.$2;
    if (closed != null) {
      setState(() {
        _banner = closed.kakaoUnlinkFailed
            ? '카카오 연결 끊기를 마치지 못했어요 — 작업 기록 확인'
            : closed.otherCleanupFailed
            ? '탈퇴 뒤 정리를 일부 마치지 못했어요 — 작업 기록 확인'
            : null;
      });
    }
    await _after(outcome.$1, done: '탈퇴를 대행했어요');
  }

  List<Widget> _actionButtons(UserDetail detail) {
    final user = detail.summary;
    final name = user.nickname ?? missingValue;
    return [
      AdminButton(label: '하트 조정', variant: AdminButtonVariant.secondary, onPressed: () => _adjust(user)),
      if (user.isSuspended)
        AdminButton(
          label: '정지 해제',
          variant: AdminButtonVariant.secondary,
          onPressed: () => _withReason(
            title: '정지를 해제할까요?',
            body: '$name 의 정지를 풀어요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '정지 해제',
            action: ProfileAction.unsuspend,
          ),
        )
      else if (user.canSuspend)
        AdminButton(
          label: '정지',
          variant: AdminButtonVariant.danger,
          onPressed: () => _withReason(
            title: '사용자를 정지할까요?',
            body: '$name 를 정지해요. 작업 기록에 사유가 남고, 사유는 필수예요.',
            confirm: '정지',
            action: ProfileAction.suspend,
            danger: true,
          ),
        ),
      AdminButton(label: '탈퇴 대행', variant: AdminButtonVariant.danger, onPressed: () => _close(detail)),
      AdminButton(label: '전화·카톡 열람', variant: AdminButtonVariant.secondary, onPressed: _viewPrivate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userDetailProvider(widget.id));
    final detail = state.value;
    final Widget content;
    if (state.hasError) {
      final error = state.error;
      final missing = error is AdminApiFailure && (error.statusCode == 404 || error.statusCode == 422);
      content = missing
          ? AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.searchX, size: 32, color: AdminColors.disabled),
              title: '사용자를 찾을 수 없어요',
              body: '지워졌거나 주소가 틀렸어요. 목록에서 다시 찾아 주세요.',
              action: AdminButton(
                label: '사용자 찾기',
                variant: AdminButtonVariant.secondary,
                onPressed: () => context.go(AdminSection.users.path),
              ),
            )
          : AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
              title: '사용자를 불러오지 못했어요',
              body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
              action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: _controller.retry),
              alert: true,
            );
    } else if (detail == null) {
      content = const AdminTableEmpty(framed: false, leading: AdminLoader(color: AdminColors.muted), body: '사용자 정보를 불러오고 있어요');
    } else {
      final user = detail.summary;
      final banner = _banner;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (banner != null) ...[_Banner(banner), const SizedBox(height: AdminSpacing.md)],
          _HeadCard(detail: detail),
          const SizedBox(height: AdminSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatCard(label: '하트 잔액', value: '${detail.heartBalance}'),
                const SizedBox(width: AdminSpacing.lg),
                StatCard(label: '받은 신고', value: '${user.reportCount}'),
                const SizedBox(width: AdminSpacing.lg),
                StatCard(label: '연락처 차단 개수', value: '${detail.contactBlockCount}'),
              ],
            ),
          ),
          const SizedBox(height: AdminSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _LedgerSection(hearts: detail.hearts)),
              const SizedBox(width: AdminSpacing.lg),
              Expanded(child: _PurchaseSection(purchases: detail.purchases)),
            ],
          ),
          const SizedBox(height: AdminSpacing.md),
          _MemoCard(notes: detail.notes, onNote: _note),
          const SizedBox(height: AdminSpacing.md),
          if (user.isWithdrawn)
            Text('탈퇴한 계정이에요', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted))
          else
            Wrap(key: const ValueKey('user-actions'), spacing: AdminSpacing.xs, runSpacing: AdminSpacing.xs, children: _actionButtons(detail)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: SingleChildScrollView(child: content),
    );
  }
}

/// 화면 위 경고 띠(pen lcIIF 와 같은 모양): warning-wash · 모서리 8 · 안쪽 12 · triangle-alert 18 + 8 + 14 warning
class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('user-banner'),
        padding: const EdgeInsets.all(AdminSpacing.sm),
        decoration: BoxDecoration(color: AdminColors.warningWash, borderRadius: BorderRadius.circular(AdminRadius.sm)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.triangleAlert, size: 18, color: AdminColors.warning),
            const SizedBox(width: AdminSpacing.xs),
            Expanded(child: Text(message, style: AdminTypography.sm.copyWith(color: AdminColors.warning))),
          ],
        ),
      ),
    );
  }
}

/// 카드 바탕(pen): web-surface · web-outline 1 · 모서리 14
Widget _card({required Key key, required EdgeInsets padding, required Widget child}) {
  final shape = BorderRadius.circular(AdminRadius.md);
  return Container(
    key: key,
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
    foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
    child: child,
  );
}

/// 머리 카드(HWaL9): 안쪽 24 · 가로 16 — 아바타 자리 56 원(web-surface-strong + user 24 web-disabled, 공개 아바타가 있으면 그 그림) →
/// 닉네임 20/700 + 상태 배지 + 로그인 방식 배지(사이 8) / 4 / 메타 14 web-muted
class _HeadCard extends StatelessWidget {
  const _HeadCard({required this.detail});

  final UserDetail detail;

  @override
  Widget build(BuildContext context) {
    final user = detail.summary;
    final (statusLabel, statusTone) = userStatusBadge(user.status);
    final active = detail.lastActiveAt;
    final avatar = detail.avatarUrl;
    const placeholder = Center(child: Icon(LucideIcons.user, size: 24, color: AdminColors.disabled));
    return _card(
      key: const ValueKey('user-head'),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      child: Row(
        children: [
          Container(
            key: const ValueKey('user-avatar'),
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(color: AdminColors.surfaceStrong, shape: BoxShape.circle),
            child: avatar == null ? placeholder : ProofImage(url: avatar, fit: BoxFit.cover, onError: (_) {}, fallback: placeholder),
          ),
          const SizedBox(width: AdminSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(header: true, child: Text(user.nickname ?? missingValue, style: AdminTypography.lg.copyWith(color: AdminColors.ink))),
                    const SizedBox(width: AdminSpacing.xs),
                    StatusBadge(statusLabel, tone: statusTone),
                    for (final provider in detail.loginProviders ?? const <String>[]) ...[
                      const SizedBox(width: AdminSpacing.xs),
                      StatusBadge('${loginProviderName(provider)} 로그인', tone: StatusTone.plain),
                    ],
                  ],
                ),
                const SizedBox(height: AdminSpacing.xxs),
                Text(
                  '${user.university ?? missingValue} · 가입 ${formatKstDate(user.createdAt)} · 마지막 활동 ${active == null ? missingValue : formatKstDate(active)}',
                  style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 표 한 칸(Q9Dxbh 의 열): 제목 16/700 → 8 → 표. 기록이 없으면 표 대신 "기록이 없어요" 14 web-muted 한 줄.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.table});

  final String title;
  final Widget? table;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
        ),
        const SizedBox(height: AdminSpacing.xs),
        table ?? const _NoRecords(),
      ],
    );
  }
}

class _NoRecords extends StatelessWidget {
  const _NoRecords();

  @override
  Widget build(BuildContext context) {
    return Text('기록이 없어요', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted));
  }
}

String _signed(int amount) => amount > 0 ? '+$amount' : '$amount';

/// 하트 원장(최근) 표: 시각 150 · 종류 170 · 변동 90 · 잔액 90(마지막 열이 남는 폭). 변동은 부호 그대로, 색 구분 없음.
class _LedgerSection extends StatelessWidget {
  const _LedgerSection({required this.hearts});

  final List<HeartEntry> hearts;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '하트 원장 (최근)',
      table: hearts.isEmpty
          ? null
          : AdminTable(
              key: const ValueKey('user-ledger'),
              columns: const [150, 170, 90, 90],
              fillLast: true,
              heads: const ['시각', '종류', '변동', '잔액'],
              rows: [
                for (final entry in hearts)
                  AdminTableRow(
                    cells: [
                      AdminCellText(formatSubmittedAt(entry.createdAt)),
                      AdminCellText(heartReasonLabel(entry.reason)),
                      AdminCellText(_signed(entry.amount)),
                      AdminCellText('${entry.balanceAfter}'),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// 구매 목록 표: 시각 140 · 상품 130 · 스토어 100 · 상태 90(글자) · 지급 하트 90(마지막 열이 남는 폭)
class _PurchaseSection extends StatelessWidget {
  const _PurchaseSection({required this.purchases});

  final List<PurchaseEntry> purchases;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '구매 목록',
      table: purchases.isEmpty
          ? null
          : AdminTable(
              key: const ValueKey('user-purchases'),
              columns: const [140, 130, 100, 90, 90],
              fillLast: true,
              heads: const ['시각', '상품', '스토어', '상태', '지급 하트'],
              rows: [
                for (final purchase in purchases)
                  AdminTableRow(
                    cells: [
                      AdminCellText(formatSubmittedAt(purchase.purchasedAt)),
                      AdminCellText(purchase.productName),
                      AdminCellText(storeName(purchase.store)),
                      AdminCellText(purchase.statusLabel),
                      AdminCellText('${purchase.grantedHearts}'),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// 메모 카드(AXEJJ): 안쪽 16 · 세로 8 — 제목 "메모" 16/700 + [메모 남기기](보조, 오른쪽) → 줄 14 web-body "날짜 · admin · 글".
/// 메모를 쓴 관리자는 서버가 번호만 줘서 "admin" 으로 적는다. 비면 "기록이 없어요".
class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.notes, required this.onNote});

  final List<UserNote> notes;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    return _card(
      key: const ValueKey('user-memo'),
      padding: const EdgeInsets.all(AdminSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('메모', style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
                ),
              ),
              AdminButton(label: '메모 남기기', variant: AdminButtonVariant.secondary, onPressed: onNote),
            ],
          ),
          const SizedBox(height: AdminSpacing.xs),
          if (notes.isEmpty)
            const _NoRecords()
          else
            for (final (i, note) in notes.indexed) ...[
              if (i > 0) const SizedBox(height: AdminSpacing.xs),
              Text(
                '${formatKstDate(note.createdAt)} · admin · ${note.text}',
                style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.body),
              ),
            ],
        ],
      ),
    );
  }
}
