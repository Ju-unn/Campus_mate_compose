import 'dart:io';

import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱 그림 지킴 시험. 시험은 `frontend/` 에서 돈다.
const _imageDirectory = 'assets/images';

/// 그림 하나의 크기 상한(2026-11-11 사용자 승인 — 앱 내려받기 용량 줄이기). 1024px 원본을 그대로 넣으면 이 값을 넘는다.
const _imageBudgetBytes = 300 * 1024;

/// lib 소스 속 `assets/images/…` 경로 전부(따옴표 · 공백 · 괄호 · 백틱 앞까지). 확장자가 없는 조립 경로도 잡는다.
final _imagePath = RegExp(r'assets/images/[^\x27\x22\s)`]+');

/// 동물상 그림은 `animal-face-$name-2d-v1.webp` 또는 `animal-face-${name}-2d-v1.webp` 로 조립한다(`AnimalType.iconAsset`) —
/// 열거 값마다 펼쳐 확인한다. 이 두 꼴이 아닌 조립(`${type.name}` · `$other` 등)은 펼치지 못해 시험이 실패한다.
final _animalName = RegExp(r'\$name|\$\{name\}');

List<File> _dartFiles() => Directory('lib').listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).toList();

Set<String> _pathsWrittenInLib() => {
      for (final file in _dartFiles())
        for (final match in _imagePath.allMatches(file.readAsStringSync())) match.group(0)!,
    };

Set<String> _expanded(Set<String> written) => {
      for (final path in written)
        if (path.startsWith('assets/images/animal-face-') && _animalName.hasMatch(path))
          for (final type in AnimalType.values) path.replaceAll(_animalName, type.name)
        else
          path,
    };

void main() {
  test('lib 이 부르는 assets/images 그림은 모두 실제 파일이다', () {
    final paths = _expanded(_pathsWrittenInLib());

    expect(paths, isNotEmpty, reason: 'lib 에서 그림 경로를 하나도 못 찾았다 — 정규식이 깨졌다');
    final missing = paths.where((path) => !File(path).existsSync()).toList()..sort();
    expect(missing, isEmpty, reason: '없는 그림 경로: $missing');
    final unexpanded = paths.where((path) => path.contains(r'$')).toList();
    expect(unexpanded, isEmpty, reason: '펼치지 못한 조립 경로: $unexpanded');
  });

  test('동물상 아이콘 경로(AnimalType.iconAsset)는 모두 실제 파일이다', () {
    for (final type in AnimalType.values) {
      expect(File(type.iconAsset).existsSync(), isTrue, reason: '${type.iconAsset} 가 없다');
    }
  });

  test('assets/images 그림은 하나도 300KB 를 넘지 않는다', () {
    final tooBig = [
      for (final file in Directory(_imageDirectory).listSync(recursive: true).whereType<File>())
        if (file.lengthSync() > _imageBudgetBytes) '${file.path.replaceAll(r'\', '/')} (${(file.lengthSync() / 1024).round()}KB)',
    ]..sort();

    expect(tooBig, isEmpty, reason: '300KB 를 넘는 그림: $tooBig');
  });
}
