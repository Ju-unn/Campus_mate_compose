import 'package:campus_mate_admin/graduate/certificate_viewer.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/graduate/graduate_review_controller.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_screen.dart';
import 'package:campus_mate_admin/heart_tasks/proof_photo_viewer.dart' show showPhotoZoom;
import 'package:campus_mate_admin/home/home_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/reports/report_dialogs.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_field.dart';
import 'package:campus_mate_admin/widgets/admin_link.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_select.dart';
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

/// A10 졸업생 검수(pen pIuL0 · 1440×900 · 값표 §6). 내용 32 안쪽에 큐 칸 320 → 24 → 사진 칸 440 → 24 → 정보 카드 328.
/// 큐 칸만 세로로 스크롤하고, 카드는 입력 칸이 들어가 화면보다 길어질 수 있어 카드 칸이 따로 스크롤한다.
///
/// 값표와 다른 점(서버 목록에 닉네임 · 학교 · 경고 칸이 없다): 큐 항목은 "n번째 신청 + 지난 시간", 칩 2종(중복 경고 · 이전 메일 있음)은
/// 그리지 않았다. 값표 밖에서 정한 것: 문서확인번호 · 학번 입력 칸, 정규화 안내, 승인 · 반려 확인 대화상자, 409 문구, 지난 신청.
///
/// 단축키(인증샷 검수와 같은 규칙): A 승인 확인 · R 반려 사유 펼침 · Esc 접기. 입력 칸 · 대화상자에 초점이 있거나 Ctrl · Cmd · Alt 를
/// 같이 누르면 무시하고, 승인은 학교 · 번호가 다 맞을 때만 먹는다. 번호 · 학번 입력은 컨트롤러 상태에만 있고 결정 뒤 비워진다.
class GraduateReviewScreen extends ConsumerStatefulWidget {
  const GraduateReviewScreen({super.key, this.initialId});

  final String? initialId;

  @override
  ConsumerState<GraduateReviewScreen> createState() => _GraduateReviewScreenState();
}

class _GraduateReviewScreenState extends ConsumerState<GraduateReviewScreen> {
  final ScrollController _queueScroll = ScrollController();
  final FocusNode _selectFocus = FocusNode(debugLabel: '반려 Select');
  final FocusNode _firstReasonFocus = FocusNode(debugLabel: '첫 반려 사유');
  final GlobalKey _menuKey = GlobalKey(debugLabel: '반려 사유 메뉴');
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final Set<String> _reportedPhotoUrls = <String>{};
  bool _menuOpen = false;
  String? _revealedSelection;

