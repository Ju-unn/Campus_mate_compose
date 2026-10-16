import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// [ProfileCard] 맨 위 아바타 칸(pen 부품 PhotoSlide · Avatar `xLjFQ`). 10b 카드 상세(`TORAs` 의 `md2PT`),
/// 15-4 남이 보는 내 프로필 수락 전(`gnEwq` 의 `WjVmJ`), 받은 신청 · 프로필 보기(`o4QqYR`)가 header 슬롯에 꽂는다.
/// 14c(신뢰 뒤)는 이 자리에 실사진 슬라이더([RevealedPhotoHeader])를 꽂아 이 칸을 쓰지 않는다.
///
/// 한 장뿐이라 점 줄이 없다. 칸 폭은 카드 안쪽 전체(pen 288, 360 화면에서 286 — 14c 슬라이더와 같다), 높이 260.
class ProfileAvatarHeader extends StatelessWidget {
  const ProfileAvatarHeader({required this.url, super.key});

  /// 아바타 공개 주소. 아직 아바타가 없으면 null — 회색 면 + 사람 아이콘(받은 신청 행 [RowAvatar] 와 같은 대체)이다.
  final String? url;

  /// pen `xLjFQ` 높이.
  static const double _height = 260;

  /// pen `Dtu4T` · `JERLm` — 그림 아래 → 이름 줄(카드 안 섹션 간격 13 과 같은 값).
  static const double _gapBelow = 13;

  /// 아바타가 없을 때 가운데 사람 아이콘. pen 에 없는 상태라 행 아바타(44 칸 · 20)와 비슷한 비율로 정했다.
  static const double _fallbackIconSize = 48;

  @override
  Widget build(BuildContext context) {
    final image = url;
    final radius = BorderRadius.circular(AppRadius.card);
    return Padding(
      padding: const EdgeInsets.only(bottom: _gapBelow),
      child: Semantics(
        container: true,
        image: true,
        label: '아바타',
        child: Container(
          width: double.infinity,
          height: _height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: radius),
          // 그림 위에 안쪽으로 그린다 — 칸 크기가 변하지 않는다(14c 슬라이더 `bordered` 와 같은 방식).
          foregroundDecoration: BoxDecoration(borderRadius: radius, border: Border.all(color: AppColors.hairline)),
          child: image == null
              ? const Icon(AppIcons.userRound, size: _fallbackIconSize, color: AppColors.disabled)
              : CachedNetworkImage(imageUrl: image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
