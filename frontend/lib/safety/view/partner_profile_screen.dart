import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/safety/model/partner_profile.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/view/safety_actions.dart';
import 'package:campus_mate/safety/viewmodel/partner_profile_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/partner_profile_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 14c 상대 프로필 상세(pen `VTX3D`). 본문은 10b 카드([ProfileCard])를 그대로 쓰고,
/// 14c 에만 있는 것(실사진 · 신뢰 배지 · 카카오 카드 · 신고/차단 링크)을 카드 슬롯에 꽂는다.
/// 10b 와 달리 결정 바(거절 · 수락)와 하단 내비가 없다. 지인 리뷰는 서버가 아직 내리지 않아 그리지 않는다.
class PartnerProfileScreen extends ConsumerWidget {
  const PartnerProfileScreen({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = partnerProfileViewModelProvider(profileId);
    final state = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (next.isGone && previous?.isGone != true) {
        _leaveGone(context, next.errorMessage);
      }
    });
    final profile = state.profile;
    return Scaffold(
      // pen `WpvDL` 56, 여백 [0,8], 간격 4 — 8 + 48 에 titleSpacing 4 로 화살표 가운데 x32, 제목 x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: BackButton(color: AppColors.ink, onPressed: () => _exit(context)),
        ),
        title: profile == null
            ? null
            : Text('${profile.detail.profile.nickname} 님 프로필', style: AppTypography.navTitle),
      ),
      body: SafeArea(child: _body(context, ref, state)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, PartnerProfileUiState state) {
    final profile = state.profile;
    if (profile != null) {
      return _ProfileBody(profile: profile, profileId: profileId);
    }
    // 404 는 곧 화면을 떠난다 — 문구 없이 비워 둔다.
    if (state.isLoading || state.isGone) {
      return const Center(child: CircularProgressIndicator());
    }
    return _LoadError(
      message: state.errorMessage ?? '',
      onRetry: () => ref.invalidate(partnerProfileViewModelProvider(profileId)),
    );
  }

  /// 보여 줄 상대가 없다(404). 서버 문구를 짧게 띄우고 빠져나간다.
  static void _leaveGone(BuildContext context, String? message) {
    if (message != null) {
      showSafetyToast(ScaffoldMessenger.of(context), message, icon: AppIcons.circleAlert);
    }
    _exit(context);
  }

  /// 채팅방 14b 버튼은 push 로 연다. 링크로 바로 열려 스택이 한 장뿐이면 pop 할 곳이 없어 대화 목록으로 간다.
  static void _exit(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.conversations);
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.profileId});

  final PartnerProfile profile;
  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revealed = profile.isRevealed;
    return SingleChildScrollView(
      // pen `tOehB` 여백 [0,16] — 카드가 앱바에 바로 붙고 화면 아래 끝까지 간다.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: ProfileCard(
        detail: profile.detail,
        // 게이트 전(null)이거나 0장이면 사진 칸이 없다 — 카드는 10b 와 같다.
        header: switch (profile.photoUrls) {
          [_, ...] && final urls => _PhotoHeader(urls: urls),
          _ => null,
        },
        nameTrailing: revealed ? const _TrustBadge() : null,
        footer: _Footer(
          afterIdealNote: profile.detail.idealNote != null,
          kakao: revealed ? _KakaoCard(kakaoId: profile.kakaoId) : null,
          onReport: () => reportThenLeave(context, ref, ReportTarget.profile(profileId)),
          onBlock: () => _block(context, ref),
        ),
      ),
    );
  }

  /// 실패는 pen 에 없다 — 14c 에는 입력 바가 없어 결과 토스트 자리에 실패 문구를 띄운다.
  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await blockThenLeave(
      context,
      ref,
      profileId: profileId,
      nickname: profile.detail.profile.nickname,
    );
    if (error != null) {
      showSafetyToast(messenger, error, icon: AppIcons.circleAlert);
    }
  }
}

/// 실사진 서명 URL → 그림. 서명 URL 은 읽을 때마다 바뀌어 디스크 캐시가 맞을 일이 없다 — 메모리 캐시만 쓰는
/// [NetworkImage] 로 둔다. 테스트는 네트워크 없이 그리려고 이 provider 를 바꿔 끼운다.
final partnerPhotoImageProvider = Provider<ImageProvider Function(String url)>((ref) => NetworkImage.new);

/// 카드 맨 위 실사진(14c "Real Photo Slider" 288×260). 게이트 뒤에만 온다.
class _PhotoHeader extends ConsumerWidget {
  const _PhotoHeader({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(partnerPhotoImageProvider);
    return Padding(
      // 값표에 슬라이더 아래 간격이 없다 — 카드 안 섹션 간격 13(pen `TORAs`)을 따른다.
      padding: const EdgeInsets.only(bottom: 13),
      child: PhotoSlider(photos: [for (final url in urls) image(url)], photoSize: const Size(288, 260)),
    );
  }
}

/// 이름 줄 오른쪽 "신뢰 확인 완료"(pen `N3WijU`): badge-check 15 + 14/600 primary-text, 간격 5.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.badgeCheck, size: 15, color: AppColors.primaryText),
        // pen 간격 5 는 간격 토큰(xxs 4 · xs 8) 사이 값이다.
        const SizedBox(width: 5),
        Text(
          '신뢰 확인 완료',
          // 줄높이 속성 없음 · pen 렌더 20.
          style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText, height: 20 / 14),
        ),
      ],
    );
  }
}

