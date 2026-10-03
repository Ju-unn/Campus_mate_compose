import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/viewmodel/faq_provider.dart';
import 'package:campus_mate/faq/viewmodel/faq_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 자주 묻는 질문(DESIGN §8.13 · §9 화면 21, pen `fszuX`). 설정(16) "자주 묻는 질문" 줄이 연다.
class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faq = ref.watch(faqProvider);
    final ui = ref.watch(faqViewModelProvider);
    final vm = ref.read(faqViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text('자주 묻는 질문', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        centerTitle: false,
        // pen `OX1DW`: 뒤로 48(`xCEi8`, 왼쪽 8) + 간격 4 → 제목 x60.
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
          ),
        ),
      ),
      body: SafeArea(
        child: switch (faq.value) {
          // 받는 중 — pen 에 모양이 없어 기존 앱 모양(편차). 못 받고 캐시도 없으면 설정 줄이 숨어 여기 올 일이 없다.
          null => const Center(child: CircularProgressIndicator()),
          final items => Column(
            children: [
              _SearchField(query: ui.query, searching: ui.searching, onChanged: vm.search),
              // 검색 중에는 결과가 탭과 상관없이 전 묶음이라 탭 줄을 숨긴다 — 고른 탭은 기억해 두었다가 검색어를 지우면 돌아간다.
              if (!ui.searching) _Tabs(selected: ui.selected, onTap: vm.selectTab),
              Expanded(
                child: _FaqList(
                  key: const ValueKey('faq-list'),
                  sections: faqSections(items, ui),
                  showHeaders: ui.searching,
                  expandedId: ui.expandedId,
                  onTap: vm.toggle,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// 검색칸 = 공용 SearchField(pen `y7Qlw`, 대장 10-03 — 21 의 `u4ntu` 는 옛 TextInput 인스턴스라 따르지 않는다):
/// 48 · #F7F7F7 · r12 · 테두리 없음 · 좌우 16 · 간격 8, 3D 돋보기 24, 안내 14 muted.
/// 글자가 있으면 뒤에 ✕(21-1 `nXpvH/uvQHG`, 누름 48 — 대장 09-29). 아래 여백은 탭 줄이 있을 때만 16 이 아니라 6 이다 —
/// 탭의 누름 칸이 그 10 을 쓴다(`_Tabs`). 검색 중엔 탭 줄이 없어 pen 그대로 16.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.query, required this.searching, required this.onChanged});

  final String query;
  final bool searching;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ✕ 는 검색어를 지우고 고른 탭 화면으로 돌아간다(대장 09-29). 뒤로 가기는 지우지 않고 화면을 나간다.
  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, widget.searching ? AppSpacing.md : 6),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: '궁금한 내용을 검색해 보세요',
          hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          // 글자를 키우면 360 폭에서 한 줄에 다 안 들어가 말줄임이 된다 — 두 줄까지 두고 칸은 최소 높이라 따라 커진다.
          hintMaxLines: 2,
          filled: true,
          fillColor: AppColors.surfaceSoft,
          isDense: true,
          // 높이는 최소값만 건다 — 글자를 키우면 칸이 따라 커진다.
          constraints: const BoxConstraints(minHeight: 48),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          prefixIcon: const Padding(
            // pen 간격 8 = 이 여백 4 + Material 3 가 prefix 뒤에 저절로 붙이는 4(input_decorator `prefixToInputGap`).
            padding: EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
            // 칸 최소 높이 48 이 그림을 세로로 늘리지 않게 가운데 둔다.
            child: Center(widthFactor: 1, child: Icon3d(AppIcon3d.search, size: 24)),
          ),
          prefixIconConstraints: const BoxConstraints(minHeight: 48),
          suffixIcon: widget.query.isEmpty
              ? null
              // Material 3 는 suffix 를 상자 끝에 붙인다. pen 오른쪽 여백 16 = 누름 48 의 여유 14 + 이 2.
              : Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: IconButton(
                    onPressed: _clear,
                    tooltip: '검색어 지우기',
                    icon: const Icon(AppIcons.x, size: 20, color: AppColors.muted),
                  ),
                ),
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
  }

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.input),
    borderSide: BorderSide.none,
  );
}

