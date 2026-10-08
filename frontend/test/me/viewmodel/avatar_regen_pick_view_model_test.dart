import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/viewmodel/avatar_regen_pick_view_model.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../../profile/model/fake_avatar_repository.dart';
import '../model/fake_me_repository.dart';

/// 이름 · 학교는 지어낸 값이다.
MyProfile _profile({List<MyPhoto>? photos}) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: '경영학과',
      heightCm: 178,
      mbti: 'ENFP',
      avatarUrl: 'https://img.test/avatar.png',
      photos: photos ??
          const [
            MyPhoto(id: 'p-0', url: 'https://img.test/0.png', isAvatarSource: true),
            MyPhoto(id: 'p-1', url: 'https://img.test/1.png', isAvatarSource: false),
          ],
      preferredAgeMin: 22,
      preferredAgeMax: 27,
      preferredHeightMin: 165,
      preferredHeightMax: 180,
      bio: '',
    );

void main() {
  late FakeMeRepository me;
  late FakeAvatarRepository avatars;
  late ProviderContainer container;
  final photo = File('picked.jpg');

  /// 사진을 이미 고른 상태의 뷰모델. 화면 없이 뷰모델만 본다.
  Future<AvatarRegenPickViewModel> prepare(WidgetTester tester, {MyProfile? profile}) async {
    me = FakeMeRepository(Success(profile ?? _profile()));
    avatars = FakeAvatarRepository();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        avatarRepositoryProvider.overrideWithValue(avatars),
        faceDetectorProvider.overrideWithValue(FakeFaceDetector()),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
      ],
    );
    addTearDown(container.dispose);
    final keep = container.listen(avatarRegenPickViewModelProvider, (_, _) {});
    addTearDown(keep.close);
    final viewModel = container.read(avatarRegenPickViewModelProvider.notifier)..pickFromGallery = () async => photo;
    await viewModel.pick();
    // 위젯 하나 없이도 시간을 흘릴 수 있게 빈 화면을 한 번 그려 둔다.
    await tester.pumpWidget(const SizedBox());
    return viewModel;
  }

  setUp(() => openMyProfileScreens = 1); // 평소엔 화면 15 가 아래에 열려 있다
  tearDown(() => openMyProfileScreens = 0);

  group('원본 칸 교체', () {
    testWidgets('지금 아바타 원본 칸(둘째)만 새 파일로 바뀌고 장수 · 나머지는 그대로, 원본 번호도 그 칸이다', (tester) async {
      final profile = _profile(photos: const [
        MyPhoto(id: 'p-0', url: 'a', isAvatarSource: false),
        MyPhoto(id: 'p-1', url: 'b', isAvatarSource: true),
        MyPhoto(id: 'p-2', url: 'c', isAvatarSource: false),
        MyPhoto(id: 'p-3', url: 'd', isAvatarSource: false),
      ]);
      final viewModel = await prepare(tester, profile: profile);
      avatars.statusResults.add(const Success(AvatarFailed()));

      await viewModel.submit();

      final (slots, source) = me.photoSaves.single;
      expect(slots.length, 4); // 4장이 차 있어도 장수가 그대로라 문제없다
      expect(source, 1);
      expect(slots[0], const KeptPhoto('p-0'));
      expect(slots[1], isA<NewPhoto>());
      expect(slots[2], const KeptPhoto('p-2'));
      expect(slots[3], const KeptPhoto('p-3'));
    });

    testWidgets('원본으로 표시된 칸이 없으면 대표(첫 칸)를 바꾼다', (tester) async {
      final viewModel = await prepare(
        tester,
        profile: _profile(photos: const [
          MyPhoto(id: 'p-0', url: 'a', isAvatarSource: false),
          MyPhoto(id: 'p-1', url: 'b', isAvatarSource: false),
        ]),
      );
      avatars.statusResults.add(const Success(AvatarFailed()));

      await viewModel.submit();

      expect(me.photoSaves.single.$2, 0);
    });

    testWidgets('실제 사진이 없는 프로필이면 아무것도 올리지 않고 알 수 없는 오류 문구', (tester) async {
      final viewModel = await prepare(tester, profile: _profile(photos: const []));

      await viewModel.submit();

      expect(me.photoSaves, isEmpty);
      expect(avatars.regenerateCount, 0);
      expect(container.read(avatarRegenPickViewModelProvider).errorMessage, isNotNull);
    });
  });

  group('등록 응답을 기다리는 사이 화면 15 가 닫혔을 때(옛 15 의 폴링 안전장치)', () {
    testWidgets('15 가 모두 닫혔으면 뒤늦게 시작된 폴링을 끊는다 — 상태를 더 묻지 않는다', (tester) async {
      final viewModel = await prepare(tester);
      avatars.generateGate = Completer<void>();
      final done = viewModel.submit();
      await tester.pump(const Duration(milliseconds: 100));
      openMyProfileScreens = 0; // 응답을 기다리는 사이 15 가 닫혔다

      avatars.generateGate!.complete();
      await done;
      final asked = avatars.statusCount;
      await tester.pump(const Duration(seconds: 12));

      expect(avatars.statusCount, asked);
    });

    testWidgets('15 가 열려 있으면 그 화면이 폴링을 쥐고 있으니 그대로 둔다', (tester) async {
      final viewModel = await prepare(tester);

      await viewModel.submit();
      final asked = avatars.statusCount;
      await tester.pump(const Duration(seconds: 12));

      expect(avatars.statusCount, greaterThan(asked));
      container.read(avatarGenerationViewModelProvider.notifier).stopPolling(); // 시험이 끝나기 전에 타이머를 치운다
    });
  });

  group('올리는 도중에 나가도', () {
    testWidgets('뷰모델이 끝까지 간다 — 화면을 떠나도 사진 교체와 등록이 마무리된다(autoDispose 가 버리지 않음)', (tester) async {
      final viewModel = await prepare(tester);
      avatars.statusResults.add(const Success(AvatarFailed()));
      me.holdSavePhotos = Completer<void>();
      final done = viewModel.submit();
      await tester.pump(const Duration(milliseconds: 50));

      container.read(avatarRegenPickViewModelProvider); // 듣는 쪽이 사라져도
      me.holdSavePhotos!.complete();
      await done;

      expect(avatars.regenerateCount, 1);
    });
  });
}
