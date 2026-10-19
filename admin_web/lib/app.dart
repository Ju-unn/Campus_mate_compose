import 'package:campus_mate_admin/router/admin_router.dart';
import 'package:campus_mate_admin/theme/admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'CampusMate 관리자',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}
