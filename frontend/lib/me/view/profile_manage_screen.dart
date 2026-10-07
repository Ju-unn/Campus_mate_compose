import 'dart:math' as math;

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15-5 프로필 편집(pen `rrJ27`). 화면 15 입구 "프로필 편집"(`sC8BR`)이 연다. 실제 사진 → 기본 정보 → 선호 조건 →
/// 자기소개 — 화면 15 에 있던 섹션을 옮겨 왔다(계획서 N1). 저장 버튼 · 하단 내비는 없다 — 섹션마다 편집 화면에서
/// 저장하고, 편집 화면이 저장 뒤 내 프로필을 다시 읽게 하고 pop 해 이 화면으로 돌아온다(N8 · N19).
class ProfileManageScreen extends ConsumerStatefulWidget {
  const ProfileManageScreen({super.key});

  @override
  ConsumerState<ProfileManageScreen> createState() => _ProfileManageScreenState();
}

class _ProfileManageScreenState extends ConsumerState<ProfileManageScreen> with MeToastHost<ProfileManageScreen> {
  /// "수정 ›" → 15-6 기본 정보 수정(A16). 저장하고 돌아오면(true) "저장했어요" 를 잠깐 띄운다(B4 — 다른 편집 화면은 토스트 없이
  /// 돌아온다). 새 값은 15-6 이 invalidate 한 내 프로필을 이 화면이 다시 읽어 그린다(N8).
  Future<void> _editBasicInfo() async {
    final saved = await context.push<bool>(AppRoutes.myBasicInfo);
    if (saved ?? false) showTimedToast(savedToast);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EditAppBar(title: '프로필 편집'),
      // 하단 버튼도 내비도 없어 토스트는 화면 아래 12 에 뜬다(pen 에 뜨는 자리가 없다 — 편차 기록).
      body: SafeArea(top: false, child: MeToastLayer(toast: timedToast, child: _body())),
    );
  }

  /// 불러오는 중 · 실패는 pen 에 없는 상태다 — 화면 15 와 같은 모양(가운데 로딩 / [MeLoadError], 계획서 N9).
  Widget _body() {
    return ref.watch(myProfileProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MeLoadError(onRetry: _retry),
          data: (result) => result.when(
            onSuccess: (profile) => _ManageContent(profile: profile, onEditBasicInfo: _editBasicInfo),
            onFailure: (_) => MeLoadError(onRetry: _retry),
          ),
        );
  }

  void _retry() => ref.invalidate(myProfileProvider);
}

/// 본문 `H4VWO` — 위 24 · 좌우 16 · 아래 40, 섹션 사이 32.
class _ManageContent extends StatelessWidget {
  const _ManageContent({required this.profile, required this.onEditBasicInfo});

  final MyProfile profile;
  final VoidCallback onEditBasicInfo;

  /// 본문 아래 여백 40 은 pen 값(간격 토큰 xl 32 · xxl 48 사이).
  static const double _bottomPadding = 40;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, _bottomPadding),
      children: [
        _RealPhotoSection(photoUrls: profile.photoUrls, onReplace: () => context.push(AppRoutes.myPhotos)),
        // 섹션 사이 32 를 기본 정보 상자 안에 둔다 — "수정 ›" 누름 칸이 그 자리로 삐져나간다([_BasicInfoSection]).
        _BasicInfoSection(profile: profile, topGap: AppSpacing.xl, onEdit: onEditBasicInfo),
        const SizedBox(height: AppSpacing.xl),
        _PreferenceSection(profile: profile),
        const SizedBox(height: AppSpacing.xl),
        _BioSection(bio: profile.bio),
      ],
    );
  }
}

/// 섹션 헤더 제목 17/700 ink — 줄높이 속성 없음 · 렌더 25(subtitle 토큰 17/600 에 굵기만 700).
final _headerTitleStyle =
    AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700, height: 25 / 17, color: AppColors.ink);

/// 섹션 헤더 오른쪽 글자 14/400 muted — 줄높이 속성 없음 · 렌더 20.
final _headerNoteStyle = AppTypography.bodySmall.copyWith(height: 20 / 14, color: AppColors.muted);

/// SectionHeader `Ymhdq` — 제목 왼쪽, 오른쪽 글자(`A8LX2`) 오른쪽 끝(space_between), 세로 가운데.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.note});

  final String title;

  /// 오른쪽 회색 글자. null 이면 제목만(pen `A8LX2` 꺼짐).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final trailing = note;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: _headerTitleStyle),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          // 글자를 키워 한 줄에 안 들어가면 제목을 밀지 않고 오른쪽 글자가 줄을 바꾼다.
          Flexible(child: Text(trailing, textAlign: TextAlign.end, style: _headerNoteStyle)),
        ],
      ],
    );
  }
}

