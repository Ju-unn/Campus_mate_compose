import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 8d 차단할 연락처 선택(pen `bWKuJ`). 권한은 들어오기 전에 받았다(`openContactPicker`).
/// 차단을 마치면 `true` 를 돌려주며 닫힌다 — 여는 쪽이 16b 로 가거나 목록을 다시 읽는다.
class ContactPickerScreen extends ConsumerWidget {
  const ContactPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(contactPickerViewModelProvider.select((state) => state.completed), (_, completed) {
      if (completed) context.pop(true);
    });
    final state = ref.watch(contactPickerViewModelProvider);
    final viewModel = ref.read(contactPickerViewModelProvider.notifier);
    return Scaffold(
      // pen `A7xnD` 56, 여백 [0,8], 간격 4 — 16f 와 같은 자리(화살표 x8, 제목 x60).
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: 4,
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: BackButton(color: AppColors.ink)),
        title: Text('차단할 연락처 선택', style: AppTypography.navTitle),
      ),
      body: Column(
        children: [
          _SearchField(onChanged: viewModel.search),
          Expanded(child: _body(state, viewModel)),
        ],
      ),
      bottomNavigationBar: _BottomBar(state: state, onSubmit: viewModel.submit),
    );
  }

  Widget _body(ContactPickerUiState state, ContactPickerViewModel viewModel) {
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    return ListView(
      // pen `rpkaB` 여백 [0,24].
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        for (final contact in state.visible)
          ContactRow(
            name: contact.name,
            number: _firstNumber(contact),
            selected: state.selectedIds.contains(contact.id),
            onTap: () => viewModel.toggle(contact.id),
          ),
      ],
    );
  }

  /// 한 사람에 번호가 여럿이어도 pen 줄은 번호 한 줄이다 — 기기가 준 첫 번호를 가려 보인다.
  static String _firstNumber(DeviceContact contact) =>
      contact.numbers.isEmpty ? '' : maskPhoneNumber(contact.numbers.first);
}

/// 검색칸(pen SearchField `y7Qlw` 인스턴스 `ARlR7`): 부모 여백 [0,24,12,24], 48 높이, surface-soft, 모서리 12, 테두리 없음,
/// 여백 [0,16], 간격 8, 돋보기 3D 24(`Tvmq5`) · "이름 검색" 14/400 muted(디자인 공통 10-03).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hintStyle = AppTypography.bodySmall.copyWith(color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: TextField(
        onChanged: onChanged,
        style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '이름 검색',
          hintStyle: hintStyle,
          filled: true,
          fillColor: AppColors.surfaceSoft,
          isDense: true,
          // 높이는 최소값만 건다 — 글자를 키우면 칸이 따라 커진다.
          constraints: const BoxConstraints(minHeight: 48),
          // 세로 여백은 두지 않는다 — 높이는 위 최소값 48 이 정하고, 테두리가 outline 이라 글자는 가운데에 선다.
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          prefixIcon: const Padding(
            // pen 간격 8 = 이 여백 4 + Material 3 가 prefix 뒤에 저절로 붙이는 4(input_decorator `prefixToInputGap`).
            padding: EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
            // 그림은 Icon 과 달리 스스로 가운데 서지 않는다 — 칸 높이 48 로 늘어나지 않게 세운다.
            child: Center(widthFactor: 1, child: Icon3d(AppIcon3d.search, size: 24)),
          ),
          prefixIconConstraints: const BoxConstraints(minHeight: 48),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 하단 고정(pen Bottom Bar CTA `bzBZZ` · 마스터 `A8INC6`): 여백 [8,24,8,24], 간격 8, 캔버스, 위 선 없음(투명).
/// 안내 `mqa0S` 12/400 muted 1.5 → 버튼 `k4MqlT`(Button 마스터 `HE8FZ` = AppButton).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onSubmit});

  final ContactPickerUiState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: AppSpacing.bottomCta,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.errorMessage != null) ...[
                // 실패 · 휴대전화 없음은 pen 에 없는 상태 — 16f 해제 실패와 같은 빨간 한 줄로 알린다.
                Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                '번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요.',
                style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: '선택 완료 (${state.selectedCount}명)',
                onPressed: state.canSubmit ? onSubmit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
