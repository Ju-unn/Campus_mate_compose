import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:campus_mate/safety/viewmodel/contact_block_list_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/contact_block_list_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 테스트가 pen 크기를 재는 데 쓰는 자리 표시.
const Key contactBlockAddKey = ValueKey('contact-block-add');

/// 16b 연락처 차단 관리(pen `fkjEh`, 빈 상태 `Gp5my`). 틀(앱바)만 여기 있고 본문은 [ContactBlockListBody] 다.
class ContactBlockListScreen extends StatelessWidget {
  const ContactBlockListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // pen `K7lDk` 56 — 16f 와 같은 자리(화살표 x8, 제목 x60).
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Navigator.of(context).canPop()
            ? const Padding(padding: EdgeInsets.only(left: 8), child: BackButton(color: AppColors.ink))
            : null,
        title: Text('연락처 차단', style: AppTypography.navTitle),
      ),
      body: const SafeArea(child: ContactBlockListBody()),
    );
  }
}

/// 16b 의 본문 — 목록 · 빈 상태 · 읽기 실패와 바닥 바의 추가 버튼. 쓰는 곳은 16b 뿐이다(가입 마지막 06-4 는 이 본문을 쓰지 않는다 —
/// `OnboardingContactBlockScreen` 이 소개만 하고 관리는 설정으로 보낸다).
/// 틀(앱바 · 제목)은 쓰는 쪽 몫이다. 높이가 정해진 자리에 둔다 — 목록이 남은 높이를 채우고 바닥 바가 맨 아래에 붙는다.
/// 들어올 때마다 새로 읽는다(뷰모델이 autoDispose).
class ContactBlockListBody extends ConsumerWidget {
  const ContactBlockListBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contactBlockListViewModelProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // pen 목록 `UajtB` y56~700 — 앱바 바로 아래에서 바닥 바 위까지.
        Expanded(child: _body(context, ref, state)),
        // pen 바닥 바 y700~780 h80 · 패딩 [8,16,16,16] — 안의 버튼 328×56(nHrnA `aogPm` · fkjEh `g1FD5` · Gp5my `w849oc`).
        // 해제 확인 시트 · 스크림은 이 바 위에 덮이는 오버레이다.
        ColoredBox(
          color: AppColors.canvas,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
            child: _AddButton(onPressed: () => _add(context, ref)),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, ContactBlockListUiState state) {
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    // 읽기 실패는 줄이 하나도 없을 때뿐이다 — 줄이 있는데 문구가 있으면 해제 실패다.
    if (state.rows.isEmpty && state.errorMessage != null) {
      return _LoadError(
        message: state.errorMessage!,
        onRetry: () => ref.read(contactBlockListViewModelProvider.notifier).load(),
      );
    }
    if (state.rows.isEmpty) return const _Empty();
    return ListView(
      // pen `ZwbzQ` 여백 [0,24].
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        for (final row in state.rows) _row(context, ref, row),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          // 해제 실패는 pen 에 없다 — 16f 와 같은 빨간 한 줄.
          Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  /// 이름을 모르는 줄(pen `J2OCDM`)은 이름칸 · 번호칸 자리에 안내 두 줄을 쓴다.
  Widget _row(BuildContext context, WidgetRef ref, ContactBlockRow row) {
    final label = row.label;
    return ContactRow(
      name: label?.name ?? '이전에 차단한 연락처',
      number: label?.maskedNumber ?? '이 기기에서 이름을 찾을 수 없어요',
      showInitial: label != null,
      onRemove: () => _confirmRemove(context, ref, row.blockId),
    );
  }

  /// 16b 의 "추가"에서 8d 로 갔다 차단을 마치고 돌아오면 목록을 다시 읽는다.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final viewModel = ref.read(contactBlockListViewModelProvider.notifier);
    if (await openContactPicker(context, ref)) await viewModel.load();
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String blockId) async {
    final viewModel = ref.read(contactBlockListViewModelProvider.notifier);
    final confirmed = await showSafetyConfirmSheet(
      context,
      // pen `rISKU` · `TxO3n` · `JFtKq` 문구 그대로.
      title: '차단을 해제할까요?',
      description: '이 연락처가 다시 카드에 나타날 수 있어요.',
      confirmLabel: '해제',
    );
    if (confirmed) await viewModel.remove(blockId);
  }
}

/// 추가(pen Button 마스터 `HE8FZ` 인스턴스 `aogPm` · `g1FD5` · `w849oc`): 가로 328 × 56, 모서리 14, #FF385C, 가운데 흰 plus → "추가" 흰색 18/700.
/// plus 는 lucide 20×20 흰색(`z0zGy`), plus 와 글자 사이 8, 덩어리 가운데 정렬. 옛 작은 회색 버튼(312×44 · #F2F2F2 · 모서리 8 · 목록 위 `AddRowWrap`)은 없앴다.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 바탕은 버튼 자신의 Material 이 칠한다 — 눌림 효과가 버튼 안에서 그려진다(COMMON §4-2).
    return Material(
      key: contactBlockAddKey,
      color: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          // 높이는 최소값만 — 글자를 키우면 버튼이 따라 커진다.
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.plus, size: 20, color: AppColors.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: Text('추가', style: AppTypography.button.copyWith(fontSize: 18, color: AppColors.onPrimary))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빈 상태(pen `Gp5my` → Empty `TVc8b` 인스턴스 `I1Mz6`): 여백 [48,24], 가운데. 마스코트 120 → 16 → 제목 → 8 → 설명.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          // 목록 칸 높이만큼 채워 가운데에 둔다. 글자를 키워 넘치면 스크롤한다.
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/mascot-female.png', width: 120, height: 120),
                  // pen 간격 8 + 빈 사각형 8(`Wz22b`).
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '아직 차단한 연락처가 없어요',
                    textAlign: TextAlign.center,
                    // pen `ZBzIg` 17/600 ink.
                    style: AppTypography.subtitle.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '추가한 연락처 속 지인과는 서로의 카드에 나타나지 않아요.',
                    textAlign: TextAlign.center,
                    // pen `DFs55` 14 / 보통 / muted / 1.55.
                    style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 읽기 실패. pen 에 없는 상태 — 16f 와 같은 회색 문구에 "다시 시도" 를 붙인다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
