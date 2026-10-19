import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_controller.dart';
import 'package:campus_mate_admin/heart_tasks/proof_photo_viewer.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A3 인증샷 검수(pen GX3T8 · 1440×900). 내용 32 안쪽에 목록 칸 320 → 24 → 사진 칸 440 → 24 → 정보 카드 328.
/// 목록만 세로로 스크롤하고(칩 줄은 고정, pen zMTVl) 상세는 목록 옆에 나란히 둔다(겹치는 화면 없음).
/// [initialId] 는 디스코드 알림 링크(`/heart-tasks/{id}`)로 연 건 — 처음 한 번 그 건을 고른다.
///
/// 단축키: A 승인 · R 반려 사유 펼침(첫 사유에 초점) · Esc 접기. 입력 칸 · 대화상자에 초점이 있거나 Ctrl · Cmd · Alt 를
/// 같이 누르면(Ctrl+R 새로고침 등) 무시한다. 한글 자판 상태에서도 되게 글자가 아니라 자판 위치(physicalKey)로 본다.
class HeartTaskReviewScreen extends ConsumerStatefulWidget {
  const HeartTaskReviewScreen({super.key, this.initialId});

  final String? initialId;

  @override
  ConsumerState<HeartTaskReviewScreen> createState() => _HeartTaskReviewScreenState();
}

class _HeartTaskReviewScreenState extends ConsumerState<HeartTaskReviewScreen> {
  final ScrollController _queueScroll = ScrollController();
  final FocusNode _selectFocus = FocusNode(debugLabel: '반려 Select');
  final FocusNode _firstReasonFocus = FocusNode(debugLabel: '첫 반려 사유');
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final Set<String> _reportedPhotoUrls = <String>{};
  bool _menuOpen = false;
  String? _revealedSelection;

