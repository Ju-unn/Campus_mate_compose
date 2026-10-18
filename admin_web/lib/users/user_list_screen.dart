import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/users/user_controller.dart';
import 'package:campus_mate_admin/users/user_item.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/admin_search_field.dart';
import 'package:campus_mate_admin/widgets/admin_table.dart';
import 'package:campus_mate_admin/widgets/error_row.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A5 사용자 찾기(pen tH5Lz · 1440×900). 내용 32 안쪽, 세로 24: 칩 줄(CIJJJ 36) → 검색 줄(saYxo — 칸 420×44 + [검색], 사이 12) →
/// 안내 줄(Jd4cM) → 표(VY7a0). 줄을 누르면 그 사람의 상세 주소(/users/{id}).
///
/// 학교 메일은 이 화면의 입력 칸에만 있다: 찾기가 끝나면(찾음 · 못 찾음 · 오류 모두) 칸을 비우고, 주소 · 라우터 상태 ·
/// provider 에는 남기지 않는다(대장 결정 2 · 설계 §14-3). 칩을 바꾸면 칸도 비운다.
class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {})); // 칸 글자에 따라 오류 줄 · [검색] 잠김이 바뀐다
  }

  /// 닉네임 · id 칩인데 칸에 "@" 가 있다 — 학교 메일이다. 닉네임 찾기는 GET 주소로 나가니 보내지 않는다(메일이 주소에 남지 않게).
  bool get _mailInNicknameMode => ref.read(userSearchProvider).mode == UserSearchMode.nickname && _query.text.contains('@');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_mailInNicknameMode) return;
    final controller = ref.read(userSearchProvider.notifier);
    final mail = ref.read(userSearchProvider).mode == UserSearchMode.schoolMail;
    await controller.search(_query.text);
    // 끝났다 — 메일은 칸에서도 지운다(오류 · 못 찾음 포함)
    if (mail && mounted) _query.clear();
  }

  void _setMode(UserSearchMode mode) {
    _query.clear();
    ref.read(userSearchProvider.notifier).setMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(userSearchProvider);
    final results = search.results;
    final mail = search.mode == UserSearchMode.schoolMail;
    final Widget content;
    if (results.hasError) {
      final error = results.error;
      final badMail = error is AdminApiFailure && error.statusCode == 422;
      content = badMail
          ? const AdminTableEmpty(
              framed: false,
              leading: Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
              title: '학교 메일 모양이 아니에요',
              body: '학교 메일 주소를 정확히 입력해 주세요.',
              alert: true,
            )
          : AdminTableEmpty(
              framed: false,
              leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
              title: '목록을 불러오지 못했어요',
              body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
              action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: ref.read(userSearchProvider.notifier).reload),
              alert: true,
            );
    } else if (!results.hasValue || results.isLoading) {
      content = const AdminTableEmpty(framed: false, leading: AdminLoader(color: AdminColors.muted), body: '사용자를 찾고 있어요');
    } else if (results.requireValue.isEmpty) {
      content = AdminTableEmpty(
        leading: const Icon(LucideIcons.inbox, size: 32, color: AdminColors.disabled),
        title: '찾은 사용자가 없어요',
        body: search.resultMode == UserSearchMode.schoolMail ? '그 학교 메일로 가입한 사용자가 없어요' : '입력한 닉네임 · id 를 다시 확인해 보세요',
        enter: true,
      );
    } else {
      content = Expanded(
        child: SingleChildScrollView(child: _UserTable(users: results.requireValue)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AdminSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminChip(label: '닉네임 · id', selected: !mail, onTap: () => _setMode(UserSearchMode.nickname)),
              const SizedBox(width: AdminSpacing.xs),
              AdminChip(label: '학교 메일', selected: mail, onTap: () => _setMode(UserSearchMode.schoolMail)),
            ],
          ),
          const SizedBox(height: AdminSpacing.lg),
          Row(
            children: [
              SizedBox(
                key: const ValueKey('user-search-box'),
                width: 420,
                child: AdminSearchField(
                  controller: _query,
                  hint: mail ? '학교 메일 주소 (정확히 일치)' : '닉네임 또는 프로필 id',
                  sensitive: mail,
                  maxChars: mail ? 254 : 36, // 서버 q 상한(닉네임 · 프로필 id 36자) · 메일 254자
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: AdminSpacing.sm),
              AdminButton(label: '검색', loading: results.isLoading, onPressed: _mailInNicknameMode ? null : _search),
            ],
          ),
          if (_mailInNicknameMode) ...[
            const SizedBox(height: AdminSpacing.xs),
            const ErrorRow("학교 메일은 '학교 메일' 칩을 눌러 찾아 주세요", lineHeight: AdminTypography.xsBox),
          ],
          const SizedBox(height: AdminSpacing.lg),
          Row(
            children: [
              const Icon(LucideIcons.info, size: 16, color: AdminColors.muted),
              const SizedBox(width: AdminSpacing.xs),
              Text('학교 메일은 정확히 일치해야 찾아요. 검색어는 기록되지 않아요.', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
            ],
          ),
          const SizedBox(height: AdminSpacing.lg),
          content,
        ],
      ),
    );
  }
}

/// 표 열(pen VY7a0): 닉네임 180 · 프로필 id 220 · 학교 180 · 상태 120 · 가입일 150 · 받은 신고 110. 남는 폭은 오른쪽이 빈다.
const List<double> _columns = [180, 220, 180, 120, 150, 110];

class _UserTable extends StatelessWidget {
  const _UserTable({required this.users});

  final List<UserSummary> users;

  @override
  Widget build(BuildContext context) {
    return AdminTable(
      key: const ValueKey('user-table'),
      columns: _columns,
      heads: const ['닉네임', '프로필 id', '학교', '상태', '가입일', '받은 신고'],
      rows: [
        for (final user in users)
          AdminTableRow(
            rowKey: ValueKey('user-row-${user.id}'),
            onTap: () => context.go('${AdminSection.users.path}/${user.id}'),
            cells: [
              AdminCellText(user.nickname ?? missingValue),
              AdminCellText(shortProfileId(user.id)),
              AdminCellText(user.university ?? missingValue),
              Builder(
                builder: (context) {
                  final (label, tone) = userStatusBadge(user.status);
                  return StatusBadge(label, tone: tone);
                },
              ),
              AdminCellText(formatKstDate(user.createdAt)),
              AdminCellText('${user.reportCount}건'),
            ],
          ),
      ],
    );
  }
}
