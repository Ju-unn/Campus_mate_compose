import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 예시 그림 한 장 — 에셋 경로와 낭독기가 읽을 설명.
typedef ExampleImage = ({String asset, String label});

/// 캡션 + 예시 그림 두 칸(pen `PhotoExample` · 아바타 변환 예시 `q7Rp0G`, 대장 전달 값). 칸 사이 12 · 모서리 14 · 정사각 cover.
/// 사진 예시(04-2)와 아바타 예시(04-3 · 15b-4 · 15b-5)가 같은 모양을 쓴다.
class PhotoExample extends StatelessWidget {
  /// 04-2 "이런 사진이 좋아요" — 두 칸이 폭을 나눠 채운다(사진 칸 158 과 같은 폭).
  /// 그림은 AI 로 만든 가상 인물이다(실존 인물 아님).
  const PhotoExample.goodPhoto({super.key})
      : _isAvatar = false,
        _tileHeight = null;

  /// 04-3 · 15b-4 · 15b-5 아바타 변환 예시 — 두 칸이 폭을 나눠 채우고 높이는 130(pen `q7Rp0G` · `wznui` · `M3beY` 칸 158×130).
  /// 그림 둘 다 변환된 일러스트다(사진 원본이 아니다). 이름은 실존 인물 사진 규칙(`avatar-*` gitignore)에 걸리지 않게 지었다.
  const PhotoExample.avatar({super.key})
      : _isAvatar = true,
        _tileHeight = 130;

  /// 아바타 변환 예시인지(아니면 04-2 사진 예시).
  final bool _isAvatar;

  /// 칸 높이. 칸 폭은 늘 둘이 나눠 채운다. null 이면 폭과 같은 정사각이다(04-2 pen `D5fQG` 158).
  final double? _tileHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final caption = _isAvatar ? l10n.profilePhotoExampleAvatarCaption : l10n.profilePhotoExampleGoodCaption;
    final List<ExampleImage> images = _isAvatar
        ? [
            (asset: 'assets/images/example-illust-a-v1.webp', label: l10n.profilePhotoExampleAvatarGlasses),
            (asset: 'assets/images/example-illust-b-v1.webp', label: l10n.profilePhotoExampleAvatarBob),
          ]
        : [
            (asset: 'assets/images/example-photo-park-v1.webp', label: l10n.profilePhotoExampleGoodPark),
            (asset: 'assets/images/example-photo-cafe-v1.webp', label: l10n.profilePhotoExampleGoodCafe),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
        // 캡션 ↔ 그림 8 — 대장 값에 없어 정한 값(pen 확인 대상).
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final (index, image) in images.indexed) ...[
              if (index > 0) const SizedBox(width: AppSpacing.sm),
              _tile(image),
            ],
          ],
        ),
      ],
    );
  }

  Widget _tile(ExampleImage image) {
    final height = _tileHeight;
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.asset(
        image.asset,
        fit: BoxFit.cover,
        // pen 아바타 예시는 세로 원본(1024×1536)을 158×130 에 가운데 cover 로 담는다. 앱 그림은 그 원본의 158~1182 줄 정사각이라
        // 아래에 맞춰야 pen 과 같은 부분(원본 347~1189 줄, 1 이내)이 보인다. 정사각 칸(04-2)은 잘리지 않아 가운데 그대로.
        alignment: height == null ? Alignment.center : Alignment.bottomCenter,
        semanticLabel: image.label,
      ),
    );
    if (height == null) {
      return Expanded(child: AspectRatio(aspectRatio: 1, child: picture));
    }
    return Expanded(child: SizedBox(height: height, child: picture));
  }
}
