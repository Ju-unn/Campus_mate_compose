import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

// 문구는 사용자 확정(10-17 "ok 문구 좋다") 그대로다. 글자 하나도 바꾸지 않는다.
// 문장마다 굵게 할 구절을 **문장에 나오는 순서대로** 적는다(사용자 지시 10-17, pen 은 rich text 를 못 담아 대장이 목록으로 전달).
const String _title = '대화를 시작하기 전에 알아 두세요';
const (String, List<String>) _summary = (
  "48시간 안에 두 분이 모두 수락해야 카카오톡 아이디·실사진이 공개되고 대화가 이어져요. "
      "위쪽의 '수락하기'를 누르면 먼저 공개할 수 있어요.",
  ['48시간', '수락'],
);
const List<(String, List<String>)> _items = [
  (
    "지금부터 48시간이 '신뢰 확인' 시간이에요. 서로 카카오톡 아이디와 실제 사진을 공개해도 좋은지 정하는 시간이에요.",
    ['48시간', '카카오톡 아이디'],
  ),
  (
    "매칭 약 24시간 뒤, 아직 수락하지 않은 분께 알림이 가요. 알림을 누르거나 이 대화방에 들어오면 "
        "'카카오톡 아이디를 공유할까요?' 창이 떠요. 거기서 '수락하고 공유하기' 또는 '거절하고 나가기'를 고르면 돼요.",
    ['24시간', '카카오톡 아이디'],
  ),
  (
    "기다리기 싫다면 지금 화면 위쪽의 '수락하기'를 눌러 보세요. 상대도 수락하면 바로 공개돼요. 수락은 취소할 수 없어요.",
    ['수락하기', '수락은 취소할 수 없어요'],
  ),
  ('48시간 안에 두 분이 모두 수락하지 않으면 이 대화는 종료돼요. 한쪽이 나가도 끝나요.', ['48시간', '종료']),
  (
    '공개된 뒤의 만남과 연락은 두 분의 선택이에요. 만나기 전에는 꼭 상대를 직접 확인하고 안전에 유의해 주세요. '
        '불편하면 신고·차단·나가기를 쓸 수 있어요.',
    [],
  ),
];

// pen 제목 14/700 ink 1.5 — 14/700 토큰이 없어 bodySmall(14)에서 굵기 · 줄높이만 pen 값으로 바꾼다.
final TextStyle _titleStyle = AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.5);
// pen 요약 · 항목 본문 14/normal body 1.55 = bodySmall 그대로.
final TextStyle _bodyStyle = AppTypography.bodySmall.copyWith(color: AppColors.body);
// pen 번호 14/700 ink. 줄높이는 pen 값이 없어 본문(1.55)과 같게 둬 첫 줄이 나란하다.
final TextStyle _numberStyle = AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink);
// 본문 속 굵은 구절은 굵기만 700 — 색 · 크기 · 줄높이는 본문을 그대로 물려받는다.
const TextStyle _emphasisStyle = TextStyle(fontWeight: FontWeight.w700);

/// [sentence] 에서 [phrases] 구절만 굵게 한 한 문단. 구절은 앞 구절 뒤에서부터 처음 나오는 곳을 찾는다.
/// 조각에 누를 동작이 없어 화면 읽기에는 문장 전체가 한 덩어리로 읽힌다.
Text _emphasized((String, List<String>) line) {
  final (sentence, phrases) = line;
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final phrase in phrases) {
    final start = sentence.indexOf(phrase, cursor);
    assert(start >= 0, '굵게 할 구절 "$phrase" 이 문장에 (앞 구절 뒤로) 없다');
    spans.addAll([TextSpan(text: sentence.substring(cursor, start)), TextSpan(text: phrase, style: _emphasisStyle)]);
    cursor = start + phrase.length;
  }
  spans.add(TextSpan(text: sentence.substring(cursor)));
  return Text.rich(TextSpan(children: spans), style: _bodyStyle);
}

