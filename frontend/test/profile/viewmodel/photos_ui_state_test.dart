import 'dart:io';

import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SelectedPhoto` 두 모양 — 이번에 고른 사진(04-2 · 04-3 · 15-7) · 이미 올려 둔 사진(15-7, 계획서 2026-09-27-me-edit.md A6).
void main() {
  group('이번에 고른 사진', () {
    final file = File('picked/a.jpg');

    test('끌기 열쇠는 파일 경로, 그림은 파일에서 읽는다, 행 id · 주소는 없다', () {
      final photo = SelectedPhoto(file);

      expect(photo.key, 'picked/a.jpg');
      expect(photo.image, FileImage(file));
      expect((photo.id, photo.url), (null, null));
      expect(photo.isAvatarSource, isFalse);
    });

    test('원본 표시를 바꿔도 같은 파일이다', () {
      final photo = SelectedPhoto(file).copyWith(isAvatarSource: true);

      expect((photo.file, photo.id, photo.isAvatarSource), (file, null, true));
    });
  });

  group('이미 올려 둔 사진', () {
    const photo = SelectedPhoto.saved(id: 'p-a', url: 'https://img.test/a.png', isAvatarSource: true);

    test('끌기 열쇠는 행 id, 그림은 서명 주소에서 읽는다, 파일은 없다', () {
      expect(photo.key, 'p-a');
      expect(photo.image, const NetworkImage('https://img.test/a.png'));
      expect(photo.file, isNull);
      expect(photo.isAvatarSource, isTrue);
    });

    test('원본 표시를 바꿔도 같은 행 · 주소다', () {
      final changed = photo.copyWith(isAvatarSource: false);

      expect((changed.id, changed.url, changed.file, changed.isAvatarSource), ('p-a', 'https://img.test/a.png', null, false));
    });
  });
}