  GraduateReviewController get _controller => ref.read(graduateReviewProvider(widget.initialId).notifier);
  GraduateReviewState get _state => ref.read(graduateReviewProvider(widget.initialId));

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
    if (!_state.canReview) return false;
    if (key == PhysicalKeyboardKey.keyR) {
      _openMenu(focusFirstReason: true);
      return true;
    }
    if (_menuOpen || !_state.canApprove) return false; // 사유를 고르는 중 · 승인 조건이 안 맞으면 승인하지 않는다
    _approve();
    return true;
  }

  /// 입력 칸에서 글자를 치는 중이거나, 대화상자(크게 보기 · 확인 · 이미 처리됨)가 위에 떠 있다
  bool _typingOrDialog() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return true;
    }
    return Navigator.of(context, rootNavigator: true).canPop();
  }

  void _openMenu({required bool focusFirstReason}) {
    if (!_menuOpen) setState(() => _menuOpen = true);
    // 카드가 화면보다 길면 펼친 사유 4개가 접힌 쪽에 있을 수 있다 — 카드 안 스크롤로 보이는 자리까지 굴린다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final menu = _menuKey.currentContext;
      if (menu != null) Scrollable.ensureVisible(menu);
      if (focusFirstReason) _firstReasonFocus.requestFocus();
    });
  }

  void _closeMenu({bool refocusSelect = false}) {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    if (refocusSelect) _selectFocus.requestFocus();
  }

  void _toggleMenu() {
    if (_menuOpen) return _closeMenu();
    _openMenu(focusFirstReason: _selectFocus.hasFocus);
  }

  /// 승인 · 반려는 사진이 바로 지워지는 되돌릴 수 없는 처리라 한 번 더 묻는다(값표 밖).
  Future<bool> _confirm({required String title, required String body, required String confirmLabel, bool danger = false}) async {
    final ok = await showAdminDialog<bool>(
      context,
      (_) => _ConfirmDialog(title: title, body: body, confirmLabel: confirmLabel, danger: danger),
    );
    return ok == true && mounted;
  }

  String _schoolName(String? id) {
    final list = _state.universities.value ?? const <UniversityStatus>[];
    return list.where((u) => u.id == id).map((u) => u.name).firstOrNull ?? '고른 학교';
  }

  Future<void> _approve() async {
    _closeMenu();
    final state = _state;
    if (!state.canApprove) return;
    final ok = await _confirm(
      title: '승인할까요?',
      body: '${_schoolName(state.universityId)} 졸업생으로 승인해요. 승인하면 사진이 바로 지워지고, 신청자에게 알림이 가요.',
      confirmLabel: '승인',
    );
    if (ok && await _controller.approve() && mounted) AdminToast.show(context, '처리했어요');
  }

  Future<void> _reject(GraduateRejectReason reason) async {
    _closeMenu();
    final ok = await _confirm(
      title: '반려할까요?',
      body: '사유: ${reason.label}. 반려하면 사진이 바로 지워지고, 신청자에게 알림이 가요.',
      confirmLabel: '반려',
      danger: true,
    );
    if (ok && await _controller.reject(reason) && mounted) AdminToast.show(context, '처리했어요');
  }

  void _onPhotoError(String detailId, String url) {
    if (!_reportedPhotoUrls.add(url)) return;
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
    final provider = graduateReviewProvider(widget.initialId);
    final state = ref.watch(provider);
    ref.listen(provider.select((s) => s.alreadyReviewed), (was, now) {
      if (now && was != true) _showAlreadyReviewed();
    });
    final items = state.items.value;
    final Widget content;
    if (state.items.hasError) {
      content = AdminTableEmpty(
        leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
        title: '목록을 불러오지 못했어요',
        body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
        action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: _controller.retryList),
        alert: true,
      );
    } else if (items == null) {
      content = const AdminTableEmpty(leading: AdminLoader(color: AdminColors.muted), body: '졸업생 신청 목록을 불러오고 있어요');
    } else if (items.isEmpty) {
      content = const AdminTableEmpty(
        leading: Icon(LucideIcons.inbox, size: 32, color: AdminColors.disabled),
        title: '검수할 졸업생 신청이 없어요',
        body: '새 신청이 들어오면 여기에 보여요',
        enter: true,
      );
    } else {
      _revealSelection(state.selectedId);
      content = _review(state, items);
    }
    return Padding(padding: const EdgeInsets.all(AdminSpacing.xl), child: content);
  }

  Widget _review(GraduateReviewState state, List<GraduateItem> items) {
    final now = ref.watch(clockProvider)();
    final detail = state.detail;
    final selectedId = state.selectedId;
    final loaded = detail?.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
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
        const SizedBox(width: AdminSpacing.lg),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Align(
              alignment: Alignment.topLeft,
              child: detail == null || selectedId == null
                  ? const SizedBox.shrink()
                  : CertificateViewer(
                      detail: detail,
                      onOpen: (url) => showPhotoZoom(context, url),
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
            child: loaded == null || detail!.isLoading
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: _InfoCard(
                      // 건이 바뀌면 입력 칸(글자 조절기)도 새로 만든다
                      key: ValueKey('info-${loaded.id}'),
                      initialId: widget.initialId,
                      detail: loaded,
                      menuOpen: _menuOpen,
                      selectFocus: _selectFocus,
                      firstReasonFocus: _firstReasonFocus,
                      menuKey: _menuKey,
                      onApprove: _approve,
                      onToggleMenu: _toggleMenu,
                      onCloseMenu: _closeMenu,
                      onReject: _reject,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 큐 항목(pen Queue Item · 값표 §6): 폭 fill · 세로 6 · 안쪽 16 — 위 줄 26(제목 14/700 + 대기 배지, 사이 8), 메타 12 web-muted.
/// 고른 줄 web-primary-wash + web-primary 2, 나머지 web-surface + web-outline 1 · 모서리 8.
/// 제목은 닉네임, 메타는 "학교 · n분 전"이다. 탈퇴 계정(닉네임 · 학교가 null)은 "n번째 신청" · 지난 시간만 보인다.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, required this.now, required this.selected, required this.onTap});

  final GraduateItem item;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapBox(
      key: ValueKey('graduate-row-${item.id}'),
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
                    item.nickname ?? (item.attemptNo <= 1 ? '첫 신청' : '${item.attemptNo}번째 신청'),
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
            [?item.universityName, formatAgo(item.createdAt, now)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 정보 카드(pen NfTj6): 폭 328 · 안쪽 24 · 세로 16 · web-surface · web-outline 1 · 모서리 14. 제목 "졸업생 확인 정보" 16/700 →
/// 제출자 · 제출 시각 줄 → 읽어 둔 문서확인번호 · 읽어 둔 학교 이름 블록(글자 인식 **힌트**) → 학교 고르기(Select) →
/// [값표 밖] 문서확인번호 · 학번 입력 → 이전 학교 이메일 → 경고 줄 → [승인] + [반려 ▾] → 안내 · 단축키.
class _InfoCard extends ConsumerStatefulWidget {
  const _InfoCard({
    super.key,
    required this.initialId,
    required this.detail,
    required this.menuOpen,
    required this.selectFocus,
    required this.firstReasonFocus,
    required this.menuKey,
    required this.onApprove,
    required this.onToggleMenu,
    required this.onCloseMenu,
    required this.onReject,
  });

  final String? initialId;
  final GraduateDetail detail;
  final bool menuOpen;
  final FocusNode selectFocus;
  final FocusNode firstReasonFocus;
  final GlobalKey menuKey;
  final VoidCallback onApprove;
  final VoidCallback onToggleMenu;
  final VoidCallback onCloseMenu;
  final ValueChanged<GraduateRejectReason> onReject;

  @override
  ConsumerState<_InfoCard> createState() => _InfoCardState();
}

class _InfoCardState extends ConsumerState<_InfoCard> {
  late final TextEditingController _document;
  late final TextEditingController _student;

  GraduateReviewController get _controller => ref.read(graduateReviewProvider(widget.initialId).notifier);

  @override
  void initState() {
    super.initState();
    final state = ref.read(graduateReviewProvider(widget.initialId));
    _document = TextEditingController(text: state.documentNumber);
    _student = TextEditingController(text: state.studentNumber);
  }

  @override
  void dispose() {
    // 평문 입력이 글자 조절기에 남지 않게 비운 뒤 버린다
    _document.clear();
    _student.clear();
    _document.dispose();
    _student.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(graduateReviewProvider(widget.initialId));
    // 상태가 바뀌면(결정 뒤 비움 · 다시 받기) 칸의 글자도 맞춘다. 사람이 칠 때는 이미 같아서 건드리지 않는다.
    ref.listen(graduateReviewProvider(widget.initialId).select((s) => s.documentNumber), (_, text) {
      if (_document.text != text) _document.text = text;
    });
    ref.listen(graduateReviewProvider(widget.initialId).select((s) => s.studentNumber), (_, text) {
      if (_student.text != text) _student.text = text;
    });
    final detail = widget.detail;
    final shape = BorderRadius.circular(AdminRadius.md);
    final documentInvalid = state.documentNumber.trim().isNotEmpty && normalizeDocumentNumber(state.documentNumber) == null;
    final studentInvalid = state.studentNumber.trim().isNotEmpty && normalizeStudentNumber(state.studentNumber) == null;
    final guide = AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted);
    return Container(
      key: const ValueKey('graduate-info'),
      padding: const EdgeInsets.all(AdminSpacing.lg),
      decoration: BoxDecoration(color: AdminColors.surface, borderRadius: shape),
      foregroundDecoration: BoxDecoration(borderRadius: shape, border: Border.all(color: AdminColors.outline)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '졸업생 확인 정보',
              style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink),
            ),
          ),
          const SizedBox(height: AdminSpacing.md),
          _SubmitterRow(nickname: detail.item.nickname, profileId: detail.item.profileId),
          const SizedBox(height: AdminSpacing.md),
          ReviewInfoRow(name: '제출 시각', value: formatSubmittedAt(detail.item.createdAt)),
          const SizedBox(height: AdminSpacing.md),
          _ReadBlock(name: '읽어 둔 문서확인번호', value: detail.ocr?.documentNumber, hint: '자동으로 읽은 값이에요. 직접 확인해 주세요'),
          const SizedBox(height: AdminSpacing.md),
          _ReadBlock(name: '읽어 둔 학교 이름', value: detail.ocr?.schoolText),
          const SizedBox(height: AdminSpacing.md),
          _Block(name: '학교 고르기', child: _schoolSelect(state)),
          const SizedBox(height: AdminSpacing.md),
          AdminField(
            key: const ValueKey('document-field'),
            label: '문서확인번호',
            controller: _document,
            hint: '발급 기관에서 확인한 번호',
            maxChars: documentNumberMaxChars,
            onChanged: _controller.setDocumentNumber,
            enabled: state.busy == null,
          ),
          const SizedBox(height: AdminSpacing.xxs),
          Text(documentNumberGuide, style: guide),
          if (documentInvalid) ...[const SizedBox(height: AdminSpacing.xxs), const ErrorRow('문서확인번호는 영문 · 숫자 4~40자로 입력해 주세요', lineHeight: AdminTypography.xsBox)],
          const SizedBox(height: AdminSpacing.md),
          AdminField(
            key: const ValueKey('student-field'),
            label: '학번 (선택)',
            controller: _student,
            hint: '서류에 학번이 있을 때만',
            maxChars: studentNumberMaxChars,
            onChanged: _controller.setStudentNumber,
            enabled: state.busy == null,
          ),
          const SizedBox(height: AdminSpacing.xxs),
          Text(studentNumberGuide, style: guide),
          if (studentInvalid) ...[const SizedBox(height: AdminSpacing.xxs), const ErrorRow('학번은 영문 · 숫자 1~20자로 입력해 주세요', lineHeight: AdminTypography.xsBox)],
          if (detail.previousSchoolEmail != null) ...[
            const SizedBox(height: AdminSpacing.md),
            _Block(
              name: '이전 학교 이메일',
              child: Text(
                detail.previousSchoolEmail!,
                style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.ink),
              ),
            ),
          ],
          for (final (i, warning) in detail.warnings.indexed) ...[
            SizedBox(height: i == 0 ? AdminSpacing.md : AdminSpacing.xs),
            _WarningRow(boxKey: ValueKey('graduate-warning-$i'), warning: warning),
          ],
          const SizedBox(height: AdminSpacing.md),
          // 펼친 사유 바깥을 누르면 접는다(Select · 사유 목록은 한 덩어리)
          TapRegion(
            onTapOutside: (_) => widget.onCloseMenu(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AdminButton(
                      label: '승인',
                      loading: state.busy == ReviewAction.approve,
                      onPressed: state.canApprove ? widget.onApprove : null,
                    ),
                    const SizedBox(width: AdminSpacing.sm),
                    Flexible(
                      child: RejectSelect(
                        focusNode: widget.selectFocus,
                        enabled: state.canReview,
                        busy: state.busy == ReviewAction.reject,
                        expanded: widget.menuOpen,
                        onTap: widget.onToggleMenu,
                      ),
                    ),
                  ],
                ),
                if (widget.menuOpen) ...[
                  const SizedBox(height: AdminSpacing.md),
                  RejectMenu<GraduateRejectReason>(
                    key: widget.menuKey,
                    firstFocus: widget.firstReasonFocus,
                    options: [for (final reason in GraduateRejectReason.values) (reason, reason.label)],
                    onReject: widget.onReject,
                  ),
                ],
              ],
            ),
          ),
          if (state.error != null) ...[const SizedBox(height: AdminSpacing.md), ErrorRow(state.error!)],
          const SizedBox(height: AdminSpacing.md),
          Text('승인 · 반려하면 사진이 바로 지워져요', style: guide),
          const SizedBox(height: AdminSpacing.md),
          Text('단축키: 승인 A · 반려 R', style: guide),
        ],
      ),
    );
  }

  /// 학교 고르기(Web/Select MuZJ5 · 폭 fill 280 · 높이 44). 아직 정해지지 않았으면 "학교를 골라 주세요"를 첫 줄에 둔다.
  Widget _schoolSelect(GraduateReviewState state) {
    final schools = state.universities;
    if (schools.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ErrorRow('학교 목록을 불러오지 못했어요', lineHeight: AdminTypography.xsBox),
          const SizedBox(height: AdminSpacing.xs),
          AdminButton(label: '다시 받기', variant: AdminButtonVariant.secondary, onPressed: _controller.retryUniversities),
        ],
      );
    }
    final list = schools.value;
    if (list == null) {
      return const SizedBox(height: AdminSizes.control, child: Center(child: AdminLoader(color: AdminColors.muted)));
    }
    final chosen = state.universityId;
    return AdminSelect<String>(
      key: const ValueKey('school-select'),
      semanticLabel: '학교 고르기',
      boxWidth: 280,
      boxHeight: AdminSizes.control,
      value: chosen ?? '',
      options: [if (chosen == null) ('', '학교를 골라 주세요'), for (final school in list) (school.id, school.name)],
      onChanged: (id) {
        if (id.isNotEmpty) _controller.setUniversity(id);
      },
    );
  }
}

