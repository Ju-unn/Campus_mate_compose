import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// 움직이는 그림(Lottie) 파일 지킴 시험. 시험은 `frontend/` 에서 돈다.
const _lottieDirectory = 'assets/lottie';

/// 사용자가 정한 크기 예산(2026-11-03 대장 지시): json 하나 100KB, 장면 하나(json + 그림) 400KB.
const _jsonBudgetBytes = 100 * 1024;
const _sceneBudgetBytes = 400 * 1024;

Map<String, dynamic> _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _imageAssets(Map<String, dynamic> json) => [
      for (final asset in json['assets'] as List<dynamic>)
        if ((asset as Map<String, dynamic>)['p'] != null) asset,
    ];

/// lottie 패키지가 asset 으로 그림을 찾는 자리: **json 이 있는 폴더 / `u` / `p`**
/// (lottie 3.8.2 `AssetLottie._loadImage` — `p.url.join(p.dirname(assetName), dirName, fileName)`).
String _imagePath(String scenePath, Map<String, dynamic> asset) {
  final folder = scenePath.substring(0, scenePath.lastIndexOf('/'));
  final parts = [folder, asset['u'] as String, asset['p'] as String];
  return parts.where((part) => part.isNotEmpty).map((part) => part.replaceAll(RegExp(r'^/+|/+$'), '')).join('/');
}

/// pubspec `flutter: assets:` 의 항목(폴더는 `/` 로 끝난다 — 폴더 항목은 **하위 폴더까지 담지 않는다**).
Set<String> _declaredAssets() {
  final lines = File('pubspec.yaml').readAsStringSync();
  return RegExp(r'^\s+-\s+(assets/\S+)\s*$', multiLine: true).allMatches(lines).map((m) => m.group(1)!).toSet();
}

bool _isDeclared(String file, Set<String> declared) {
  final folder = file.substring(0, file.lastIndexOf('/') + 1);
  return declared.contains(file) || declared.contains(folder);
}

/// 윈도우 경로의 역슬래시를 슬래시로 맞춘다.
String _slashPath(String path) => path.replaceAll(r'\', '/');

String _fileBaseName(String path) => path.split('/').last.replaceAll('.json', '');

void main() {
  test('assets/lottie 폴더가 있다', () {
    expect(Directory(_lottieDirectory).existsSync(), isTrue, reason: '$_lottieDirectory 가 없다');
  });

  test('assets/lottie 의 json 은 모두 AppLottie 에 있고, AppLottie 의 경로는 모두 실제 파일이다', () {
    final files = Directory(_lottieDirectory)
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((path) => path.endsWith('.json'))
        .toSet();
    final table = AppLottie.values.map((scene) => scene.path).toSet();

    expect(table, hasLength(AppLottie.values.length), reason: '같은 경로가 두 장면에 있다');
    expect(files, table);
  });

  test('AppLottie 의 경로는 모두 pubspec assets 에 잡힌다', () {
    final declared = _declaredAssets();

    for (final scene in AppLottie.values) {
      expect(_isDeclared(scene.path, declared), isTrue, reason: '${scene.path} 가 pubspec assets 에 없다');
    }
  });

  // 그림 경로(json 폴더 / u / p)가 실제 번들에서 맞는지 — 패키지가 그림을 못 찾으면 경고만 남기고 그 층이 안 그려진다.
  testWidgets('실제 장면은 번들에서 읽으면 그림이 하나도 빠짐 없이 로드된다', (tester) async {
    await tester.runAsync(() async {
      for (final scene in AppLottie.values) {
        final composition = await AssetLottie(scene.path).load();

        // "이미지가 N 개" 는 패키지의 성능 권고일 뿐이다 — 그림을 못 읽은 경고만 막는다.
        expect(composition.warnings.where((w) => w.startsWith('Failed to load image')), isEmpty, reason: scene.path);
        for (final image in composition.images.values) {
          expect(image.loadedImage, isNotNull, reason: '${scene.path} ${image.dirName}${image.fileName}');
        }
        expect(composition.getMarker('loop'), isNotNull, reason: scene.path);
      }
    });
  });

  test('assets/lottie/images/<이름>/ 에는 json 이 참조하는 그림만 있다(안 쓰는 파일이 앱에 실리지 않는다)', () {
    final root = Directory('$_lottieDirectory/images');
    final folders = {
      for (final folder in root.listSync().whereType<Directory>()) _slashPath(folder.path).split('/').where((part) => part.isNotEmpty).last: folder,
    };
    final sceneNames = AppLottie.values.map((scene) => _fileBaseName(scene.path)).toSet();

    expect(folders.keys.toSet().difference(sceneNames), isEmpty, reason: '장면이 없는 그림 폴더');
    for (final scene in AppLottie.values) {
      final name = _fileBaseName(scene.path);
      final referenced = {for (final asset in _imageAssets(_readJson(scene.path))) _imagePath(scene.path, asset)};
      final files = {
        for (final file in folders[name]?.listSync().whereType<File>() ?? <File>[]) _slashPath(file.path),
      };
      expect(files, referenced, reason: '$name 폴더의 파일과 json 이 참조하는 그림이 같아야 한다');
    }
  });

  group('장면마다', () {
    for (final scene in AppLottie.values) {
      final name = _fileBaseName(scene.path);

      test('$name — 그림 참조는 images/$name/ 이고 실제 파일이며 pubspec 에 잡힌다', () {
        final declared = _declaredAssets();

        for (final asset in _imageAssets(_readJson(scene.path))) {
          expect(asset['u'], 'images/$name/', reason: '$name 의 그림 폴더는 images/$name/ 이다');
          final path = _imagePath(scene.path, asset);
          expect(File(path).existsSync(), isTrue, reason: '$name 이 참조하는 $path 가 없다');
          expect(_isDeclared(path, declared), isTrue, reason: '$path 가 pubspec assets 에 없다(폴더 항목은 하위 폴더를 담지 않는다)');
        }
      });

      test('$name — json 은 100KB 이하, json + 그림은 400KB 이하', () {
        final json = File(scene.path).lengthSync();
        final images = {
          for (final asset in _imageAssets(_readJson(scene.path))) _imagePath(scene.path, asset),
        }.fold<int>(0, (sum, path) => sum + File(path).lengthSync());

        expect(json, lessThanOrEqualTo(_jsonBudgetBytes), reason: '$name json $json 바이트');
        expect(json + images, lessThanOrEqualTo(_sceneBudgetBytes), reason: '$name 합계 ${json + images} 바이트');
      });

      test('$name — 반복 구간(loop) 표시가 있고, 멈춤 프레임이 장면 안에 있다', () {
        final json = _readJson(scene.path);
        final markers = [for (final marker in json['markers'] as List<dynamic>) (marker as Map<String, dynamic>)['cm']];

        expect(markers, contains('loop'));
        expect(scene.stillFrame, greaterThanOrEqualTo(json['ip'] as num));
        expect(scene.stillFrame, lessThan(json['op'] as num));
      });
    }
  });
}