/// 실제 사진 `Rn3AC` — 헤더 → 12 → 슬라이더(`c9Co2`) → 12 → 점(`RaYKc`) → 12 → "실제 사진 교체"(`E7Cv2`).
/// 섹션이 gap 12 한 벌이라 사진 ↔ 점도 12 다(공용 [PhotoSlider] 기본 8 은 화면 15 · 14c 값).
class _RealPhotoSection extends StatelessWidget {
  const _RealPhotoSection({required this.photoUrls, required this.onReplace});

  final List<String> photoUrls;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: '실제 사진', note: '서로 수락하면 전달돼요'),
        const SizedBox(height: AppSpacing.sm),
        PhotoSlider(
          photos: [for (final url in photoUrls) NetworkImage(url)],
          // 사진 `gw2bo` 252×184.
          photoSize: const Size(252, 184),
          firstPhotoBadge: const _LockBadge(),
          dotsGap: AppSpacing.sm,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ReplacePhotoButton(onTap: onReplace),
      ],
    );
  }
}

/// "수락 후 공개" `r6b8Vu`(Badge · Small `b4m05R`) — ink 알약, 패딩 [5,8], lock 12, gap 4, 11/600 렌더 18(높이 28).
class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceInk, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Padding(
        // 세로 5 는 pen 마스터 값(토큰 밖 리터럴).
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.lock, size: 12, color: AppColors.onInk),
            const SizedBox(width: AppSpacing.xxs),
            // 렌더 높이 18 — badge 토큰 1.30 대신 18/11.
            Text('수락 후 공개', style: AppTypography.badge.copyWith(height: 18 / 11, color: AppColors.onInk)),
          ],
        ),
      ),
    );
  }
}

/// "실제 사진 교체" `E7Cv2` 328×44, surface-strong, 모서리 8, 14/600 ink. 누르면 15-7 사진 수정(A15).
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

/// 기본 정보 `QldHz` — 헤더 "기본 정보" + "수정 ›"(`A8LX2`) → 12 → 카드(`N1dIuc`).
///
/// "수정 ›" 는 pen 에서 34×20 인데 누름 칸은 44 다(N12). 헤더를 44 로 키우면 pen 간격이 어긋나므로 44 칸을 헤더 위에
/// 겹쳐 세로 가운데를 맞춘다. 칸이 위로 삐져나가는 몫은 이 상자 안이어야 눌린다 — 상자 밖은 누름 검사가 닿지 않는다.
/// 그래서 위 섹션과의 간격 [topGap] 을 상자 안에 둔다(15c `_TagSection` 과 같은 방식).
class _BasicInfoSection extends StatelessWidget {
  const _BasicInfoSection({required this.profile, required this.topGap, required this.onEdit});

  final MyProfile profile;
  final double topGap;
  final VoidCallback onEdit;

  /// 대장 결정 N12(pen 높이 20 → 누름 44).
  static const double _tapTarget = 44;

  @override
  Widget build(BuildContext context) {
    // 헤더 한 줄 높이(배율 1.0 에서 25). 이 줄 가운데에 누름 칸을 맞춘다 — 글자를 키워도 "수정 ›" 이 제목과 나란하다.
    final lineHeight = MediaQuery.textScalerOf(context).scale(_headerTitleStyle.fontSize!) * _headerTitleStyle.height!;
    final linkHeight = math.max(lineHeight, _tapTarget);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(top: topGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionHeader(title: '기본 정보'),
              const SizedBox(height: AppSpacing.sm),
              _ProfileFacts(profile: profile),
            ],
          ),
        ),
        Positioned(
          top: topGap + (lineHeight - linkHeight) / 2,
          right: 0,
          child: _EditLink(minHeight: linkHeight, onTap: onEdit),
        ),
      ],
    );
  }
}

/// "수정 ›" `A8LX2` — 14/400 muted 글자만(N12 — 15c `cOkl1` 의 분홍 "수정" 과 다르다, 화면마다 pen 기준).
/// 누름 칸은 최소 44×44, 글자는 칸 오른쪽 끝.
class _EditLink extends StatelessWidget {
  const _EditLink({required this.minHeight, required this.onTap});

  final double minHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 스크롤 안의 탭 위젯이라 눌림 효과를 그릴 Material 을 칸 크기로 둔다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: _BasicInfoSection._tapTarget, minHeight: minHeight),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            heightFactor: 1,
            child: Text('수정 ›', style: _headerNoteStyle),
          ),
        ),
      ),
    );
  }
}