/// 제출자 줄: 닉네임(14/600 web-ink — 값표). 탈퇴 계정이라 닉네임이 null 이면 프로필 번호 앞 8자를 사용자 상세로 가는 링크로 보인다.
class _SubmitterRow extends StatelessWidget {
  const _SubmitterRow({required this.nickname, required this.profileId});

  final String? nickname;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    final nickname = this.nickname;
    if (nickname != null) return ReviewInfoRow(name: '제출자', value: nickname);
    final short = profileId.length > 8 ? profileId.substring(0, 8) : profileId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text('제출자', style: AdminTypography.sm.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
        ),
        const SizedBox(width: AdminSpacing.sm),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: AdminLink(label: short, onTap: () => context.go('/users/$profileId')),
          ),
        ),
      ],
    );
  }
}

/// 값표 블록: 세로 6, 키 12/600 web-muted
class _Block extends StatelessWidget {
  const _Block({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        const SizedBox(height: 6), // pen 블록 gap 6 — 간격 표에 없는 값
        child,
      ],
    );
  }
}

/// "읽어 둔 …" 블록: 값 16/700 web-ink, 힌트 12 web-muted. 못 읽었으면 "읽지 못했어요"(14/600 web-muted, 힌트 없음 — 값표 밖).
class _ReadBlock extends StatelessWidget {
  const _ReadBlock({required this.name, required this.value, this.hint});

