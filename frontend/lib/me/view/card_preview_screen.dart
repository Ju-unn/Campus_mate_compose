import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/viewmodel/card_preview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 15-4 남이 보는 내 프로필(pen `gnEwq`). 화면 15 입구 "남이 보는 내 프로필 카드"(`k3r5C`)가 연다. 하단 내비 없음.
/// 카드는 10b · 14c 가 같이 쓰는 [ProfileCard] 를 슬롯 없이 그대로 쓴다 — 실사진 · 카카오 카드 · 신고/차단 줄 · "신뢰 확인
/// 완료"(`CTtPd`)가 없는 모양이 pen `kpIeX` 와 같다. 값은 `GET /me/card-preview`(10b 와 같은 몸통, 계획서 N2).
class CardPreviewScreen extends ConsumerWidget {
  const CardPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const EditAppBar(title: '남이 보는 내 프로필'),
      body: SafeArea(top: false, child: _body(ref)),
    );
  }

  /// 불러오는 중 · 실패는 pen 에 없는 상태다 — 화면 15 와 같은 모양(가운데 로딩 / [MeLoadError], 계획서 N9).
  Widget _body(WidgetRef ref) {
    void retry() => ref.invalidate(myCardPreviewProvider);
    return ref.watch(myCardPreviewProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MeLoadError(onRetry: retry),
          data: (result) => result.when(
            onSuccess: (detail) => _PreviewContent(detail: detail),
            onFailure: (_) => MeLoadError(onRetry: retry),
          ),
        );
  }
}

/// 본문 `iFAyO` — 위 24 · 좌우 16 · 아래 40, 안내 ↔ 카드 32. 카드 높이는 내용 맞춤(N17).
class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.detail});

  final CardDetail detail;

  /// 본문 아래 여백 40 은 pen 값(간격 토큰 xl 32 · xxl 48 사이).
  static const double _bottomPadding = 40;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, _bottomPadding),
      children: [
        const _PreviewNotice(),
        const SizedBox(height: AppSpacing.xl),
        // 지인 리뷰 섹션(kpIeX 안) — 채팅탭 지인 리뷰 PR 4 가 넣는다(깃발 숨김 N6).
        ProfileCard(detail: detail),
      ],
    );
  }
}

/// 안내 `Ocmk4`(Notice `WQIrY`) — primary-wash, 모서리 12, 안쪽 14, 아이콘 · 링크 없음, 14/400 body 줄높이 1.5.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  /// 모서리 12 · 안쪽 14 는 pen 값(토큰 사이 값 — 라운드 sm 8 · md 14, 간격 sm 12 · md 16).
  static const double _radius = 12;
  static const double _padding = 14;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Text(
          '대화 상대가 보는 내 프로필이에요. 실제 사진과 카카오톡 아이디는 둘 다 수락한 뒤에 공개돼요.',
          style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.body),
        ),
      ),
    );
  }
}