/// 기본 정보 카드 `N1dIuc` — #FFFFFF · 모서리 14 · 카드 그림자 두 겹([AppElevation.card], 사용자 결정 09-28 —
/// ProfileEntryRow `fN0xc` 는 10-01 개편으로 [AppElevation.row] 한 겹이 됐다),
/// 패딩 위아래 4 · 좌우 16, 48 행 셋, 구분선 없음. MBTI 가 없으면 "선택 안 함"(사용자 결정 2026-09-27), 키·학과가 없으면
/// "-"(판단값 — 온보딩 필수라 드물다).
class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final height = profile.heightCm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppElevation.card,
      ),
      child: Column(
        children: [
          _FactRow(icon: AppIcon3d.ruler, label: '내 키', value: height == null ? '-' : '${height}cm'),
          _FactRow(icon: AppIcon3d.mbti, label: 'MBTI', value: profile.mbti ?? '선택 안 함'),
          _FactRow(icon: AppIcon3d.graduationCap, label: '학과', value: profile.major ?? '-'),
        ],
      ),
    );
  }
}

/// 기본 정보 행(`wBr7Y` · `qEL5S` · `G3QdoO`) — 아이콘 20 → 10 → 라벨 → Spacer → 값(오른쪽 끝).
class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, required this.value});

  final AppIcon3d icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // pen 높이 48 은 최소값이다 — 글자를 키우면 행이 늘어난다(DESIGN §11.2).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          // 3D 아이콘 20(`morjL` · `mwlRq` · `qKYxh`)·gap 10 은 pen 값(토큰 밖 리터럴).
          Icon3d(icon, size: 20),
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

/// 선호 조건 `J0ZhR6` — 헤더(오른쪽 없음) → 12 → ProfileEntryRow 두 개(`sR3If` · `t1Eok`, 사이 12).
/// 두 행 모두 06-1 편집으로 간다 — 나이 · 키가 한 화면에 있다(U1).
class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: '선호 조건'),
        const SizedBox(height: AppSpacing.sm),
        ProfileEntryRow(
          icon: AppIcon3d.calendar,
          title: '선호 나이 범위',
          note: _ageRangeNote(),
          onTap: () => context.push(AppRoutes.myIdealConditions),
        ),
        const SizedBox(height: AppSpacing.sm),
        ProfileEntryRow(
          icon: AppIcon3d.ruler,
          title: '선호 키 범위',
          note: _heightRangeNote(),
          onTap: () => context.push(AppRoutes.myIdealConditions),
        ),
      ],
    );
  }

  /// "22세–27세"(pen 그대로, en dash·띄어쓰기 없음). 06-1 "나이는 상관없어요"는 전 구간(19~35)으로 저장된다.
  /// 위 끝 35 는 06-1 처럼 "35세 이상"(사용자 결정 2026-09-27). 아래 끝 19 는 06-1 도 "19세" 라 그대로 둔다.
  String _ageRangeNote() {
    final (min, max) = (profile.preferredAgeMin, profile.preferredAgeMax);
    final isWholeRange = min == IdealConditionsUiState.ageFloor && max == IdealConditionsUiState.ageCeiling;
    if (min == null || max == null || isWholeRange) return _noPreference;
    final upper = max == IdealConditionsUiState.ageCeiling ? '$max세 이상' : '$max세';
    return '$min세–$upper';
  }

  /// "165cm ~ 180cm"(pen 그대로). 06-1 "키는 상관없어요"는 null 로 저장된다.
  /// 끝값 150·190 은 06-1 처럼 "150cm 이하"·"190cm 이상"(사용자 결정 2026-09-27) — 06-1 의 표기 함수는 private 이라 규칙을 여기 둔다.
  String _heightRangeNote() {
    final (min, max) = (profile.preferredHeightMin, profile.preferredHeightMax);
    if (min == null || max == null) return _noPreference;
    final lower = min == IdealConditionsUiState.heightFloor ? '${min}cm 이하' : '${min}cm';
    final upper = max == IdealConditionsUiState.heightCeiling ? '${max}cm 이상' : '${max}cm';
    return '$lower ~ $upper';
  }

  /// pen 에 없는 상태 — 06-1 체크박스 문구와 같은 말을 쓴다(사용자 결정 2026-09-27).
  static const _noPreference = '상관없어요';
}

/// 자기소개 `jVQAw` — 헤더(오른쪽 없음) → 12 → 본문 `IUPXc` 16/400 body 줄높이 1.6 → 12 → 15c 입구 행 `bTDTS`.
/// 본문이 비면(온보딩이 필수로 받아 드물다 — 방어) 본문만 숨긴다. 입구 행은 남아야 자기소개를 다시 채울 수 있다.
class _BioSection extends StatelessWidget {
  const _BioSection({required this.bio});

  final String? bio;

  @override
  Widget build(BuildContext context) {
    final text = bio?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: '자기소개'),
        const SizedBox(height: AppSpacing.sm),
        if (text.isNotEmpty) ...[
          Text(text, style: AppTypography.body.copyWith(color: AppColors.body)),
          const SizedBox(height: AppSpacing.sm),
        ],
        ProfileEntryRow(
          icon: AppIcon3d.tags,
          title: '자기소개 · 태그',
          note: '관심사 · 나의 특징 · 이상형',
          onTap: () => context.push(AppRoutes.myProfileEdit),
        ),
      ],
    );
  }
}
