import 'dart:io';

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// 테스트가 사진 칸 · 삭제 X 를 찾는 표식.
const Key graduatePhotoSlotKey = ValueKey('graduate-photo-slot');
const Key graduatePhotoRemoveKey = ValueKey('graduate-photo-remove');

/// 사진 칸 한 변(pen `gCJ2p` 104×104).
const double _slotSize = 104;

/// 삭제 X 원(pen `oaPh3` = 마스터 `uzGT9` PhotoSlot · RemoveButton 28×28, 모서리 999, X 14 흰색) 지름.
const double _removeCircle = 28;

/// 누르는 넓이. 그림은 28 원 그대로 두고 누를 수 있는 넓이만 44 로 키운다(칸 오른쪽 위 모서리 안쪽에서).
const double _removeTouch = 44;

/// 삭제 X 원의 자리(pen `oaPh3` 절대 위치 x72 y4, 칸 기준).
const double _removeLeft = 72;
const double _removeTop = 4;

/// 졸업증명서 사진 칸(pen `gCJ2p` — 104×104 · 바탕 #EBEBEB · 모서리 14 · image 아이콘 28 #929292, 오른쪽 위 삭제 X 는
/// 절대 위치 x72 y4). 18b 사진 3장 시안(`fUFvU`) · 04-2 격자 칸과 같은 방식(프레임 + 삭제 X 인스턴스)이다.
///
/// 빈 칸 · 고른 칸은 시안에 한 장(채운 칸의 자리 표시)뿐이라 이렇게 정했다: 빈 칸은 같은 칸에 삭제 X 만 없고,
/// 고른 칸은 같은 칸에 사진을 꽉 채워(cover) 보인다. 칸을 누르면 갤러리를 연다(고른 뒤에는 바꾸기).
/// 올리는 중([isLocked])에는 칸도 X 도 눌리지 않는다. 눌림 효과는 칸 크기의 자기 Material 에 그린다(COMMON §4-2).
class GraduatePhotoSlot extends StatelessWidget {
  const GraduatePhotoSlot({
    required this.photo,
    required this.isLocked,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  final File? photo;
  final bool isLocked;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final picked = photo;
    return SizedBox(
      key: graduatePhotoSlotKey,
      width: _slotSize,
      height: _slotSize,
      child: Stack(
        children: [
          Positioned.fill(child: _tile(picked)),
          if (picked != null)
            Positioned(
              left: _slotSize - _removeTouch,
              top: 0,
              child: _RemoveButton(onPressed: onRemove),
            ),
        ],
      ),
    );
  }

  Widget _tile(File? picked) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      label: picked == null ? '졸업증명서 사진 추가' : '졸업증명서 사진 바꾸기',
      excludeSemantics: true,
      onTap: isLocked ? null : onPick,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: isLocked ? null : onPick,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.hairlineSoft,
              borderRadius: radius,
              // 읽지 못하는 파일이어도 회색 칸이 그대로 남는다 — 제출할 때 서버 · 압축이 다시 알려 준다.
              image: picked == null
                  ? null
                  : DecorationImage(image: FileImage(picked), fit: BoxFit.cover, onError: (_, _) {}),
            ),
            child: picked == null
                ? const Center(child: Icon(AppIcons.image, size: 28, color: AppColors.disabled))
                : null,
          ),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '사진 빼기',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          key: graduatePhotoRemoveKey,
          width: _removeTouch,
          height: _removeTouch,
          // 누르는 칸의 왼쪽 위가 칸 기준 (60, 0) 이라, 원은 그 안에서 (72-60, 4) 에 놓인다.
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: _removeLeft - (_slotSize - _removeTouch), top: _removeTop),
              child: Container(
                width: _removeCircle,
                height: _removeCircle,
                // pen 바탕 #00000099 — 사진 위 어두운 반투명 원(04-2 칸의 x 와 같다).
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                child: const Icon(AppIcons.x, size: 14, color: AppColors.onInk),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
