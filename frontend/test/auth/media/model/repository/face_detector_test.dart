import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/media/model/repository/face_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_face_detector.dart';

/// 폭 100 · 높이 40 인 단색 JPEG(Pillow 로 만듦, 회전 표시 없음).
const _jpeg100x40 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAoAGQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDcooorE2CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//Z';

/// ML Kit 플러그인이 돌려주는 얼굴 한 개(상자만 의미 있다 — 표식 · 윤곽은 비운다).
Map<String, Object?> _face(double left, double width) => {
      'rect': {'left': left, 'top': 0.0, 'right': left + width, 'bottom': 20.0},
      'landmarks': <String, Object?>{},
      'contours': <String, Object?>{},
    };

void main() {
  group('가짜 검출기', () {
    test('기본값은 얼굴을 찾았고 크기는 모르는 것으로 처리한다', () async {
      final detector = FakeFaceDetector();

      final scan = await detector.scan(File('dummy.jpg'));

      expect((scan.hasFace, scan.widthRatio), (true, null));
    });

    test('nextResult를 지정하면 그 값을 돌려준다', () async {
      final detector = FakeFaceDetector()..nextResult = false;

      final scan = await detector.scan(File('dummy.jpg'));

      expect(scan.hasFace, isFalse);
    });

    test('얼굴 크기는 줄 세운 값부터 쓰고 다 쓰면 nextWidthRatio 로 돌아간다', () async {
      final detector = FakeFaceDetector()
        ..nextWidthRatio = 0.5
        ..queuedWidthRatios.addAll([0.1, null]);

      final ratios = [for (var i = 0; i < 3; i++) (await detector.scan(File('dummy.jpg'))).widthRatio];

      expect(ratios, [0.1, null, 0.5]);
    });
  });

  // 플러그인 채널(`google_mlkit_face_detector`)을 가짜로 두고 진짜 [MlKitFaceDetector] 의 계산을 본다.
  group('MlKitFaceDetector', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('google_mlkit_face_detector');
    late Directory dir;
    late List<Map<String, Object?>> faces;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('face_detector_test');
      faces = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => call.method == 'vision#startFaceDetector' ? faces : null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });

    File jpeg() => File('${dir.path}/photo.jpg')..writeAsBytesSync(base64Decode(_jpeg100x40));

    test('얼굴이 여러 개면 가장 큰 얼굴의 폭 ÷ 사진 폭', () async {
      faces = [_face(0, 10), _face(40, 30), _face(80, 12)];

      final scan = await MlKitFaceDetector().scan(jpeg());

      expect(scan.hasFace, isTrue);
      expect(scan.widthRatio, closeTo(0.30, 1e-9));
      expect(scan.hasCompanion, isFalse, reason: '다른 얼굴(10 · 12)이 가장 큰 얼굴(30)의 절반보다 작다');
    });

    test('가장 큰 얼굴 폭의 절반 이상인 얼굴이 또 있으면 같이 나온 사람이 있다', () async {
      faces = [_face(0, 30), _face(50, 15)];

      final scan = await MlKitFaceDetector().scan(jpeg());

      expect(scan.hasCompanion, isTrue);
      expect(scan.widthRatio, closeTo(0.30, 1e-9));
    });

    test('사진 폭을 읽지 못해도 같이 나온 사람은 가린다(얼굴 상자끼리 견준다)', () async {
      faces = [_face(0, 30), _face(50, 20)];
      final broken = File('${dir.path}/broken.jpg')..writeAsStringSync('not an image');

      final scan = await MlKitFaceDetector().scan(broken);

      expect((scan.widthRatio, scan.hasCompanion), (null, true));
    });

    test('얼굴 폭이 정확히 기준(사진 폭의 15%)이면 아바타 원본으로 통과한다', () async {
      faces = [_face(10, 15)];

      final scan = await MlKitFaceDetector().scan(jpeg());

      expect(scan.widthRatio, 0.15);
      expect(scan.isTooSmallForAvatar, isFalse);
    });

    test('사진 폭을 읽지 못하면(깨진 파일) 크기 모름 — 통과로 둔다', () async {
      faces = [_face(0, 5)];
      final broken = File('${dir.path}/broken.jpg')..writeAsStringSync('not an image');

      final scan = await MlKitFaceDetector().scan(broken);

      expect((scan.hasFace, scan.widthRatio), (true, null));
      expect(scan.isTooSmallForAvatar, isFalse);
    });
  });
}
