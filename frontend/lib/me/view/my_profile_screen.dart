import 'dart:async';

import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 화면 15 내 프로필(pen `r8oJc`). 헤더 → 아바타 → 실사진 → Facts → 선호 나이·키 → 자기소개.
/// pen 의 "아바타 다시 만들기"(`JaHig`)·"친구들이 본 나"(`ZCpM4`)·"프로필 수정"(`o0yhI0`)은 갈 화면이 없어 뺐다.
/// 앱바 톱니가 설정(16)으로 가는 유일한 문이다(DESIGN §9 화면 15).
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  /// "곧 열려요" 안내가 떠 있는 시간(사용자 결정 2026-09-27, 약 2초).
  static const Duration _toastDuration = Duration(seconds: 2);

  Timer? _toastTimer;
  var _isToastVisible = false;

  /// "실제 사진 교체" — 교체 화면이 아직 없어 안내만 잠깐 띄운다. 움직임 없이 나타나고 사라진다.
  void _showComingSoon() {
    _toastTimer?.cancel();
    setState(() => _isToastVisible = true);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _isToastVisible = false);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // pen `ffOFL` — 09b 첫 화면과 같은 관례: 제목 x20, 톱니 48 뒤 오른쪽 여백 8.
      appBar: AppBar(
        titleSpacing: 20,
        title: Text('내 프로필', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: '설정',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(AppIcons.settings, size: 22, color: AppColors.ink),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.me),
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          // 토스트 공통 규칙(DESIGN §8.5)은 "하단 버튼 위 12" — 이 화면엔 하단 버튼이 없어 하단 내비 위 12 에 둔다.
          if (_isToastVisible)
            const Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.sm,
              child: Center(
                child: AppToast(
                  leading: Icon(AppIcons.clock3, size: 16, color: AppColors.onInk),
                  label: '곧 열려요',
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 불러오는 중·실패는 pen 에 없는 상태다. 모양(가운데 로딩 / 가운데 문구 + "다시 시도")은 3c(`school_info_screen`)와
  /// 같고, 실패 문구만 다르다([_LoadError._message], 사용자 결정 2026-09-27).
  Widget _body() {
    return ref.watch(myProfileProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _LoadError(onRetry: _retry),
          data: (result) => result.when(
            onSuccess: (profile) => _ProfileContent(profile: profile, onReplacePhoto: _showComingSoon),
            onFailure: (_) => _LoadError(onRetry: _retry),
          ),
        );
  }

  void _retry() => ref.invalidate(myProfileProvider);
}

/// 조회 실패. 실패 사유와 상관없이 다시 해 보라는 안내 한 줄을 쓴다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  /// 사용자 결정 2026-09-27. 글자가 같은 `ServerUnavailableFailure` 는 뜻(502·503)이 달라 빌려 오지 않는다.
  static const _message = '잠시 뒤 다시 시도해 주세요';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_message, style: AppTypography.body.copyWith(color: AppColors.body)),
          AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// 본문 `lFotP` — 좌우 16, 위 0, 아래 32, 섹션 사이 24. 아바타↔실사진만 16(`Mcyik`).
class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile, required this.onReplacePhoto});

  final MyProfile profile;
  final VoidCallback onReplacePhoto;

  @override
  Widget build(BuildContext context) {
    final bio = profile.bio?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      children: [
        _IdentityHeader(profile: profile),
        const SizedBox(height: AppSpacing.lg),
        _AvatarSection(avatarUrl: profile.avatarUrl),
        const SizedBox(height: AppSpacing.md),
        _RealPhotoSection(photoUrls: profile.photoUrls, onReplace: onReplacePhoto),
        const SizedBox(height: AppSpacing.lg),
        _ProfileFacts(profile: profile),
        const SizedBox(height: AppSpacing.lg),
        ProfileEntryRow(icon: AppIcons.calendar, title: '선호 나이 범위', note: _ageRangeNote()),
        const SizedBox(height: AppSpacing.lg),
        ProfileEntryRow(icon: AppIcons.ruler, title: '선호 키 범위', note: _heightRangeNote()),
        // 온보딩이 필수로 받아 비는 일은 드물다 — 비면 섹션째 숨긴다(방어).
        if (bio.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _BioSection(bio: bio),
        ],
      ],
    );
  }

  /// "22세–27세"(pen `vFPb8` 그대로, en dash·띄어쓰기 없음). 06-1 "나이는 상관없어요"는 전 구간(19~35)으로 저장된다.
  /// 위 끝 35 는 06-1 처럼 "35세 이상"(사용자 결정 2026-09-27). 아래 끝 19 는 06-1 도 "19세" 라 그대로 둔다.
  String _ageRangeNote() {
    final (min, max) = (profile.preferredAgeMin, profile.preferredAgeMax);
    final isWholeRange = min == IdealConditionsUiState.ageFloor && max == IdealConditionsUiState.ageCeiling;
    if (min == null || max == null || isWholeRange) return _noPreference;
    final upper = max == IdealConditionsUiState.ageCeiling ? '$max세 이상' : '$max세';
    return '$min세–$upper';
  }

  /// "165cm ~ 180cm"(pen `Te5KQ` 그대로). 06-1 "키는 상관없어요"는 null 로 저장된다.
  /// 끝값 150·190 은 06-1 처럼 "150cm 이하"·"190cm 이상"(사용자 결정 2026-09-27) — 06-1 의 표기 함수는 private 이라 규칙을 여기 둔다.
  String _heightRangeNote() {
    final (min, max) = (profile.preferredHeightMin, profile.preferredHeightMax);
    if (min == null || max == null) return _noPreference;
    final lower = min == IdealConditionsUiState.heightFloor ? '${min}cm 이하' : '${min}cm';
    final upper = max == IdealConditionsUiState.heightCeiling ? '${max}cm 이상' : '${max}cm';
    return '$lower ~ $upper';
  }

  /// pen 화면 15 에 없는 상태 — 06-1 체크박스 문구와 같은 말을 쓴다(사용자 결정 2026-09-27).
  static const _noPreference = '상관없어요';
}

