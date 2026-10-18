import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/table_empty.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 목록 자리의 세 상태(W1~W3 와 같은 틀 — [AdminTableEmpty]): 받는 중 · 못 받음(+ 다시 시도) · 빈 목록.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminTableEmpty(framed: false, leading: const AdminLoader(color: AdminColors.muted), body: message);
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock(this.title, {super.key, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminTableEmpty(
      framed: false,
      leading: const Icon(LucideIcons.circleAlert, size: 32, color: AdminColors.danger),
      title: title,
      body: '인터넷 연결을 확인하고 다시 시도해 주세요.',
      action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.secondary, onPressed: onRetry),
      alert: true,
    );
  }
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AdminTableEmpty(leading: const Icon(LucideIcons.inbox, size: 32, color: AdminColors.disabled), title: title, enter: true);
  }
}