/// 카드 맨 아래(pen `tLtXl` → `e2HVe` 1 → `z7YFng` 구분선 → `QCRYo` 11 → `divm8` 링크 줄).
///
/// 링크 줄은 보이는 줄이 20 인데 누르는 영역은 48 이어야 한다. 위는 구분선 뒤 11, 아래는 카드 여백 20 뿐이라
/// 누르는 영역을 위 11 · 아래 17 로 잡고 남은 3 을 채운다 — 카드가 아래 여백을 이 칸에 넘겨준다.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.afterIdealNote,
    required this.kakao,
    required this.onReport,
    required this.onBlock,
  });

  /// 카드 마지막 칸이 "이런 사람이 좋아요" 글이다.
  final bool afterIdealNote;

  /// 게이트 뒤에만 있다.
  final Widget? kakao;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 카드의 다른 마지막 칸(태그 · 외모 타입)은 섹션 간격 13(pen `TORAs`)으로 끝나는데 이 글만 0 으로 끝난다.
        // pen `VTX3D` 에는 이 칸이 없어 10b 값을 따른다(결정: 사용자 (가), 통합대장 09-27).
        if (afterIdealNote) const SizedBox(height: 13),
        if (kakao != null) ...[kakao!, const SizedBox(height: 1)],
        const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
        // 배율을 키우면 두 링크가 한 줄에 안 들어간다 — 넘치지 않게 다음 줄로 내린다.
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ActionLink(icon: AppIcons.flag, label: '신고하기', onTap: onReport),
            Padding(
              padding: _linkPadding,
              // pen `Z0DRuj` 14 / hairline.
              child: Text('·', style: _linkStyle),
            ),
            _ActionLink(icon: AppIcons.ban, label: '차단하기', onTap: onBlock),
          ],
        ),
        const SizedBox(height: 3),
      ],
    );
  }
}

/// 누르는 영역 48 = 위 11(구분선 뒤 pen 간격) + 글자 20 + 아래 17.
const EdgeInsets _linkPadding = EdgeInsets.only(top: 11, bottom: 17);

/// pen `bLICR` · `wOUWs` 14 / 보통 굵기, 줄높이 속성 없음 · 렌더 20. 가운데 점만 hairline 색이다.
final TextStyle _linkStyle = AppTypography.bodySmall.copyWith(color: AppColors.hairline, height: 20 / 14);

/// 회색 글자 링크(pen `divm8` — 버튼이 아니라 글자 모양, 빨강 없음).
class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 눌림 효과가 스크롤과 같이 움직이게 링크 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: _linkPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Flexible(child: Text(label, style: _linkStyle.copyWith(color: AppColors.muted))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 카카오 카드(pen `tLtXl`): 채움 primary-wash, 모서리 12, 여백 [12,14], 라벨 11 · 값 16/600(사이 2), copy 18 primary-text.
/// 14b 카톡 행(`I9ZyOV`)과 색 · 여백 · 모서리가 달라 따로 둔다.
class _KakaoCard extends StatelessWidget {
  const _KakaoCard({required this.kakaoId});

  final String? kakaoId;

  @override
  Widget build(BuildContext context) {
    final id = kakaoId;
    return Container(
      // 세로 여백 12 는 글자 칸에만 준다 — 복사 버튼(48)은 높이 64 안에 세로 가운데로 들어간다.
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다.
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '카카오톡 아이디',
                    // pen 11 / 보통 굵기, 줄높이 속성 없음 · 렌더 16.
                    style: AppTypography.caption
                        .copyWith(fontSize: 11, color: AppColors.muted, height: 16 / 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // 게이트 뒤라도 상대가 아직 적지 않았을 수 있다 — 14b 와 같은 말로 적는다.
                    id ?? '상대가 아직 아이디를 등록하지 않았어요',
                    // pen 16/600, 줄높이 속성 없음 · 렌더 22.
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 22 / 16),
                  ),
                ],
              ),
            ),
          ),
          if (id != null)
            IconButton(
              // 누르는 영역 48, 보이는 아이콘 18 은 pen 자리(오른쪽 여백 14 에 붙음)에 둔다.
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(AppIcons.copy, size: 18, color: AppColors.primaryText),
              tooltip: '복사',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('카카오톡 아이디를 복사했어요')));
                }
              },
            ),
        ],
      ),
    );
  }
}

/// 읽기 실패(404 말고). pen 에 없는 상태 — 10b 와 같은 회색 문구에 "다시 시도" 를 붙인다.
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
