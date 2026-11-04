import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 문구 파일 `lib/l10n/app_ko.arb` 의 모양을 지킨다(1.0.2 B8). 문구가 수백 개로 늘어도 정렬 · 중복 · 자리표시자가 어긋나지 않게,
/// 그리고 안 쓰는 키가 쌓이지 않게 한다. 생성 파일(`app_localizations*.dart`)이 아니라 ARB 와 `lib/` 소스를 직접 읽으므로
/// 생성 여부와 상관없이 돈다.
void main() {
  const arbPath = 'lib/l10n/app_ko.arb';

  /// 최상위 키를 (중복 포함) 나온 순서대로 뽑는다. `jsonDecode` 는 중복 키를 조용히 뒤엣것으로 덮어서 원문에서 센다.
  List<String> topLevelKeys(String arb) {
    final keys = <String>[];
    var depth = 0;
    var i = 0;
    while (i < arb.length) {
      final c = arb[i];
      if (c == '{' || c == '[') depth++;
      if (c == '}' || c == ']') depth--;
      if (c != '"') {
        i++;
        continue;
      }
      final start = ++i;
      while (arb[i] != '"') {
        i += arb[i] == r'\' ? 2 : 1;
      }
      final token = arb.substring(start, i++);
      var next = i;
      while (next < arb.length && arb[next].trim().isEmpty) {
        next++;
      }
      if (depth == 1 && next < arb.length && arb[next] == ':') keys.add(token);
    }
    return keys;
  }

  /// 본문 바깥 층의 `{이름}` · `{이름, select, …}` 에서 이름을 뽑는다. 선택지 안쪽 중괄호는 건너뛴다(중첩 자리표시자는 쓰지 않는다).
  Set<String> placeholderNames(String message) {
    final names = <String>{};
    var depth = 0;
    for (var i = 0; i < message.length; i++) {
      if (message[i] == '}') depth--;
      if (message[i] != '{') continue;
      if (depth++ == 0) names.add(RegExp(r'\{\s*(\w+)').firstMatch(message.substring(i))!.group(1)!);
    }
    return names;
  }

  group('시험 도구', () {
    test('최상위 키만 나온 순서대로 뽑고 중복도 그대로 남긴다', () {
      const arb = '{"@@locale":"ko","b":"x","@b":{"placeholders":{"n":{"type":"int"}}},"a":"y","b":"z"}';

      expect(topLevelKeys(arb), ['@@locale', 'b', '@b', 'a', 'b']);
    });

    test('자리표시자 이름은 select 선택지 안쪽 중괄호를 건너뛰고 같은 이름은 한 번만 센다', () {
      expect(placeholderNames('{a}와 {b}, {a}'), {'a', 'b'});
      expect(placeholderNames('이미 {p, select, kakao{카카오} other{소셜}}로 {n}'), {'p', 'n'});
      expect(placeholderNames('자리표시자 없음'), isEmpty);
    });
  });

  group('app_ko.arb', () {
    late String raw;
    late Map<String, dynamic> arb;

    setUpAll(() {
      raw = File(arbPath).readAsStringSync();
      arb = jsonDecode(raw) as Map<String, dynamic>;
    });

    List<String> messageKeys() => [
          for (final key in arb.keys)
            if (!key.startsWith('@')) key,
        ];

    test('JSON 으로 읽히고 @@locale 이 ko 이다', () {
      expect(arb['@@locale'], 'ko');
    });

    test('같은 키가 두 번 나오지 않는다', () {
      final keys = topLevelKeys(raw);
      final duplicates = {for (final key in keys) if (keys.where((other) => other == key).length > 1) key};

      expect(duplicates, isEmpty);
    });

    test('키는 소문자로 시작하는 영문 camelCase 이다', () {
      final bad = messageKeys().where((key) => !RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(key));

      expect(bad, isEmpty);
    });

    test('메시지 키는 ASCII 오름차순이고, @키 는 자기 메시지 바로 아래에 있다', () {
      final messages = messageKeys()..sort();
      final expected = [
        '@@locale',
        for (final key in messages) ...[key, if (arb.containsKey('@$key')) '@$key'],
      ];

      expect(topLevelKeys(raw), expected);
    });

    test('모든 @키 에는 짝이 되는 메시지가 있다', () {
      final orphans = arb.keys.where((key) => key.startsWith('@') && key != '@@locale' && !arb.containsKey(key.substring(1)));

      expect(orphans, isEmpty);
    });

    test('본문의 {자리표시자} 이름이 @키 placeholders 와 같고, 타입은 String 또는 int 이다', () {
      final problems = <String>[];
      for (final key in messageKeys()) {
        final meta = arb['@$key'] as Map<String, dynamic>?;
        final declared = ((meta?['placeholders'] as Map<String, dynamic>?) ?? {});
        final used = placeholderNames(arb[key] as String);
        if (used.difference(declared.keys.toSet()).isNotEmpty || declared.keys.toSet().difference(used).isNotEmpty) {
          problems.add('$key: 본문 $used ↔ 선언 ${declared.keys.toSet()}');
        }
        for (final entry in declared.entries) {
          final type = (entry.value as Map<String, dynamic>)['type'];
          if (type != 'String' && type != 'int') problems.add('$key.${entry.key}: 타입 $type');
        }
      }

      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('메시지 키는 하나도 빠짐없이 lib/ 코드 어딘가에서 쓰인다 — 안 쓰는 문구가 쌓이지 않게', () {
      final identifiers = <String>{};
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = file.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') || path.startsWith('lib/l10n/')) continue;
        final code = stripComments(file.readAsStringSync());
        identifiers.addAll(RegExp(r'[A-Za-z_]\w*').allMatches(code).map((match) => match.group(0)!));
      }

      final unused = messageKeys().where((key) => !identifiers.contains(key));

      expect(unused, isEmpty, reason: '쓰는 곳이 없는 문구 키 — 지우거나 쓰는 코드를 같이 넣는다');
    });
  });
}
