import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 설정 "연락처 차단" 줄이 부른다. 권한이 이미 있으면 16b 로 바로 간다(8a 생략, DESIGN §9 화면 8a).
/// 없으면 8a → 8d 를 먼저 거치고, 거기서 차단을 마쳤을 때만 16b 로 간다.
Future<void> openContactBlocks(BuildContext context, WidgetRef ref) async {
  final granted = await ref.read(deviceContactSourceProvider).hasPermission();
  if (!context.mounted) return;
  final ready = granted || await openContactPicker(context, ref);
  if (ready && context.mounted) context.push(AppRoutes.contactBlocks);
}

/// 8d 로 간다. 권한이 없으면 8a 안내를 먼저 띄우고, OS 권한을 받지 못하면 8a-2 로 끝난다.
/// 8d 에서 차단을 마쳤으면 true. 06-4 는 [route] 로 온보딩 쪽 8d 를 연다.
Future<bool> openContactPicker(BuildContext context, WidgetRef ref, {String route = AppRoutes.contactPicker}) async {
  final source = ref.read(deviceContactSourceProvider);
  final granted = await source.hasPermission() || (context.mounted && await _askPermission(context, source));
  if (!granted || !context.mounted) return false;
  return await context.push<bool>(route) ?? false;
}

/// 8a(pen `KgX8O`). "허용하고 계속"이면 OS 권한 창, 거부면 8a-2. "나중에 할게요"도 8a-2 로 간다
/// (DESIGN §9 화면 8a-2 "OS 권한을 거부하거나 '나중에'를 눌렀을 때"). 바깥을 눌러 닫으면 아무것도 하지 않는다.
Future<bool> _askPermission(BuildContext context, DeviceContactSource source) async {
  final allow = await _showPermissionSheet(
    context,
    title: '연락처 접근을 허용해 주세요',
    description: '내 연락처에 있는 지인이 카드에 뜨지 않게 하려면 연락처를 읽어야 해요. 전화번호는 암호화해 대조에만 쓰고 원본은 저장하지 않아요.',
    primaryLabel: '허용하고 계속',
    neutralLabel: '나중에 할게요',
  );
  if (allow == null) return false;
  // "다시 묻지 않음"이면 OS 창 없이 곧바로 거부가 온다 — 그때도 8a-2 가 떠야 한다.
  final granted = allow && await source.requestPermission();
  if (!granted && context.mounted) await _showDenied(context, source);
  return granted;
}

/// 8a-2(pen `M9ovbi`). "기기 설정 열기"는 시트를 닫고 앱 설정을 연다.
Future<void> _showDenied(BuildContext context, DeviceContactSource source) async {
  final openSettings = await _showPermissionSheet(
    context,
    title: '연락처 권한이 꺼져 있어요',
    description: '기기 설정 > CampusMate > 연락처를 켜면 지인 차단을 쓸 수 있어요.',
    primaryLabel: '기기 설정 열기',
    neutralLabel: '닫기',
  );
  if (openSettings ?? false) await source.openSettings();
}

/// 주색 버튼이면 true, 회색 버튼이면 false, 바깥을 눌러 닫으면 null.
Future<bool?> _showPermissionSheet(
  BuildContext context, {
  required String title,
  required String description,
  required String primaryLabel,
  required String neutralLabel,
}) {
  return showSafetySheet<bool>(
    context,
    (_) => _PermissionSheet(
      title: title,
      description: description,
      primaryLabel: primaryLabel,
      neutralLabel: neutralLabel,
    ),
  );
}

/// 8a · 8a-2 는 16f 해제 확인과 같은 틀이다(여백 [12,20,28,20] · 20/700 제목 · 16 설명 1.5 · 52 버튼 둘).
/// 회색 버튼 글자가 "취소"가 아니라 `SafetyConfirmSheet` 대신 내용만 같은 모양으로 넘긴다.
class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.neutralLabel,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final String neutralLabel;

  @override
  Widget build(BuildContext context) {
    return SafetySheet(
      children: [
        // pen `WCK2p` · `G2nEkR` 20/700 ink, 렌더 29.
        Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
        const SizedBox(height: AppSpacing.md),
        // pen `YPJbz` · `IrFv0` 16 / body / 1.5.
        Text(description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        // pen 은 설명과 버튼 사이에 4px 투명 사각형(`JuPTg` · `Zuk8c`)을 끼워 16 + 4 + 16 = 36 을 만든다.
        const SizedBox(height: 36),
        SafetySheetButton.primary(label: primaryLabel, onPressed: () => Navigator.of(context).pop(true)),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: neutralLabel, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
