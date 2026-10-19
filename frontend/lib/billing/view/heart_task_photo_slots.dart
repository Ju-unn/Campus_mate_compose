import 'dart:io';

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/material.dart';

/// 테스트가 사진 블록 · 칸 · 빼기 버튼을 찾는 표식.
const Key heartTaskPhotoBlockKey = ValueKey('heart-task-photo-block');
Key heartTaskPhotoSlotKey(int index) => ValueKey('heart-task-photo-slot-$index');
Key heartTaskPhotoRemoveKey(int index) => ValueKey('heart-task-photo-remove-$index');

/// 18b 사진 블록(pen `uvkY2` 3장 · `r7wOTV` 1장 — 18b `fUFvU` · `LgSoe`). 옛 한 칸 업로더(`moNIO` 220)를 대체한다.
/// 세로 gap 8: 개수 줄("n/3장" 14/600 ink + 힌트 12 muted, 가로 gap 8) → 칸 줄(가로 gap 8, 칸 104×104 — 본문 폭 328 에서).
/// 찬 칸은 사진 + 모서리 14, 첫 칸만 "필수" 배지(마스터 `fPA2r`, x4 y4), 삭제 X(마스터 `uzGT9` 28, 오른쪽 위 4).
/// 빈 칸은 "사진 추가"([AddPhotoTile], 마스터 `jieCD` — 04-2 와 같은 칸). 칸은 늘 3열 자리이고, 옛 서버([maxPhotos] 1)면 첫 칸만 쓴다.
class HeartTaskPhotoSlots extends StatelessWidget {
  const HeartTaskPhotoSlots({
    required this.photos,
    required this.maxPhotos,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  /// 고른 순서대로.
  final List<File> photos;

  /// 서버가 허락한 장수(인증 항목 3, 옛 서버 1).
  final int maxPhotos;

  /// 빈 칸을 눌렀을 때 — 갤러리를 열어 남은 칸만큼 고르게 한다.
  final Future<void> Function() onAdd;

  /// 찬 칸의 X 를 눌렀을 때 그 번호.
  final ValueChanged<int> onRemove;

  static const int _columns = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: heartTaskPhotoBlockKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountLine(count: photos.length, maxPhotos: maxPhotos),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (var index = 0; index < _columns; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: index >= maxPhotos
                    ? const SizedBox.shrink()
                    : AspectRatio(
                        aspectRatio: 1,
                        child: index < photos.length
                            ? _FilledSlot(index: index, photo: photos[index], onRemove: onRemove)
                            // 04-2 칸은 버튼이라고 읽히지 않는다(탭 동작만 있다) — 여기서 버튼 표시를 얹는다.
                            : Semantics(button: true, child: AddPhotoTile(onTap: onAdd)),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// "n/3장" + 힌트. 글자를 키우면 힌트가 다음 줄로 접힌다(말줄임 없음).
class _CountLine extends StatelessWidget {
  const _CountLine({required this.count, required this.maxPhotos});

  final int count;
  final int maxPhotos;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // "3/3장" 을 그대로 읽으면 "3 슬래시 3" 이라 낭독만 풀어 준다. pen 14/600 ink, 줄높이 속성 없음 · 렌더 20.
        Semantics(
          container: true,
          label: '사진 $maxPhotos장 중 $count장',
          excludeSemantics: true,
          child: Text('$count/$maxPhotos장', style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14)),
        ),
        Text('1장은 꼭 올려 주세요 · 최대 $maxPhotos장', style: AppTypography.caption.copyWith(color: AppColors.muted)),
      ],
    );
  }
}

/// 사진이 든 칸. 바탕 #EBEBEB(불러오는 동안 · 못 읽을 때), 사진은 칸을 가득 채운다(cover).
/// 칸을 누르는 동작은 없다(pen 에 없음) — 바꾸려면 X 로 빼고 다시 고른다.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({required this.index, required this.photo, required this.onRemove});

  final int index;
  final File photo;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: index == 0 ? '사진 1, 필수' : '사진 ${index + 1}',
      child: ClipRRect(
        key: heartTaskPhotoSlotKey(index),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.hairlineSoft,
                // 칸 104 의 3배로 풀어 쓴다 — 원본(수백만 화소)을 통째로 디코딩하지 않는다.
                child: Image.file(
                  photo,
                  fit: BoxFit.cover,
                  cacheWidth: 312,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ),
            if (index == 0)
              Positioned(
                left: AppSpacing.xxs,
                top: AppSpacing.xxs,
                // 칸 이름이 이미 "필수" 를 읽어 준다 — 배지에서 또 읽으면 두 번 들린다.
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(color: AppColors.surfaceInk, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('필수', style: AppTypography.badge.copyWith(color: AppColors.onInk)),
                  ),
                ),
              ),
            Positioned(right: 0, top: 0, child: _RemoveButton(index: index, onRemove: onRemove)),
          ],
        ),
      ),
    );
  }
}

/// 삭제 X — 그림은 28 원(pen `uzGT9`, 모서리에서 4)이고 누르는 넓이는 44 로 키워 모서리에 붙인다(터치 영역 44+).
/// 원 색은 04-2 사진 칸 X(photo_tiles.dart `_PhotoTile`)와 같은 검정 60% — pen 마스터 `uzGT9` 를 같이 쓴다. 토큰이 없어 리터럴이다(보고).
/// 칸과 다른 낭독 칸으로 떼어 둔다(합쳐지면 칸 이름과 섞인다).
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.index, required this.onRemove});

  final int index;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '사진 ${index + 1} 빼기',
      child: GestureDetector(
        key: heartTaskPhotoRemoveKey(index),
        behavior: HitTestBehavior.opaque,
        onTap: () => onRemove(index),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.topRight,
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: SizedBox.square(
            dimension: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: const Icon(AppIcons.x, size: 14, color: AppColors.onInk),
            ),
          ),
        ),
      ),
    );
  }
}
