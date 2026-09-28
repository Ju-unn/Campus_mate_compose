import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 조각 6 바텀시트를 띄운다. 딤은 모달 딤 토큰(pen `colors.scrim`), 키보드가 올라오면 그만큼 밀어 올린다.
Future<T?> showSafetySheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 기본 딤(0.8)은 시안보다 어둡다 — 모달 딤 토큰(0.5)을 쓴다.
    barrierColor: AppColors.scrim,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: builder(sheetContext),
    ),
  );
}

/// 시트 맨 위 손잡이(pen `L3Bec` · `Y1P837` · `k8GZO` · `R5hkR` — 모두 36×4, 모서리 8, hairline).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

/// 신고 시트(pen `yl8gX`) · 14e 차단 확인(`aCTy1`) · 16f 해제 확인(`FzXZ4`)이 같이 쓰는 틀.
/// 셋 다 시트 마스터가 아니라 같은 모양으로 직접 그린 plain frame 이다.
/// 여백 [12,20,28,20], 위 모서리 24, 캔버스. 손잡이와 첫 줄 사이 16. 그 아래 간격은 시트마다 다르다
/// (신고 시트의 사유 행은 누르는 영역이 48 이라 16 을 그대로 쓰면 보이는 간격이 틀어진다) — 각 시트가 넣는다.
class SafetySheet extends StatelessWidget {
  const SafetySheet({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서는 시트가 화면보다 길어진다 — 넘치는 만큼 스크롤한다.
        child: SingleChildScrollView(
          // pen 아래 여백 28 은 간격 토큰(lg 24 · xl 32) 사이 값이다.
          padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// 조각 6 시트의 52 높이 버튼 두 종(pen `Ktokt` · `cLFGm` · `Tcqay` 주색 / `V66Ve5` · `B6RP1` · `tXumG` 회색).
/// AppButton(56, 모서리 16)과 크기·모서리가 달라 여기 둔다 — pen 도 Button 마스터(HE8FZ)가 아니다.
class SafetySheetButton extends StatelessWidget {
  /// 주색 채움(#FF385C). 계획서의 danger 가 pen 에서는 이 색이다.
  /// [leading] 은 글자 앞 아이콘(15b 하트 CTA pen `wf0b2`, gap 8). 없으면 글자만 둔다.
  const SafetySheetButton.primary({required this.label, required this.onPressed, this.leading, super.key})
      : _isPrimary = true;

  /// 회색 채움(surface-strong). 계획서의 글자 버튼이 pen 에서는 이 모양이다.
  const SafetySheetButton.neutral({required this.label, required this.onPressed, super.key})
      : _isPrimary = false,
        leading = null;

  final String label;

  /// null 이면 비활성.
  final VoidCallback? onPressed;
  final Widget? leading;
  final bool _isPrimary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // pen 에 비활성 상태가 없어 AppButton 의 비활성 색을 따른다.
    final background = !enabled
        ? AppColors.primaryDisabled
        : (_isPrimary ? AppColors.primary : AppColors.surfaceStrong);
    final foreground = !enabled
        ? AppColors.disabled
        : (_isPrimary ? AppColors.onPrimary : AppColors.ink);
    return Semantics(
      button: true,
      enabled: enabled,
      // 눌림 효과가 시트와 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다(고정 높이면 조용히 잘린다).
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              // pen 라벨 렌더 26 이 y 13 에 놓인다.
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 13),
              child: Center(child: _content(foreground)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Color foreground) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      // pen 18/700, 줄높이 속성 없음 · 렌더 26.
      style: AppTypography.label.copyWith(color: foreground, height: 26 / 18),
    );
    // 아이콘이 없으면 기존 안전 시트 버튼과 똑같이 글자 하나만 둔다.
    if (leading == null) {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [leading!, const SizedBox(width: AppSpacing.xs), Flexible(child: text)],
    );
  }
}

/// 확인 시트 하나를 띄우고 확인했으면 true. 바깥 탭·스와이프·취소는 false.
Future<bool> showSafetyConfirmSheet(
  BuildContext context, {
  required String title,
  required String description,
  required String confirmLabel,
}) async {
  final confirmed = await showSafetySheet<bool>(
    context,
    (_) => SafetyConfirmSheet(title: title, description: description, confirmLabel: confirmLabel),
  );
  return confirmed ?? false;
}

/// 14e(pen `aCTy1`) · 16f 해제(`FzXZ4`) 확인 시트. 제목 · 설명 · 주색 확인 · 회색 취소.
class SafetyConfirmSheet extends StatelessWidget {
  const SafetyConfirmSheet({
    required this.title,
    required this.description,
    required this.confirmLabel,
    super.key,
  });

  final String title;
  final String description;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return SafetySheet(
      children: [
        // pen `YXdCN` 20/700, 줄높이 속성 없음 · 렌더 29. 신고 시트 제목(18)과 크기가 다르다.
        Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
        const SizedBox(height: AppSpacing.md),
        // pen `u3gXUA` 16 / body / 1.5.
        Text(description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        // pen 은 설명과 버튼 사이에 4px 투명 사각형(`zlBnH`)을 끼워 간격 16 + 4 + 16 = 36 을 만든다.
        const SizedBox(height: 36),
        SafetySheetButton.primary(
          label: confirmLabel,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: '취소', onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