/// 섹션 제목 14/600 ink(`rxNdD` · `ZTAJF`). pen 줄높이 1.5 인데 렌더 높이는 22 — 22/14 로 맞춘다
/// (섹션 높이 280 = 22 + 8 + … 가 이 값으로 나온다).
final _sectionTitleStyle = AppTypography.labelSmall.copyWith(height: 22 / 14, color: AppColors.ink);

/// Identity Header `mHdp8` — 왼쪽 "닉네임, 나이" / "학교 · 학과", 오른쪽 위 학생 인증 배지(`af0TP`).
/// 배지는 늘 보인다 — `GET /me/profile` 은 인증된 사람만 닿는다.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final (age, major) = (profile.age, profile.major);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `xew8J` 렌더 높이 37(줄높이 1.5 속성, 렌더 37) — headline 토큰 1.35 대신 37/24.
              Text(
                age == null ? profile.nickname : '${profile.nickname}, $age',
                style: AppTypography.headline.copyWith(height: 37 / 24, color: AppColors.ink),
              ),
              // Name Copy `HHOzj` gap 3(토큰 밖 리터럴).
              const SizedBox(height: 3),
              // `q9by2M` 렌더 높이 22 — 헤더 62 = 37 + 3 + 22.
              Text(
                major == null ? profile.university : '${profile.university} · $major',
                style: AppTypography.bodySmall.copyWith(height: 22 / 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        // pen 은 space_between 이라 간격 속성이 없다 — 글자를 키웠을 때 배지에 붙지 않게만 둔다(1.0 자리는 같다).
        const SizedBox(width: AppSpacing.xs),
        const _InkBadge(icon: AppIcons.badgeCheck, label: '학생 인증'),
      ],
    );
  }
}

/// 잉크 알약 배지. 기본 = Z54et "Badge" `XPRBv`(패딩 [6,10], 아이콘 13),
/// [small] = "Badge · Small" `b4m05R`(패딩 [5,8], 아이콘 12). 둘 다 gap 4, 글자 11/600 렌더 18.
class _InkBadge extends StatelessWidget {
  const _InkBadge({required this.icon, required this.label, this.small = false});

  final IconData icon;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceInk, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Padding(
        // 패딩 5·6·10 은 pen 마스터 값(토큰 밖 리터럴).
        padding: small
            ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: small ? 12 : 13, color: AppColors.onInk),
            const SizedBox(width: AppSpacing.xxs),
            // 렌더 높이 18(`ANgbp` 44×18) — badge 토큰 1.30 대신 18/11. 배지 높이 30·28 이 이 값으로 나온다.
            Text(label, style: AppTypography.badge.copyWith(height: 18 / 11, color: AppColors.onInk)),
          ],
        ),
      ),
    );
  }
}