  HeartTaskReviewController get _controller => ref.read(heartTaskReviewProvider(widget.initialId).notifier);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _queueScroll.dispose();
    _selectFocus.dispose();
    _firstReasonFocus.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return false;
    final key = event.physicalKey;
    final escape = event.logicalKey == LogicalKeyboardKey.escape;
    if (key != PhysicalKeyboardKey.keyA && key != PhysicalKeyboardKey.keyR && !escape) return false;
    if (_typingOrDialog()) return false;
    if (escape) {
      if (!_menuOpen) return false;
      _closeMenu(refocusSelect: true);
      return true;
    }
    if (!ref.read(heartTaskReviewProvider(widget.initialId)).canReview) return false;
    if (key == PhysicalKeyboardKey.keyR) {
      _openMenu(focusFirstReason: true);
      return true;
    }
    if (_menuOpen) return false; // 사유를 고르는 중에는 승인하지 않는다
    _approve();
    return true;
  }

  /// 입력 칸에서 글자를 치는 중이거나, 대화상자(사진 크게 보기 · 이미 처리됨)가 위에 떠 있다
  bool _typingOrDialog() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return true;
    }
    // 대화상자는 맨 위 navigator 에 쌓인다(메뉴 화면은 셸 안쪽 navigator 의 한 페이지).
    return Navigator.of(context, rootNavigator: true).canPop();
  }

  void _openMenu({required bool focusFirstReason}) {
    if (!_menuOpen) setState(() => _menuOpen = true);
    if (focusFirstReason) WidgetsBinding.instance.addPostFrameCallback((_) => _firstReasonFocus.requestFocus());
  }

  void _closeMenu({bool refocusSelect = false}) {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    if (refocusSelect) _selectFocus.requestFocus();
  }

  void _toggleMenu() {
    if (_menuOpen) return _closeMenu();
    // 키보드(Enter · Space)로 펼쳤으면 첫 사유로 초점을 옮긴다. 마우스로 누르면 초점은 그대로.
    _openMenu(focusFirstReason: _selectFocus.hasFocus);
  }

  Future<void> _approve() async {
    _closeMenu();
    if (await _controller.approve() && mounted) AdminToast.show(context, '처리했어요');
  }

  Future<void> _reject(HeartTaskRejectReason reason) async {
    _closeMenu();
    if (await _controller.reject(reason) && mounted) AdminToast.show(context, '처리했어요');
  }

  void _openZoom(String photoId, int photoIndex) {
    showProofZoom(context, initialId: widget.initialId, photoId: photoId, photoIndex: photoIndex);
  }

  void _onPhotoError(String detailId, String url) {
    if (!_reportedPhotoUrls.add(url)) return;
    // 그리는 중에는 상태를 바꿀 수 없다 — 이 장면이 끝난 뒤 알린다. 같은 주소는 한 번만.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.photoFailed(detailId);
    });
  }

  Future<void> _showAlreadyReviewed() async {
    _closeMenu();
    await showAdminDialog<void>(
      context,
      (_) => const AdminDialog(title: '이미 처리된 항목이에요', body: '다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.'),
    );
    if (mounted) _controller.dismissAlreadyReviewed();
  }

  /// 고른 줄이 목록 칸 밖이면(링크로 연 건이 아래쪽) 보이는 자리까지 굴린다 — 움직임 없이 바로.
  void _revealSelection(String? id) {
    if (id == _revealedSelection) return;
    _revealedSelection = id;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rowKeys[id]?.currentContext;
      if (row == null || !mounted) return;
      Scrollable.ensureVisible(row, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(row, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = heartTaskReviewProvider(widget.initialId);
    final state = ref.watch(provider);
    ref.listen(provider.select((s) => s.alreadyReviewed), (was, now) {
      if (now && was != true) _showAlreadyReviewed();
    });
    final chips = _FilterChips(selected: state.filter, onSelect: _controller.setFilter);
    final items = state.items.value;
    final Widget content;
    if (state.items.hasError) {
      content = _frame(
        chips,
        AdminTableEmpty(
          leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
          title: '목록을 불러오지 못했어요',
          body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
          action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: _controller.retryList),
          alert: true,
        ),
      );
    } else if (items == null) {
      content = _frame(
        chips,
        const AdminTableEmpty(leading: AdminLoader(color: AdminColors.muted), body: '인증샷 목록을 불러오고 있어요'),
      );
    } else if (items.isEmpty) {
      content = _frame(
        chips,
        const AdminTableEmpty(
          leading: Icon(LucideIcons.inbox, size: 32, color: AdminColors.disabled),
          title: '검수할 인증샷이 없어요',
          body: '새 제출이 들어오면 여기에 보여요',
          enter: true,
        ),
      );
    } else {
      _revealSelection(state.selectedId);
      content = _review(state, items, chips);
    }
    return Padding(padding: const EdgeInsets.all(AdminSpacing.xl), child: content);
  }

  /// 빈 목록 · 받는 중 · 못 받음(pen t36bfq): 칩 줄 → 24 → 내용 폭 가득 틀
  Widget _frame(Widget chips, Widget frame) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [chips, const SizedBox(height: AdminSpacing.lg), frame],
    );
  }

  Widget _review(HeartTaskReviewState state, List<HeartTaskItem> items, Widget chips) {
    final now = ref.watch(clockProvider)();
    final selected = state.selected;
    final detail = state.detail;
    final selectedId = state.selectedId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chips,
              const SizedBox(height: AdminSpacing.sm),
              Expanded(
                child: ReviewQueue(
                  controller: _queueScroll,
                  children: [
                    for (final item in items)
                      KeyedSubtree(
                        key: _rowKeys.putIfAbsent(item.id, GlobalKey.new),
                        child: _QueueRow(
                          item: item,
                          now: now,
                          selected: item.id == selectedId,
                          onTap: () {
                            _closeMenu();
                            _controller.select(item.id);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AdminSpacing.lg),
        // 1440 에서 440. 최소 창(1280)에서는 이 칸만 줄어든다(목록 · 정보 카드는 pen 폭 그대로).
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Align(
              alignment: Alignment.topLeft,
              child: detail == null || selectedId == null
                  ? const SizedBox.shrink()
                  : ProofPhotoViewer(
                      detail: detail,
                      selectedIndex: state.selectedPhotoIndex,
                      onSelectPhoto: _controller.selectPhoto,
                      onOpen: _openZoom,
                      onPhotoError: (url) => _onPhotoError(selectedId, url),
                      onRetry: _controller.retryDetail,
                    ),
            ),
          ),
        ),
        const SizedBox(width: AdminSpacing.lg),
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 328,
            child: selected == null
                ? const SizedBox.shrink()
                : _SubmitInfo(
                    item: selected,
                    state: state,
                    menuOpen: _menuOpen,
                    selectFocus: _selectFocus,
                    firstReasonFocus: _firstReasonFocus,
                    onApprove: _approve,
                    onToggleMenu: _toggleMenu,
                    onCloseMenu: _closeMenu,
                    onReject: _reject,
                  ),
          ),
        ),
      ],
    );
  }
}

/// 칩 줄(K29dnK): 전체 · 에브리타임 · 단톡방, 사이 8. 같은 칩을 다시 눌러도 새로 받는다.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final HeartTaskKind? selected;
  final ValueChanged<HeartTaskKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <(String, HeartTaskKind?)>[('전체', null), for (final kind in HeartTaskKind.values) (kind.listLabel, kind)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (label, kind)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: AdminSpacing.xs),
          AdminChip(label: label, selected: selected == kind, onTap: () => onSelect(kind)),
        ],
      ],
    );
  }
}

