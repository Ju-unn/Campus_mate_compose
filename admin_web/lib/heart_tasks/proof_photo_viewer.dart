import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/theme/admin_colors.dart';
import 'package:campus_mate_admin/theme/admin_spacing.dart';
import 'package:campus_mate_admin/theme/admin_typography.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_dialog.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/tap_box.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 사진이 그려지지 않았다(서명 만료 · 깨진 파일) — 그 주소를 알린다.
typedef PhotoErrorCallback = void Function(String url);

/// pen Web/PhotoViewer(DKRDo · A3 xTCUl): 큰 사진 380 높이(폭은 칸 — 1440 에서 440) → 12 → "지난 제출" + 썸네일 64(사이 12).
/// 썸네일은 시안 72 였으나 서버 최대 5개가 440 한 줄에 들어가게 64 로 줄였다(대장 결정 10-18, pen 도 같이 고침).
/// 큰 사진: web-surface-strong · web-outline 1 · 모서리 14, 캡처 전체가 보이게 contain(대장 결정 10-18), 누르면 크게 보기.
/// 사진 없음(RmiFS): image-off 40 + "사진 없음" — 썸네일은 image-off 20. 받는 중 · 못 받음은 pen 에 없는 상태(대장 보고표).
class ProofPhotoViewer extends StatelessWidget {
  const ProofPhotoViewer({
    super.key,
    required this.detail,
    required this.onOpen,
    required this.onPhotoError,
    required this.onRetry,
  });

  final AsyncValue<HeartTaskDetail> detail;

  /// 사진 하나를 크게 본다 — 인자는 그 사진의 제출 번호(고른 건 또는 지난 제출)
  final ValueChanged<String> onOpen;
  final PhotoErrorCallback onPhotoError;
  final VoidCallback onRetry;

  static const double photoHeight = 380;
  static const double thumbSize = 64;

  @override
  Widget build(BuildContext context) {
    final loaded = detail.value;
    final url = detail.isLoading ? null : loaded?.photoUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapBox(
          key: const ValueKey('proof-photo'),
          onTap: url == null ? null : () => onOpen(loaded!.item.id),
          cursor: SystemMouseCursors.zoomIn,
          semanticLabel: url == null ? null : '인증샷 크게 보기',
          color: AdminColors.surfaceStrong,
          side: const BorderSide(color: AdminColors.outline),
          radius: AdminRadius.md,
          width: double.infinity,
          height: photoHeight,
          child: _bigPhoto(url),
        ),
        const SizedBox(height: AdminSpacing.sm),
        SizedBox(height: thumbSize, child: _history(context)),
      ],
    );
  }

  Widget _bigPhoto(String? url) {
    if (detail.isLoading) return const Center(child: AdminLoader(color: AdminColors.muted));
    if (detail.hasError) {
      return PhotoPlaceholder(
        icon: LucideIcons.circleAlert,
        label: '사진을 불러오지 못했어요',
        action: AdminButton(label: '다시 시도', variant: AdminButtonVariant.text, onPressed: onRetry),
      );
    }
    if (url == null) return const PhotoPlaceholder(icon: LucideIcons.imageOff, label: '사진 없음');
    return ProofImage(
      url: url,
      fit: BoxFit.contain,
      onError: onPhotoError,
      loading: const Center(child: AdminLoader(color: AdminColors.muted)),
      fallback: const PhotoPlaceholder(icon: LucideIcons.imageOff, label: '사진 없음'),
    );
  }

  Widget _history(BuildContext context) {
    final previous = detail.isLoading ? null : detail.value?.previous;
    final caption = AdminTypography.xsStrong.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted);
    return Row(
      children: [
        Text('지난 제출', style: caption),
        const SizedBox(width: AdminSpacing.sm),
        if (previous != null && previous.isEmpty)
          Text('없어요', style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.muted)),
        if (previous != null && previous.isNotEmpty)
          Expanded(
            // 5개(서버 최대)는 440 칸 한 줄에 들어간다(글자 약 48 + 12 + 64×5 + 12×4). 최소 창(1280)처럼 칸이 좁을 때만
            // 넘치지 않고 이 줄만 가로로 밀린다.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, photo) in previous.indexed) ...[
                      if (i > 0) const SizedBox(width: AdminSpacing.sm),
                      _Thumb(photo: photo, onOpen: onOpen, onError: onPhotoError),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onOpen, required this.onError});

  final HeartTaskPrevious photo;
  final ValueChanged<String> onOpen;
  final PhotoErrorCallback onError;

  @override
  Widget build(BuildContext context) {
    final url = photo.photoUrl;
    const missing = Center(child: Icon(LucideIcons.imageOff, size: 20, color: AdminColors.disabled));
    return TapBox(
      key: ValueKey('proof-thumb-${photo.id}'),
      onTap: url == null ? null : () => onOpen(photo.id),
      cursor: SystemMouseCursors.zoomIn,
      semanticLabel: url == null ? null : '지난 제출 ${formatSubmittedAt(photo.createdAt)} 크게 보기',
      color: AdminColors.surfaceStrong,
      side: const BorderSide(color: AdminColors.outline),
      width: ProofPhotoViewer.thumbSize,
      height: ProofPhotoViewer.thumbSize,
      child: url == null ? missing : ProofImage(url: url, fit: BoxFit.cover, onError: onError, fallback: missing),
    );
  }
}

