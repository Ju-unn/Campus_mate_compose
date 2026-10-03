import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/contact_permission_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _circleSize = 96.0; // pen I8gQZ
const _iconSize = 52.0; // pen Nnsox
const _skipHeight = 48.0; // pen Dazi1
const _noticeRadius = 12.0; // pen xxLBt — 토큰 사이 값(radius sm 8 · md 14)
const _noticePadding = 14.0; // pen xxLBt

/// 06-4 지인 차단(pen `lK8tn`). 가입 마지막 화면이다(결정 8 ①) — 20d 뒤 앱에서만 잇는다.
/// 버튼은 8a → 8d(온보딩 쪽 경로)를 열고, 차단을 마치면 홈으로 간다. 건너뛰기도 홈으로 간다.
/// 차단 목록(16b)은 여기 두지 않는다 — 소개만 하고 관리는 설정에서(대장 결정).
class OnboardingContactBlockScreen extends ConsumerWidget {
  const OnboardingContactBlockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const _AppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // pen 은 Top Bar(QvfFs)와 Scroll(LHBul)이 나뉘었지만, 글자를 키우면 위 묶음만으로도 넘쳐 함께 스크롤한다.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: _circleSize,
                      height: _circleSize,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
                      child: const Icon3d(AppIcon3d.contact, size: _iconSize),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '지인 차단',
                      style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '아는 사람을 만나고 싶지 않다면 연락처로 미리 막을 수 있어요',
                      style: AppTypography.body.copyWith(color: AppColors.body),
                    ),
                    // QvfFs 아래 16 + LHBul 위 8.
                    const SizedBox(height: AppSpacing.md + AppSpacing.xs),
                    const _Notice(),
                  ],
                ),
              ),
            ),
            ColoredBox(
              color: AppColors.canvas,
              child: Padding(
                padding: AppSpacing.bottomCta,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(label: '연락처에서 지인 차단하기', onPressed: () => _block(context, ref)),
                    const SizedBox(height: AppSpacing.xs),
                    // Dazi1 은 #6A6A6A — AppButton text variant(주색 글자)와 달라 화면 안에서 그린다.
                    TextButton(
                      onPressed: () => context.go(AppRoutes.home),
                      // shrinkWrap — 기본 터치 영역(48)이 높이를 대신 채우지 않게, 높이는 _skipHeight 가 정한다.
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(_skipHeight),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '건너뛰기',
                        style: AppTypography.button.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '나중에 설정 > 지인 차단에서 할 수 있어요',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final blocked = await openContactPicker(context, ref, route: AppRoutes.onboardingContactPicker);
    if (blocked && context.mounted) context.go(AppRoutes.home);
  }
}

/// pen x6w7Xd = AppBar · Sub `KH1hX`: 높이 56, 뒤로 48(arrow-left 22), 제목 18/700. 건너뛰기 자리는 꺼짐.
/// 나 탭 `EditAppBar` 와 같은 틀이지만 그건 쌓인 화면을 pop 한다 — 여기는 go 로 들어와 뒤로가 20d 로 가야 해 따로 그린다.
class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar();

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: AppColors.canvas,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: AppSpacing.sm + 48,
      titleSpacing: AppSpacing.xxs,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Center(
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: () => context.go(AppRoutes.onboardingAcquisition),
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
          ),
        ),
      ),
      title: Text('지인 차단', style: AppTypography.subNavTitle.copyWith(color: AppColors.ink)),
    );
  }
}

/// pen xxLBt — 15-4 안내(`WQIrY`)와 같은 틀이다.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(_noticeRadius)),
      child: Padding(
        padding: const EdgeInsets.all(_noticePadding),
        child: Text(
          '연락처 번호는 암호화해서 비교에만 쓰고, 연락처 목록은 저장하지 않아요',
          style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.body),
        ),
      ),
    );
  }
}