/// 목록 칸만 스크롤(pen zMTVl): 스크롤바 6 · 트랙 web-outline · 썸 web-outline-strong · 알약 모서리 · 오른쪽 2 안쪽.
/// 브라우저 기본 스크롤바는 끈다(두 개가 겹치지 않게).
class ReviewQueue extends StatelessWidget {
  const ReviewQueue({super.key, required this.controller, required this.children});

  final ScrollController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(3);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 6,
        radius: radius,
        trackRadius: radius,
        thumbColor: AdminColors.outlineStrong,
        trackColor: AdminColors.outline,
        trackBorderColor: Colors.transparent,
        crossAxisMargin: 2,
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, row) in children.indexed) ...[if (i > 0) const SizedBox(height: AdminSpacing.sm), row],
            ],
          ),
        ),
      ),
    );
  }
}

/// 목록 줄(pen Queue Item q8XUTQ): 320×80 · 안쪽 16 · 세로 6 — 위 줄 26(닉네임 14/700 + 대기 배지, 사이 8),
/// 둘째 줄 "{항목} · {학교} · {n분 전}" 12 web-muted. 고른 줄 web-primary-wash + web-primary 2, 나머지 web-surface + web-outline 1.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, required this.now, required this.selected, required this.onTap});

  final HeartTaskItem item;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapBox(
      key: ValueKey('heart-task-row-${item.id}'),
      onTap: onTap,
      selected: selected,
      color: selected ? AdminColors.primaryWash : AdminColors.surface,
      side: selected ? const BorderSide(color: AdminColors.primary, width: 2) : const BorderSide(color: AdminColors.outline),
      padding: const EdgeInsets.all(AdminSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminTypography.sm.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.smBox, color: AdminColors.ink),
                  ),
                ),
                const SizedBox(width: AdminSpacing.xs),
                const StatusBadge('대기', tone: StatusTone.warning),
              ],
            ),
          ),
          const SizedBox(height: 6), // pen Queue Item gap 6 — 간격 표에 없는 값
          Text(
            '${item.kind.listLabel} · ${item.university} · ${formatAgo(item.createdAt, now)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 정보 카드(pen SuzHP): 폭 328 · 안쪽 24 · 세로 16 · web-surface · web-outline 1 · 모서리 14.
/// 제목 "제출 정보" 16/700 → 6줄(제출자 · 학교 · 항목 · 사진 · 제출 시각 · 보상, 이름 88 14 web-muted · 사이 12 · 값 14/600) → [승인] + [반려 ▾](Select 200×44) →
/// (펼침 Rrwiu: 사유 3개 280 · 44씩) → "단축키: 승인 A · 반려 R" 12 web-muted.
class _SubmitInfo extends StatelessWidget {
  const _SubmitInfo({
    required this.item,
    required this.state,
    required this.menuOpen,
    required this.selectFocus,
    required this.firstReasonFocus,
    required this.onApprove,
    required this.onToggleMenu,
    required this.onCloseMenu,
    required this.onReject,
  });

  final HeartTaskItem item;
  final HeartTaskReviewState state;
  final bool menuOpen;
  final FocusNode selectFocus;
  final FocusNode firstReasonFocus;
  final VoidCallback onApprove;
  final VoidCallback onToggleMenu;
  final VoidCallback onCloseMenu;
  final ValueChanged<HeartTaskRejectReason> onReject;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(AdminRadius.md);
    // 사진 장수는 사진을 받은 뒤에야 안다 — 받는 동안 · 못 받으면 "—"(행을 두어 카드 높이가 변하지 않게). 정리로 비면 "없음".
    final loaded = state.detail?.value;
    final photos = loaded != null && loaded.item.id == item.id ? loaded.photoUrls.length : null;
    final rows = <(String, String)>[
      ('제출자', item.nickname),
      ('학교', item.university),
      ('항목', item.kind.infoLabel),
      ('사진', photos == null ? '—' : (photos == 0 ? '없음' : '$photos장')),
      ('제출 시각', formatSubmittedAt(item.createdAt)),
      ('보상', formatReward(item.rewardHearts)),
    ];
    return Container(
      key: const ValueKey('submit-info'),
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
              '제출 정보',
              style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
            ),
          ),
          for (final (name, value) in rows) ...[const SizedBox(height: AdminSpacing.md), ReviewInfoRow(name: name, value: value)],
          const SizedBox(height: AdminSpacing.md),
          // 펼친 사유 바깥을 누르면 접는다(Select · 사유 목록은 한 덩어리)
          TapRegion(
            onTapOutside: (_) => onCloseMenu(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AdminButton(
                      label: '승인',
                      loading: state.busy == ReviewAction.approve,
                      onPressed: state.canReview ? onApprove : null,
                    ),
                    const SizedBox(width: AdminSpacing.sm),
                    // pen 은 66 + 12 + 200 = 278(칸 280). 글자를 키우면 승인 단추가 커지니 Select 가 그만큼 양보한다.
                    Flexible(
                      child: RejectSelect(
                        focusNode: selectFocus,
                        enabled: state.canReview,
                        busy: state.busy == ReviewAction.reject,
                        expanded: menuOpen,
                        onTap: onToggleMenu,
                      ),
                    ),
                  ],
                ),
                if (menuOpen) ...[
                  const SizedBox(height: AdminSpacing.md),
                  RejectMenu<HeartTaskRejectReason>(
                    firstFocus: firstReasonFocus,
                    options: [for (final reason in HeartTaskRejectReason.values) (reason, reason.label)],
                    onReject: onReject,
                  ),
                ],
              ],
            ),
          ),
          if (state.reviewFailed) ...[
            const SizedBox(height: AdminSpacing.md),
            const ErrorRow('처리하지 못했어요. 다시 시도해 주세요.'),
          ],
          const SizedBox(height: AdminSpacing.md),
          Text(
            '단축키: 승인 A · 반려 R',
            style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}

