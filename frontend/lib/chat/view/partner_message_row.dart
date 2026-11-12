import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 말풍선 옆 상대 사진 지름(pen `CxCs7` 36×36).
const double _bubbleFaceSize = 36;

/// 이어지는 줄의 왼쪽 비움(pen `C5V6P` 44) = 사진 36 + 사진과 말풍선 사이 8.
const double _continuedInset = _bubbleFaceSize + AppSpacing.xs;

/// 상대 얼굴 동그라미(채팅방 제목 32 · 말풍선 옆 36). 무엇을 보일지는 `ChatRoom.partnerFaceUrl` 이 정한다.
/// 그림이 없으면 회색 면 + 사람 아이콘(지름의 절반)이다.
class PartnerFace extends StatelessWidget {
  const PartnerFace({required this.url, required this.size, super.key});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = url;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Icon(AppIcons.userRound, size: size / 2, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: image, fit: BoxFit.cover),
    );
  }
}

/// 상대 말풍선 한 줄(카카오톡처럼, 사용자 결정 11-12).
/// - [PartnerMessageRow.first]: 묶음 첫 줄(pen `H9vQHd`) — 왼쪽 사진 36, 사이 8, 오른쪽에 닉네임 → 4 → 말풍선. 위 정렬.
/// - [PartnerMessageRow.continued]: 이어지는 줄(pen `C5V6P`) — 사진 자리만큼 왼쪽 44 를 비운다.
///
/// [bubble] 은 기존 `MessageBubble`(pen `fm3rk`) 그대로다. 최대 폭 78% 는 남은 폭 안에서 지켜진다.
class PartnerMessageRow extends StatelessWidget {
  const PartnerMessageRow.first({
    required String this.nickname,
    required this.photoUrl,
    required this.onOpenProfile,
    required this.bubble,
    super.key,
  });

  const PartnerMessageRow.continued({required this.bubble, super.key})
      : nickname = null,
        photoUrl = null,
        onOpenProfile = null;

  /// 묶음 첫 줄에만 있다. null 이면 이어지는 줄이다.
  final String? nickname;
  final String? photoUrl;

  /// 사진을 누르면 상대 소개(14c)로 간다. 상대가 나간 방이면 null — 누를 수 없다(14c 가 404).
  final VoidCallback? onOpenProfile;
  final Widget bubble;

  @override
  Widget build(BuildContext context) {
    final name = nickname;
    if (name == null) {
      return Padding(padding: const EdgeInsets.only(left: _continuedInset), child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xs,
      children: [
        _face(context, name),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.xxs,
            children: [
              // pen `LpIpn` 12 / 600 / 1.4 / #222222.
              Text(name, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
              bubble,
            ],
          ),
        ),
      ],
    );
  }

  Widget _face(BuildContext context, String name) {
    final face = PartnerFace(url: photoUrl, size: _bubbleFaceSize);
    final onTap = onOpenProfile;
    if (onTap == null) {
      return face;
    }
    return Semantics(
      button: true,
      label: context.l10n.chatPartnerProfileOpen(nickname: name),
      // 그림 안쪽 노드를 지워서 탭 동작은 이 노드가 직접 건다.
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(onTap: onTap, child: face),
    );
  }
}