/// 큰 칸 · 크게 보기의 안내 그림(pen vyryA · Cpr6U): 아이콘(web-disabled) → 8 → 글자 14/600 web-muted.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, required this.icon, required this.label, this.iconSize = 40, this.action});

  final IconData icon;
  final String label;
  final double iconSize;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: AdminColors.disabled),
          const SizedBox(height: AdminSpacing.xs),
          Text(label, style: AdminTypography.smStrong.copyWith(height: AdminTypography.smBox, color: AdminColors.muted)),
          if (action != null) ...[const SizedBox(height: AdminSpacing.xs), action],
        ],
      ),
    );
  }
}

/// 인증샷 한 장. 주소 → 그림은 [proofImageProvider](웹은 Image.network 와 같은 NetworkImage — Storage 가
/// `Access-Control-Allow-Origin: *` 를 답해 CanvasKit 의 바이트 받기가 막히지 않는다). 칸을 꽉 채워 [fit] 으로 그린다.
/// 못 그리면 [onError] 로 주소를 알리고 [fallback] 을 보인다.
class ProofImage extends ConsumerWidget {
  const ProofImage({super.key, required this.url, required this.fit, required this.onError, required this.fallback, this.loading});

  final String url;
  final BoxFit fit;
  final PhotoErrorCallback onError;
  final Widget fallback;

  /// 바이트를 받는 동안 보일 것. null 이면 빈 칸.
  final Widget? loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = this.loading;
    return Image(
      image: ref.watch(proofImageProvider)(url),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      // 사진 내용은 화면 읽기로 알 수 없다 — 이름은 감싼 칸("인증샷 크게 보기")이 읽힌다.
      excludeFromSemantics: true,
      frameBuilder: loading == null
          ? null
          : (context, child, frame, synchronous) => synchronous || frame != null ? child : loading,
      errorBuilder: (context, error, stackTrace) {
        onError(url);
        return fallback;
      },
    );
  }
}

/// 크게 보기를 띄운다(pen gpMkm). 나타남 · 사라짐은 관리자 대화상자와 같다(200ms · 150ms, 동작 줄이기면 바로).
Future<void> showProofZoom(BuildContext context, {required String? initialId, required String photoId}) {
  return showAdminDialog<void>(context, (_) => ProofZoom(initialId: initialId, photoId: photoId));
}

/// 주소 하나를 같은 크게 보기로 띄운다(A4 신고 사본의 아바타 · 실사진). 이미 썸네일로 받은 그림이라 대개 바로 그려지고,
/// 서명이 만료돼 못 그리면 "사진 없음" — 상세를 다시 받으면 새 주소가 온다.
Future<void> showPhotoZoom(BuildContext context, String url) {
  const waiting = _ZoomFrame(child: Center(child: AdminLoader(color: AdminColors.muted)));
  const missing = _ZoomFrame(child: PhotoPlaceholder(icon: LucideIcons.imageOff, label: '사진 없음', iconSize: 48));
  return showAdminDialog<void>(
    context,
    (_) => PhotoZoomOverlay(
      photo: ProofImage(url: url, fit: BoxFit.contain, onError: (_) {}, loading: waiting, fallback: missing),
    ),
  );
}

