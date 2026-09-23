import 'dart:io';

import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사진 두 장이 이미 담긴 상태에서 시작한다(갤러리·압축은 ViewModel 테스트가 본다).
class _TwoPhotosViewModel extends PhotosViewModel {
  @override
  PhotosUiState build() => PhotosUiState(photos: [SelectedPhoto(File('a.jpg')), SelectedPhoto(File('b.jpg'))]);
}

void main() {
  testWidgets('아바타 뱃지 배경은 사진 위에 그려진다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photosViewModelProvider.overrideWith(_TwoPhotosViewModel.new)],
        child: const MaterialApp(home: PhotosScreen()),
      ),
    );

    // Ink 는 가장 가까운 Material 에 칠해진다. 그 Material 이 타일(Positioned) 밖의 Scaffold 면
    // 뱃지 배경이 사진 뒤에 깔려 글자만 떠 보인다(2026-09-23 실기기 테스트).
    final nearestMaterial = find
        .ancestor(of: find.text('아바타로 선택').first, matching: find.byType(Material))
        .first;
    expect(find.ancestor(of: nearestMaterial, matching: find.byType(Positioned)), findsOneWidget);
  });
}
