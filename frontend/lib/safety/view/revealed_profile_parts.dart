import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 서로 수락한 뒤에만 열리는 것들(실사진 · 카카오톡 아이디 · 신고/차단 줄)을 그리는 조각.
// 14c 상대 프로필(pen `VTX3D`)과 15-4b "남이 보는 내 프로필 · 수락 후"(pen `vn8R2`)가 같이 쓴다.

/// 실사진 서명 URL → 그림. 서명 URL 은 읽을 때마다 바뀌어 디스크 캐시가 맞을 일이 없다 — 메모리 캐시만 쓰는
/// [NetworkImage] 로 둔다. 테스트는 네트워크 없이 그리려고 이 provider 를 바꿔 끼운다.
final partnerPhotoImageProvider = Provider<ImageProvider Function(String url)>((ref) => NetworkImage.new);

/// 카드 맨 위 실사진(14c "Real Photo Slider" 288×260). 게이트 뒤에만 온다.
class RevealedPhotoHeader extends ConsumerWidget {
  const RevealedPhotoHeader({required this.urls, super.key});

  final List<String> urls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(partnerPhotoImageProvider);
    return Padding(
      // 값표에 슬라이더 아래 간격이 없다 — 카드 안 섹션 간격 13(pen `TORAs`)을 따른다.
      padding: const EdgeInsets.only(bottom: 13),
      child: PhotoSlider(
        photos: [for (final url in urls) image(url)],
        photoSize: const Size(288, 260),
        bordered: true, // pen `uMias` → 마스터 `YJdUT` 안 `oE1rh` PhotoSlide · Real — 안쪽 1px #DDDDDD
      ),
    );
  }
}

/// 카드 맨 아래 신고/차단 줄(pen `e2HVe` 1 → `z7YFng` 구분선 → `QCRYo` 11 → `divm8` 링크 줄).
///
/// 링크 줄은 보이는 줄이 20 인데 누르는 영역은 48 이어야 한다. 위는 구분선 뒤 11, 아래는 카드 여백 20 뿐이라
/// 누르는 영역을 위 11 · 아래 17 로 잡고 남은 3 을 채운다 — 카드가 아래 여백을 이 칸에 넘겨준다([ReportBlockLinks]
/// 자신은 3 을 채우지 않는다. 부른 쪽이 넣는다).
///
/// [onReport] · [onBlock] 이 null 이면 그 링크는 누를 곳이 없는 글자일 뿐이다(15-4b 는 내 카드 미리보기라 자기 자신을
/// 신고 · 차단할 수 없다).
class ReportBlockLinks extends StatelessWidget {
  const ReportBlockLinks({this.onReport, this.onBlock, super.key});

  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
        // 배율을 키우면 두 링크가 한 줄에 안 들어간다 — 넘치지 않게 다음 줄로 내린다.
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ActionLink(icon: AppIcon3d.siren, label: '신고하기', onTap: onReport),
            Padding(
              padding: _linkPadding,
              // pen `Z0DRuj` 14 / hairline.
              child: Text('·', style: _linkStyle),
            ),
            _ActionLink(icon: AppIcon3d.ban, label: '차단하기', onTap: onBlock),
          ],
        ),
      ],
    );
  }
}

/// 누르는 영역 48 = 위 11(구분선 뒤 pen 간격) + 글자 20 + 아래 17.
const EdgeInsets _linkPadding = EdgeInsets.only(top: 11, bottom: 17);

/// pen `bLICR` · `wOUWs` 14 / 보통 굵기, 줄높이 속성 없음 · 렌더 20. 가운데 점만 hairline 색이다.
final TextStyle _linkStyle = AppTypography.bodySmall.copyWith(color: AppColors.hairline, height: 20 / 14);

/// 회색 글자 링크(pen `divm8` — 버튼이 아니라 글자 모양, 빨강 없음). 앞 그림은 3D 18(사이렌 `jsi9g` · 금지 `eUCJv`).
class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.icon, required this.label, required this.onTap});

  final AppIcon3d icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: _linkPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon3d(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: _linkStyle.copyWith(color: AppColors.muted))),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      // 눌림 효과가 스크롤과 같이 움직이게 링크 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// 카카오 카드(pen `tLtXl`): 채움 primary-wash, 모서리 12, 여백 [12,14], 라벨 11 · 값 16/600(사이 2), copy 18 primary-text.
/// 14b 카톡 행(`I9ZyOV`)과 색 · 여백 · 모서리가 달라 따로 둔다.
class KakaoIdCard extends StatelessWidget {
  const KakaoIdCard({required this.kakaoId, super.key});

  /// 비었으면 "상대가 아직 아이디를 등록하지 않았어요"(14b 와 같은 말)를 보인다.
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
                    style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.muted, height: 16 / 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('카카오톡 아이디를 복사했어요')));
                }
              },
            ),
        ],
      ),
    );
  }
}
