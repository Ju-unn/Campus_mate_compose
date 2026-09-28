import 'package:campus_mate/common/widgets/app_button.dart';
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

/// 검색칸(pen SearchField `y7Qlw` 인스턴스 `ARlR7`): 부모 여백 [0,24,12,24], 44 높이, surface-soft, 모서리 8, 테두리 없음,
/// 여백 [0,12], 간격 8, 돋보기 18 · "이름 검색" 14/400 둘 다 disabled 색.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hintStyle = AppTypography.bodySmall.copyWith(color: AppColors.disabled);
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
          constraints: const BoxConstraints(minHeight: 44),
          // 세로 여백은 두지 않는다 — 높이는 위 최소값 44 가 정하고, 테두리가 outline 이라 글자는 가운데에 선다.
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          prefixIcon: const Padding(
            // pen 간격 8 = 이 여백 4 + Material 3 가 prefix 뒤에 저절로 붙이는 4(input_decorator `prefixToInputGap`).
            padding: EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.xxs),
            child: Icon(AppIcons.search, size: 18, color: AppColors.disabled),
          ),
          prefixIconConstraints: const BoxConstraints(minHeight: 44),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 하단 고정(pen Bottom Bar CTA `bzBZZ`): 여백 [16,24,28,24], 간격 8, 캔버스, 위 선 hairline 1.
/// 안내 `mqa0S` 12/400 muted 1.5 → 버튼 `k4MqlT`(Button 마스터 `HE8FZ` = AppButton 56 · 모서리 16).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onSubmit});

  final ContactPickerUiState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // pen 아래 여백 28 은 간격 토큰(lg 24 · xl 32) 사이 값이다.
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 28),
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