  final String name;
  final String? value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final hint = this.hint;
    return _Block(
      name: name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value == null)
            Text('읽지 못했어요', style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.muted))
          else
            Text(value, style: AdminTypography.md.copyWith(fontWeight: FontWeight.w700, height: AdminTypography.mdBox, color: AdminColors.ink)),
          if (value != null && hint != null) ...[
            const SizedBox(height: 6),
            Text(hint, style: AdminTypography.xs.copyWith(height: 1.5, color: AdminColors.muted)),
          ],
        ],
      ),
    );
  }
}

/// 중복 경고 줄(pen arX3b): 폭 fill · 가로 8 · 안쪽 12 · web-warning-wash · 모서리 8 · triangle-alert 18 web-warning + 글자 14/normal 줄높이 1.5 web-warning.
/// 문구 3종은 값표 보강 B2-1(EpGOe · ugWMg · jzuAV). 모르는 코드(그 밖)만 같은 틀에 문구를 정했다.
class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.boxKey, required this.warning});

  final Key boxKey;
  final GraduateWarning warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: boxKey,
      padding: const EdgeInsets.all(AdminSpacing.sm),
      decoration: BoxDecoration(color: AdminColors.warningWash, borderRadius: BorderRadius.circular(AdminRadius.sm)),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const Icon(LucideIcons.triangleAlert, size: 18, color: AdminColors.warning),
            const SizedBox(width: AdminSpacing.xs),
            Expanded(child: Text(warning.code.message, style: AdminTypography.sm.copyWith(color: AdminColors.warning))),
          ],
        ),
      ),
    );
  }
}

/// 승인 · 반려 확인(값표 밖): 대화상자 틀(DialogFrame p8OOG) 폭 480 · 제목 → 설명 → [취소] + 확인
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.body, required this.confirmLabel, required this.danger});

  final String title;
  final String body;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      dialogKey: const ValueKey('graduate-confirm-dialog'),
      width: 480,
      busy: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dialogTitle(title),
          const SizedBox(height: AdminSpacing.md),
          dialogBody(body),
          const SizedBox(height: AdminSpacing.md),
          dialogButtons(
            onCancel: () => Navigator.of(context).pop(false),
            confirm: AdminButton(
              label: confirmLabel,
              variant: danger ? AdminButtonVariant.danger : AdminButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
  }
}