class ReviewInfoRow extends StatelessWidget {
  const ReviewInfoRow({super.key, required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(name, style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
        ),
        const SizedBox(width: AdminSpacing.sm),
        // 긴 값(학교 이름)은 잘라 숨기지 않고 줄을 바꾼다
        Expanded(
          child: Text(value, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.ink)),
        ),
      ],
    );
  }
}

/// pen Web/Select(MuZJ5 · A3 EHrY2): 200×44 · 좌우 12 · 사이 8 · web-surface · web-outline-strong 1 · 모서리 8,
/// 글자 "반려" 14 web-ink + chevron-down 18 web-muted(▾ 글자는 아이콘과 겹쳐 뺐다 — 대장 결정 10-18, pen 도 같이 고침). 반려 요청 중에는 chevron 자리에 도는 아이콘.
/// 잠김(사진을 받는 중 · 승인 중)은 pen 에 없는 상태 — 보조 단추의 비활성과 같은 색.
class RejectSelect extends StatelessWidget {
  const RejectSelect({
    super.key,
    required this.focusNode,
    required this.enabled,
    required this.busy,
    required this.expanded,
    required this.onTap,
  });

  final FocusNode focusNode;
  final bool enabled;
  final bool busy;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = !enabled && !busy;
    return Semantics(
      expanded: expanded,
      child: TapBox(
        key: const ValueKey('reject-select'),
        onTap: enabled ? onTap : null,
        focusNode: focusNode,
        semanticLabel: '반려 사유 고르기',
        width: 200,
        height: AdminSizes.control,
        color: dim ? AdminColors.surfaceStrong : AdminColors.surface,
        side: BorderSide(color: dim ? AdminColors.outline : AdminColors.outlineStrong),
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '반려',
                style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: dim ? AdminColors.disabled : AdminColors.ink),
              ),
            ),
            const SizedBox(width: AdminSpacing.xs),
            if (busy)
              const AdminLoader(color: AdminColors.muted, size: 18)
            else
              Icon(LucideIcons.chevronDown, size: 18, color: dim ? AdminColors.disabled : AdminColors.muted),
          ],
        ),
      ),
    );
  }
}

/// 펼친 반려 사유(pen krcn9): 폭 280 · web-surface · web-outline-strong 1 · 모서리 8, 사유 3개 각 44 · 좌우 16 · 14 web-ink · 선 없음.
/// 고르면 바로 반려 요청. 위아래 화살표로 사유 사이를 옮긴다(웹 기본은 화살표가 스크롤이라 여기서 초점 이동으로 묶는다).
class RejectMenu<T> extends StatelessWidget {
  const RejectMenu({super.key, required this.firstFocus, required this.options, required this.onReject});

  final FocusNode firstFocus;

  /// (사유, 줄에 보일 글자) — 인증샷은 3개, 졸업생은 4개
  final List<(T, String)> options;
  final ValueChanged<T> onReject;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      key: const ValueKey('reject-menu'),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: FocusTraversalGroup(
        child: Material(
          color: AdminColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdminRadius.sm),
            side: const BorderSide(color: AdminColors.outlineStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 280,
            child: Column(
              children: [
                for (final (i, (reason, label)) in options.indexed)
                  TapBox(
                    key: ValueKey('reject-option-$i'),
                    onTap: () => onReject(reason),
                    focusNode: i == 0 ? firstFocus : null,
                    radius: 0,
                    width: 280,
                    height: AdminSizes.control,
                    padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.md),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.ink),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
