import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/bio_screen.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 자기소개 초안 생성 화면(DESIGN.md 화면 06-2b). 제목·진행 점 없이 좌상단 뒤로가기만 있다(§13-70).
///
/// 06-3 을 따로 라우트로 두지 않고 여기서 바로 갈아끼운다 — 서버 `next-step` 이 초안 생성과 자기소개를
/// `bio` 한 단계로 세기 때문에, 별도 경로를 만들면 [AuthRedirect] 가 곧장 되돌려 보낸다.
class BioDraftLoadingScreen extends ConsumerStatefulWidget {
  const BioDraftLoadingScreen({super.key});

  @override
  ConsumerState<BioDraftLoadingScreen> createState() => _BioDraftLoadingScreenState();
}

class _BioDraftLoadingScreenState extends ConsumerState<BioDraftLoadingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(bioViewModelProvider.notifier).loadDraft());
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(bioViewModelProvider).draftLoaded) {
      return const BioScreen();
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text('소개 글 초안을 쓰고 있어요', style: AppTypography.body.copyWith(color: AppColors.body)),
            ],
          ),
        ),
      ),
    );
  }
}
