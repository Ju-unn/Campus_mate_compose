import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 문구 파일 `lib/l10n/app_ko.arb` 의 보조 용언 띄어쓰기를 지킨다(사용자 결정 「맞춤법대로 맞춤」 2026-11-09).
/// "-아/어 주다 · 드리다" 는 띄운다: "골라주세요" → "골라 주세요", "알려드릴게요" → "알려 드릴게요".
/// 표준국어대사전에 한 낱말로 오른 말(도와주다 · 들려주다 · 가져다주다 …)과 명사 + 접미사 "-드리다"(감사드려요 …)만 붙인 채 둔다.
void main() {
  group('시험 도구', () {
    test('아/어 꼴 뒤에 붙은 주세요 · 주셔 · 주시 · 주신 · 드려 · 드릴 · 드렸을 잡는다', () {
      expect(attachedAuxiliaries('사진을 골라주세요.'), ['골라주세요']);
      expect(attachedAuxiliaries('직접 알려주셔야 해요'), ['알려주셔야']);
      expect(attachedAuxiliaries('답해주신 내용으로 써드릴게요.'), ['답해주신', '써드릴게요']);
      expect(attachedAuxiliaries('모두 소개해드렸어요.\n바로 알려드릴게요.'), ['소개해드렸어요', '알려드릴게요']);
      expect(attachedAuxiliaries('알림을 보내드려요'), ['보내드려요']);
    });

    test('띄운 말 · 사전 한 낱말 · 아/어 꼴이 아닌 말은 잡지 않는다', () {
      expect(attachedAuxiliaries('사진을 골라 주세요. 바로 알려 드릴게요.'), isEmpty);
      expect(attachedAuxiliaries('도와주세요 · 내주세요 · 돌려주세요 · 넘겨주세요 · 들어주세요 · 알아주세요'), isEmpty);
      expect(attachedAuxiliaries('봐주세요 · 보아주세요 · 가져다주세요 · 데려다주세요 · 도와드릴게요 · 내드려요'), isEmpty);
      expect(attachedAuxiliaries('건네주세요 · 확인해 주세요 · 입력해 주세요 · 주세요'), isEmpty);
    });

    test('사전 한 낱말은 낱말 전체로만 비켜 간다 — 보내주세요 · 물어봐주세요는 잡는다', () {
      expect(attachedAuxiliaries('보내주세요 · 물어봐주세요'), ['보내주세요', '물어봐주세요']);
    });

    test('들려주다 · 빌려주다 · 물려주다는 사전 한 낱말이라 잡지 않는다', () {
      expect(attachedAuxiliaries('나에 대해 들려주세요 · 책을 빌려주세요 · 물려주셔도 돼요'), isEmpty);
      expect(attachedAuxiliaries('사진을 골라주세요'), ['골라주세요']);
    });

    test('명사 + 접미사 "-드리다"(국립국어원: 붙여 쓴다)는 드려 · 드릴 · 드렸 꼴에서만 비켜 간다', () {
      expect(attachedAuxiliaries('매칭을 축하드려요 · 감사드려요 · 인사드릴게요 · 사과드렸어요 · 안내드려요 · 전화드릴게요'), isEmpty);
      expect(attachedAuxiliaries('부탁드려요 · 연락드릴게요'), isEmpty);
      expect(attachedAuxiliaries('나중에 전화주세요'), ['전화주세요']);
    });

    test('준 · 주는 · 줘 꼴도 잡는다 — 준비 · 기준 · 자주는 · 매주는 처럼 보조 용언이 아닌 말은 빼고', () {
      expect(attachedAuxiliaries('AI가 그려준 아바타 · 잘 보여주는 이야기 · 골라줘'), ['그려준', '보여주는', '골라줘']);
      expect(attachedAuxiliaries('준비해주세요'), ['준비해주세요']);
      expect(attachedAuxiliaries('준비 · 기준 · 수준 · 자주는 · 매주는 · 그려 준 · 넣어 줘 · 들려준 · 빌려주는 · 봐줘'), isEmpty);
    });
  });

  test('app_ko.arb 의 문구에 붙여 쓴 "-아/어 주다 · 드리다" 가 없다', () {
    final arb = jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync()) as Map<String, dynamic>;
    final found = <String, List<String>>{
      for (final entry in arb.entries)
        if (!entry.key.startsWith('@') && entry.value is String && attachedAuxiliaries(entry.value as String).isNotEmpty)
          entry.key: attachedAuxiliaries(entry.value as String),
    };

    expect(arb, isNotEmpty);
    expect(found, isEmpty,
        reason: '보조 용언은 띄운다(예: 골라 주세요 · 알려 드릴게요). 사전 한 낱말 · 명사+접미사 \'-드리다\' 는 예외 목록에 더한다: $found');
  });
}

/// 붙여 쓴 보조 용언 "주다 · 드리다" 가 든 낱말(공백 · 문장 부호로 끊은 한글 덩어리)을 나온 순서대로 준다.
/// 바로 앞 글자가 받침 없는 아/어 꼴(ㅏ ㅐ ㅓ ㅕ ㅘ ㅙ ㅝ — 해 · 라 · 려 · 어 · 와 …)일 때만 보조 용언으로 본다.
List<String> attachedAuxiliaries(String text) => [
      for (final word in RegExp('[가-힣]+').allMatches(text).map((m) => m.group(0)!))
        if (_isAttachedAuxiliary(word)) word,
    ];

final _auxiliary = RegExp('(주세요|주셔|주시|주신|주는|준|줘|드려|드릴|드렸)');

/// 표준국어대사전에 한 낱말로 오른 "…주다 · …드리다" 의 앞부분(낱말 전체가 이것이어야 비켜 간다).
const _dictionaryStems = {'도와', '내', '돌려', '넘겨', '들어', '알아', '봐', '보아', '들려', '빌려', '물려'};

/// 접미사 "-드리다" 가 붙는 명사(국립국어원: 감사드리다 · 부탁드리다 · 연락드리다는 붙여 쓴다). 드려 · 드릴 · 드렸 꼴에서만 비켜 간다.
const _nounsWithDeurida = {'감사', '축하', '인사', '사과', '안내', '전화', '부탁', '연락'};

/// "주" 가 앞말의 끝인 부사(자주 · 매주 · 아주) — "자주는" 의 "주는" 은 보조 용언이 아니다.
const _adverbHeads = {'자', '매', '아'};

bool _isAttachedAuxiliary(String word) => _auxiliary.allMatches(word).any((match) => _isAttachedAt(word, match));

bool _isAttachedAt(String word, RegExpMatch match) {
  if (match.start == 0) return false;
  final stem = word.substring(0, match.start);
  // 가져다주다 · 데려다주다 · 갖다주다 · 바래다주다 — "-다 주다" 꼴은 사전에 한 낱말로 올라 있다.
  if (_dictionaryStems.contains(stem) || _adverbHeads.contains(stem) || stem.endsWith('다')) return false;
  if (match.group(0)!.startsWith('드') && _nounsWithDeurida.contains(stem)) return false;
  final syllable = stem.codeUnitAt(stem.length - 1) - 0xAC00;
  const finalConsonants = 28;
  const ahEoVowels = {0, 1, 4, 6, 9, 10, 14}; // ㅏ ㅐ ㅓ ㅕ ㅘ ㅙ ㅝ
  return syllable % finalConsonants == 0 && ahEoVowels.contains(syllable ~/ finalConsonants % 21);
}