/// "상대에게는 이렇게 보여요" `p3iPK` — 제목, 8, 아바타 `w0ncIi` 328×198 가로 사각(모서리 14, cover).
/// 아바타가 없을 때는 pen 에 없다 — 같은 크기의 surface-soft 빈 칸으로 둔다(대장 지시 2026-09-27).
class _AvatarSection extends StatelessWidget {
  const _AvatarSection({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('상대에게는 이렇게 보여요', style: _sectionTitleStyle),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          image: true,
          label: '내 AI 아바타',
          // 그림은 decoration 으로 깐다 — Image 위젯은 그림 비율로 제 높이를 주장한다. 이미지 칸이라 198 고정.
          child: Container(
            height: 198,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: url == null ? AppColors.surfaceSoft : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              image: url == null ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
            ),
            child: const Stack(
              children: [
                // `CRZX0` x238 y14 → 위 14, 오른쪽 13(토큰 밖 리터럴).
                Positioned(top: 14, right: 13, child: _InkBadge(icon: AppIcons.sparkles, label: 'AI 아바타', small: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 실사진 섹션 `fwReS` — 제목, 8, 슬라이더 `o2Nhn`(점 포함), 8, "실제 사진 교체" `M1OptH`.
class _RealPhotoSection extends StatelessWidget {
  const _RealPhotoSection({required this.photoUrls, required this.onReplace});

  final List<String> photoUrls;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('서로 수락하면 전달돼요', style: _sectionTitleStyle),
        const SizedBox(height: AppSpacing.xs),
        PhotoSlider(
          photos: [for (final url in photoUrls) NetworkImage(url)],
          // 사진 `T09a8` 252×184.
          photoSize: const Size(252, 184),
          firstPhotoBadge: const _InkBadge(icon: AppIcons.lock, label: '수락 후 공개', small: true),
        ),
        const SizedBox(height: AppSpacing.xs),
        _ReplacePhotoButton(onTap: onReplace),
      ],
    );
  }
}

/// "실제 사진 교체" `M1OptH` 328×44, surface-strong, 모서리 8. 교체 화면이 아직 없어 누르면 안내만 띄운다.
class _ReplacePhotoButton extends StatelessWidget {
  const _ReplacePhotoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 스크롤 안의 탭 위젯이라 눌림 효과를 그릴 Material 을 버튼 크기로 둔다 — 배경색도 이 Material 이 칠한다(COMMON §4-2).
    return Material(
      color: AppColors.surfaceStrong,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        // pen 높이 44 는 최소값이다 — 글자를 키우면 버튼이 늘어난다(DESIGN §11.2).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Text(
              '실제 사진 교체',
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(height: 1.5, color: AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile Facts `FxO58` — surface-soft 카드(패딩 위아래 4 · 좌우 16, 모서리 14), 48 행 셋, 구분선 없음.
/// MBTI 가 없으면 "선택 안 함"(사용자 결정 2026-09-27), 키·학과가 없으면 "-"(판단값 — 온보딩 필수라 드물다).
class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final height = profile.heightCm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        children: [
          _FactRow(icon: AppIcons.ruler, label: '내 키', value: height == null ? '-' : '${height}cm'),
          _FactRow(icon: AppIcons.badge, label: 'MBTI', value: profile.mbti ?? '선택 안 함'),
          _FactRow(icon: AppIcons.graduationCap, label: '학과', value: profile.major ?? '-'),
        ],
      ),
    );
  }
}

/// Facts 행(`pedOI` · `NL9X7` · `K4N2c`) — 아이콘 19 → 10 → 라벨 → Spacer → 값(오른쪽 끝).
class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // pen 높이 48 은 최소값이다 — 글자를 키우면 행이 늘어난다(DESIGN §11.2).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          // 아이콘 19·gap 10 은 pen 값(토큰 밖 리터럴).
          Icon(icon, size: 19, color: AppColors.muted),
          const SizedBox(width: 10),
          Text(label, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted)),
          // pen 은 라벨 · gap 10 · Spacer · gap 10 · 값 — 값을 Expanded 로 오른쪽에 붙여 길어지면 줄을 바꾼다.
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.labelSmall.copyWith(height: 1.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// 자기소개 `pP9uk` — 카드 아님(채움 없음). 제목 `ISElO` 14/600 렌더 21, 8, 본문 `i6XFiC` 16/400 body.
class _BioSection extends StatelessWidget {
  const _BioSection({required this.bio});

  final String bio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('자기소개', style: AppTypography.labelSmall.copyWith(height: 1.5, color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        // 렌더 75 = 3줄 × 25 — body 토큰 1.60 대신 25/16.
        Text(bio, style: AppTypography.body.copyWith(height: 25 / 16, color: AppColors.body)),
      ],
    );
  }
}