/// pen A3 사진 크게 보기(gpMkm): 전체 web-scrim 위 사진(화면 90% 안 contain), 오른쪽 위 닫기 44(✕ 24 흰색),
/// 아래 web-ink 알약 "Esc 또는 바깥을 누르면 닫혀요" 12 흰 글자. 다운로드는 없다.
/// 사진 · 빈자리 어디를 눌러도 닫힌다(사진은 누를 것이 아니라 눌림을 아래 막(barrier)으로 흘린다).
/// 서명이 만료돼 못 그리면 그 건을 다시 받아(화면과 같은 길) 새 주소로 다시 그린다.
class ProofZoom extends ConsumerStatefulWidget {
  const ProofZoom({super.key, required this.initialId, required this.photoId});

  final String? initialId;
  final String photoId;

  @override
  ConsumerState<ProofZoom> createState() => _ProofZoomState();
}

class _ProofZoomState extends ConsumerState<ProofZoom> {
  final Set<String> _reported = <String>{};

  void _onError(String detailId, String url) {
    if (!_reported.add(url)) return;
    // 그리는 중에는 상태를 바꿀 수 없다 — 이 장면이 끝난 뒤 알린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(heartTaskReviewProvider(widget.initialId).notifier).photoFailed(detailId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(heartTaskReviewProvider(widget.initialId).select((s) => s.detail));
    final loaded = detail?.value;
    final String? url;
    if (loaded == null || detail!.isLoading) {
      url = null;
    } else if (loaded.item.id == widget.photoId) {
      url = loaded.photoUrl;
    } else {
      url = loaded.previous.where((p) => p.id == widget.photoId).firstOrNull?.photoUrl;
    }
    const waiting = _ZoomFrame(child: Center(child: AdminLoader(color: AdminColors.muted)));
    const missing = _ZoomFrame(child: PhotoPlaceholder(icon: LucideIcons.imageOff, label: '사진 없음', iconSize: 48));
    final Widget photo;
    if (loaded == null || detail!.isLoading) {
      photo = waiting;
    } else if (url == null) {
      photo = missing;
    } else {
      photo = ProofImage(
        url: url,
        fit: BoxFit.contain,
        onError: (failed) => _onError(loaded.item.id, failed),
        loading: waiting,
        fallback: missing,
      );
    }
    return PhotoZoomOverlay(photo: photo);
  }
}

/// 크게 보기 틀(pen gpMkm): 사진(화면 90% 안) · 오른쪽 위 닫기 44 · 아래 안내 알약. 사진은 누를 것이 아니라 눌림을
/// 아래 막(barrier)으로 흘려 어디를 눌러도 닫힌다.
class PhotoZoomOverlay extends StatelessWidget {
  const PhotoZoomOverlay({super.key, required this.photo});

  final Widget photo;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Stack(
      key: const ValueKey('proof-zoom'),
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screen.width * 0.9, maxHeight: screen.height * 0.9),
                child: photo,
              ),
            ),
          ),
        ),
        Positioned(
          top: AdminSpacing.md,
          right: AdminSpacing.md,
          child: TapBox(
            key: const ValueKey('proof-zoom-close'),
            onTap: () => Navigator.of(context).pop(),
            semanticLabel: '닫기',
            width: AdminSizes.control,
            height: AdminSizes.control,
            radius: AdminRadius.pill,
            overlayColor: AdminColors.onPrimary,
            focusColor: AdminColors.onPrimary,
            child: const Center(child: Icon(LucideIcons.x, size: 24, color: AdminColors.onPrimary)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          // pen KnNnS: y 826 · 높이 28 (900 화면 아래 46)
          bottom: 46,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: AdminColors.ink, borderRadius: BorderRadius.circular(AdminRadius.pill)),
                child: Text(
                  'Esc 또는 바깥을 누르면 닫혀요',
                  style: AdminTypography.xs.copyWith(height: AdminTypography.xsBox, color: AdminColors.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 크게 보기에서 사진이 없을 때의 틀(pen Cpr6U 시안 900×620 · web-surface-strong · 모서리 14)
class _ZoomFrame extends StatelessWidget {
  const _ZoomFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 900,
      height: 620,
      decoration: BoxDecoration(color: AdminColors.surfaceStrong, borderRadius: BorderRadius.circular(AdminRadius.md)),
      child: child,
    );
  }
}
