import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_literals.dart';

/// 에러 자리는 글자가 아니라 **종류**를 담는다(1.0.2 B8, 설계 §5 ②-c). 뷰모델 · UiState 에 이름이 error · failure · rejection 인
/// `String` 칸이 생기면 뷰모델이 에러 문구를 글자로 만들어 상태에 싣는다는 뜻이다 — 문구가 ARB(`error*` 키) 밖에서 정해지고,
/// 언어가 늘면 상태에 낡은 글자가 남는다. 그래서 그런 칸은 `Failure?` · `AppError?` 만 허락하고, 글자는 view 가
/// `context.errorText(failure)` 로 바꾼다. view 위젯의 글자 인자(`LabeledField.errorText` · `AppToast.label` 등)는 대상이 아니다.
void main() {
  // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더). 생성 폴더 `lib/l10n/` 은 읽지 않는다.
  final slotFiles = {
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart')) file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  }..removeWhere((path, source) => path.startsWith('lib/l10n/') || !isErrorSlotFile(path, source));

  group('stringErrorSlots(표본)', () {
    test('이름에 error · failure · rejection 이 든 String / String? 필드 · getter · 매개변수를 잡는다', () {
      const source = '''
class AUiState {
  const AUiState({this.errorMessage, String? heightRejection});
  final String? errorMessage;
  final String submitFailure = '';
  String get loadError => '';
  String? get LastRejection => null;
}
''';

      expect(stringErrorSlots(source), ['heightRejection', 'errorMessage', 'submitFailure', 'loadError', 'LastRejection']);
    });

    test('Failure? · AppError? · 컬렉션 · 메서드 · 다른 이름의 String 은 통과한다', () {
      const source = '''
// final String? errorMessage;
class BUiState {
  final Failure? error;
  final AppError? kind;
  final Set<String> _nicknameRejections = {};
  final Map<String, Failure?> failures = {};
  final String message;
  String errorLine() => '';
  void retry(String code) {}
}
''';

      expect(stringErrorSlots(source), isEmpty);
    });
  });

  test('검사할 파일이 있다 — 뷰모델 폴더 · UiState 파일을 실제로 읽는다', () {
    expect(slotFiles.keys.where((path) => path.contains('/viewmodel/')), isNotEmpty);
  });

  test('뷰모델 · UiState 의 에러 자리(이름에 error · failure · rejection)는 String 이 아니라 Failure? · AppError? 다', () {
    final offenders = [
      for (final MapEntry(key: path, value: source) in slotFiles.entries)
        for (final name in stringErrorSlots(source)) '$path: $name',
    ];

    expect(
      offenders,
      isEmpty,
      reason: '에러는 종류(Failure? · AppError?)로 상태에 담고 화면이 context.errorText(...) 로 글자로 바꾼다:\n${offenders.join('\n')}',
    );
  });
}

/// 뷰모델 폴더의 파일이거나 `…UiState` 클래스를 선언한 파일.
bool isErrorSlotFile(String path, String source) =>
    path.contains('/viewmodel/') || RegExp(r'\bclass\s+\w*UiState\b').hasMatch(source);

/// `String` · `String?` 로 선언한 필드 · getter · 매개변수 중 이름에 error · failure · rejection(대소문자 무관)이 든 것의 이름.
/// 주석은 빼고 읽는다. `Set<String>` 처럼 타입 인자인 String 과 이름 뒤에 `(` 가 오는 메서드는 아니다.
List<String> stringErrorSlots(String source) => [
      for (final match in _stringDeclaration.allMatches(stripComments(source)))
        if (_errorName.hasMatch(match.group(1)!)) match.group(1)!,
    ];

final RegExp _stringDeclaration = RegExp(r'(?<![\w$<.])String\??\s+(?:get\s+)?([A-Za-z_$][\w$]*)(?![\w$])(?!\s*[(<])');
final RegExp _errorName = RegExp('error|failure|rejection', caseSensitive: false);