/// 매칭 직후 첫 입장 안내 카드(pen 마스터 `cinKv` 접힘 · `TfPlG` 펼침 · 항목 `B3PzPm`).
/// 대화방 목록 맨 위에 메시지와 함께 스크롤된다. 접힘 상태는 부르는 쪽(채팅방 화면)이 들고 있다 —
/// 목록 칸은 화면 밖으로 나가면 버려지므로 여기 두면 다시 접힌다.
class ChatIntroCard extends StatelessWidget {
  const ChatIntroCard({required this.expanded, required this.onToggle, super.key});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // 카드 전체가 읽기용 묶음 하나다. 토글 버튼은 자기 노드라 따로 읽힌다.
    return Semantics(
      container: true,
      child: DecoratedBox(
        // pen 그림자 없음 · surface-strong(시스템 줄과 같은 회색) · 모서리 14.
        decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Padding(
          // pen [16,16,4,16] — 아래가 4 인 것은 토글 줄(48)이 제 안에 여백을 갖고 있어서다.
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xs,
            children: [
              // pen Title Row(z83bi · cinKv 같은 값): 파란 안내 3D 아이콘 20 → 6 → 제목(폭 296 − 26 = 270), 세로 가운데.
              // 아이콘은 장식이라 Icon3d 가 낭독에서 뺀다 — 제목만 읽힌다.
              Row(
                spacing: 6, // pen 가로 gap 6 — 간격 토큰(4 · 8) 사이 값
                children: [
                  const Icon3d(AppIcon3d.infoBlue, size: 20),
                  Expanded(child: Text(_title, style: _titleStyle)),
                ],
              ),
              _Resize(child: expanded ? const _Items() : _emphasized(_summary)),
              // pen 토글 줄 296×48: 오른쪽 정렬 · 세로 가운데.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _Toggle(expanded: expanded, onPressed: onToggle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 요약 ↔ 항목이 바뀔 때 높이만 {motion.standard} 로 옮긴다(자주 안 쓰는 동작, 상태 변화).
/// 카드가 보이는 방은 목록을 위로 붙이므로(대장 결정 B) 짧은 방에서는 **제목이 제자리**다 — 위를 기준으로 맞춰
/// 글자가 제자리에서 아래로 드러난다. 화면을 채운 긴 방에서는 토글이 제자리이고 본문이 위로 늘어난다(스크롤 위치는 그대로).
class _Resize extends StatelessWidget {
  const _Resize({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 동작 줄이기면 AnimatedSize 를 아예 두지 않는다 — 시간 0 인 AnimatedSize 는 제 레이아웃 중에
    // 다시 레이아웃을 걸어 오류가 난다(heart_balance_chip 과 같은 이유).
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedSize(
      duration: AppMotion.standard,
      curve: AppMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// 펼친 본문(pen `ChatIntroItem` `B3PzPm` × 5): 번호 칸 20 · 가로 6 · 본문, 항목 사이 8.
class _Items extends StatelessWidget {
  const _Items();

  @override
  Widget build(BuildContext context) {
    // 번호 칸 20 은 배율 1 의 값이다 — 글자를 키우면 칸도 같이 키워 "5." 가 두 줄로 쪼개지지 않게 한다.
    final numberWidth = MediaQuery.textScalerOf(context).scale(20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        for (var index = 0; index < _items.length; index++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6, // pen 가로 gap 6 — 간격 토큰(4 · 8) 사이 값
            children: [
              SizedBox(width: numberWidth, child: Text('${index + 1}.', style: _numberStyle)),
              Expanded(child: _emphasized(_items[index])),
            ],
          ),
      ],
    );
  }
}

/// 토글(pen 버튼 85×48 + 그 오른쪽에 붙은 chevron 16): "자세히 보기" + chevron-down / "접기" + chevron-up,
/// 14/600 primary-text. pen 버튼 안쪽은 [위아래 0, 오른쪽 4, 왼쪽 12] 이고 chevron 은 버튼 밖인데,
/// **앱은 chevron 도 같이 눌리게 버튼 안에 넣는다(대장 지시 10-17)** — 그래서 글자 → chevron 4 는 pen 버튼 오른쪽 안쪽 4 다.
/// 화면 읽기에는 버튼 + 펼침 상태로 읽힌다. TextButton 은 자기 Material 에 잉크를 그려 목록과 같이 움직인다(COMMON §4-2).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // 높이는 최소값만 건다 — 글자를 키우면 줄이 따라 커진다.
        minimumSize: const Size(48, 48),
        padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.primaryText,
      ),
      // 버튼 노드 안에 합쳐져 "자세히 보기, 버튼, 접힘" 처럼 읽힌다.
      child: Semantics(
        expanded: expanded,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xxs,
          children: [
            Text(expanded ? '접기' : '자세히 보기', style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
            Icon(expanded ? AppIcons.chevronUp : AppIcons.chevronDown, size: 16, color: AppColors.primaryText),
          ],
        ),
      ),
    );
  }
}