/// 카테고리 탭 줄(pen `Sg89A` · 탭 `H2Qyx`). 보이는 줄은 38 이고 누름 칸만 48 이다(대장 09-29) —
/// 모자란 10 은 위(검색칸 아래 여백)로 늘려 보이는 모양은 pen 그대로다. 내용이 화면보다 넓어 가로로 민다(DESIGN §13-69).
class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onTap});

  final FaqCategory selected;
  final ValueChanged<FaqCategory> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hairline))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          spacing: AppSpacing.md,
          children: [
            for (final category in FaqCategory.values)
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onTap(category),
                  // 위 20 = 누름 칸 10 + pen padding-top 10. 라벨 칸 18 · 간격 8 · 밑줄 2 → 48.
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 20, AppSpacing.sm, AppSpacing.xs),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: category == selected ? AppColors.primaryText : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 18),
                      child: Text(
                        category.label,
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: category == selected ? FontWeight.w700 : FontWeight.w500,
                          color: category == selected ? AppColors.primaryText : AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 본문(pen `BqbHF`: padding [16,16,32,16], 묶음 사이 32). 머리글(`sI8Dm` 20/600)은 검색 중에만 — 탭 화면에선
/// 탭이 제목 몫이라 꺼져 있다(사용자 결정 ① 가).
class _FaqList extends StatelessWidget {
  const _FaqList({
    required this.sections,
    required this.showHeaders,
    required this.expandedId,
    required this.onTap,
    super.key,
  });

  final List<FaqSection> sections;
  final bool showHeaders;
  final String? expandedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const _NoResults();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xl),
          if (showHeaders) ...[
            Text(section.category.label, style: AppTypography.title.copyWith(color: AppColors.ink)),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (final item in section.items)
            _FaqRow(item: item, expanded: item.id == expandedId, onTap: () => onTap(item.id)),
        ],
      ],
    );
  }
}

/// 검색 0개(사용자 결정 ② 가 → pen 21-1 `U19HAx` · Empty `TVc8b` 인스턴스 `IhXOF`): 본문 좌우 16 + 여백 24, 가운데.
/// 마스코트 120 → 24 → 제목 → 8 → 설명 세 줄(메일 주소만 `o0LQI0` 14/600 primaryText, 누르면 메일 앱).
class _NoResults extends ConsumerStatefulWidget {
  const _NoResults();

  @override
  ConsumerState<_NoResults> createState() => _NoResultsState();
}

class _NoResultsState extends ConsumerState<_NoResults> {
  static const _mail = 'appmailerl4538@gmail.com';

  /// 메일 앱을 못 연 안내(pen 에 없음). 가입 동의 화면(`consent_screen.dart`)과 같은 문구 · 모양 · 3초(대장 09-29).
  String? _notice;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _openMail() async {
    bool opened;
    try {
      opened = await ref.read(openUrlProvider)(Uri.parse('mailto:$_mail'));
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = const UnknownFailure().toDisplayMessage());
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final description = AppTypography.bodySmall.copyWith(color: AppColors.muted);
    final notice = _notice;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                // 본문 칸 높이만큼 채워 가운데에 둔다. 글자를 키워 넘치면 스크롤한다.
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + AppSpacing.lg, vertical: AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/images/mascot-male.png', width: 120, height: 120),
                        // pen 간격 8 + 빈 사각형 8(`Wz22b`) + 간격 8.
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          '찾는 질문이 없어요',
                          textAlign: TextAlign.center,
                          // pen `ZBzIg` 17/600, 줄높이 속성 없음 · 렌더 25.
                          style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 25 / 17),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // pen `ksubx` 줄마다 14/400 lh1.55 muted(마스터 설명 `DFs55` 값).
                        Text('다른 말로 검색하거나', textAlign: TextAlign.center, style: description),
                        // pen `CvTKu` 가로 · 간격 4. 글자를 키워 폭이 모자라면 "으로" 가 다음 줄로 간다.
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.xxs,
                          children: [
                            // 모양은 pen 그대로, 누름 칸만 위아래로 늘려 48(대장 09-29 · 03 "메일 다시 받기" 와 같은 방식).
                            TextButton(
                              onPressed: _openMail,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: AppColors.primaryText,
                                textStyle: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                              ),
                              child: const Text(_mail, textAlign: TextAlign.center),
                            ),
                            Text('으로', style: description),
                          ],
                        ),
                        Text('물어봐 주세요', textAlign: TextAlign.center, style: description),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (notice != null) ...[
          AppToast(
            leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
            label: notice,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// 질문 줄(pen `KrMaM`, 펼침 `ElIjG`). 같은 줄 안에서 답이 펼쳐진다 — 화면 이동이 아니다(DESIGN §8.13).
/// 아래 선은 묶음 마지막 줄에도 그린다(pen `e0Ig9`).
class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.item, required this.expanded, required this.onTap});

  final FaqItem item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 잉크는 줄 크기의 투명 Material 에 그린다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hairlineSoft))),
          // 펼침 시간은 pen 에 없어 앱 공통 값.
          child: AnimatedSize(
            duration: AppMotion.standard,
            curve: AppMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: AppSpacing.sm,
                  children: [
                    Expanded(
                      child: Text(
                        item.question,
                        style: AppTypography.label.copyWith(color: expanded ? AppColors.primaryText : AppColors.ink),
                      ),
                    ),
                    Icon(expanded ? AppIcons.chevronUp : AppIcons.chevronDown, size: 20, color: AppColors.muted),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(item.answer, style: AppTypography.body.copyWith(color: AppColors.muted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
