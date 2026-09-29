import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/viewmodel/my_photos_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_face_detector.dart';
import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_me_repository.dart';

/// 서버 사진 행 — [source] 번째가 아바타 원본. 이름·학교는 지어낸 값이다.
MyProfile _profile({List<String> ids = const ['p-a', 'p-b', 'p-c'], int source = 0}) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: null,
      heightCm: null,
      mbti: null,
      avatarUrl: null,
      preferredAgeMin: null,
      preferredAgeMax: null,
      preferredHeightMin: null,
      preferredHeightMax: null,
      bio: null,
      photos: [
        for (final (index, id) in ids.indexed)
          MyPhoto(id: id, url: 'https://img.test/$id.png', isAvatarSource: index == source),
      ],
    );

void main() {
  late FakeMeRepository me;
  late FakeFaceDetector faceDetector;
  late ProviderContainer container;
  late ProviderSubscription<PhotosUiState> subscription;

  MyPhotosViewModel viewModel() => container.read(myPhotosViewModelProvider.notifier);
  PhotosUiState state() => subscription.read();

  /// [profile] 로 내 프로필을 읽은 뒤 15e 를 연다 — 15e 는 15-5 를 거쳐 열려 내 프로필이 이미 읽혀 있다.
  Future<void> open(MyProfile profile) async {
    me = FakeMeRepository(Success(profile));
    faceDetector = FakeFaceDetector();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
        faceDetectorProvider.overrideWithValue(faceDetector),
      ],
    );
    addTearDown(container.dispose);
    await container.read(myProfileProvider.future);
    subscription = container.listen(myPhotosViewModelProvider, (_, _) {});
  }

  /// 딱 한 번 보낸 칸 순서 · 원본 번호. 레코드 안의 List 는 == 가 같은 객체인지만 봐서 따로 비교한다.
  void expectSaved(List<PhotoSlot> slots, int avatarSource) {
    final (sentSlots, sentSource) = me.photoSaves.single;
    expect(sentSlots, slots);
    expect(sentSource, avatarSource);
  }

  /// 갤러리에서 [file] 한 장을 고른다(얼굴 검사는 통과).
  Future<void> addPhoto(File file) async {
    viewModel().pickFromGallery = (limit) async => [file];
    await viewModel().addPhoto();
  }

  test('열면 서버 사진이 자리 순서대로 칸에 들어가고 원본 표시도 그대로다', () async {
    await open(_profile(source: 1));

    expect([for (final photo in state().photos) photo.key], ['p-a', 'p-b', 'p-c']);
    expect([for (final photo in state().photos) photo.url], [
      'https://img.test/p-a.png',
      'https://img.test/p-b.png',
      'https://img.test/p-c.png',
    ]);
    expect([for (final photo in state().photos) photo.isAvatarSource], [false, true, false]);
    expect(viewModel().canSave, isTrue);
  });

  test('하나 빼고 하나 더해 저장하면 [남길 사진, 새 사진] · 원본 0 을 보낸다', () async {
    await open(_profile(ids: ['p-a', 'p-b']));
    viewModel().removePhoto(1);
    await addPhoto(File('new.jpg'));

    await viewModel().save();

    expectSaved([const KeptPhoto('p-a'), NewPhoto(File('new.jpg'))], 0);
  });

  test('아바타 원본 사진을 빼면 대표(첫 칸)가 원본이 된다(U3)', () async {
    await open(_profile(source: 1));
    viewModel().removePhoto(1);

    await viewModel().save();

    expectSaved(const [KeptPhoto('p-a'), KeptPhoto('p-c')], 0);
  });

  test('원본 사진을 둘째 칸으로 끌면 원본 번호는 1 이다', () async {
    await open(_profile(ids: ['p-a', 'p-b']));
    viewModel().swapPhotos(0, 1);

    await viewModel().save();

    expectSaved(const [KeptPhoto('p-b'), KeptPhoto('p-a')], 1);
  });

  test('2장 미만이면 저장하지 못한다', () async {
    await open(_profile(ids: ['p-a', 'p-b']));
    viewModel().removePhoto(0);

    await viewModel().save();

    expect(viewModel().canSave, isFalse);
    expect(me.photoSaves, isEmpty);
  });

  test('고른 사진을 살펴보는 동안은 저장하지 못한다 — 늦게 끝난 검사가 보낸 목록에서 빠진다', () async {
    await open(_profile(ids: ['p-a', 'p-b']));
    final gate = Completer<bool>();
    faceDetector.gate = gate;
    viewModel().pickFromGallery = (limit) async => [File('new.jpg')];
    final adding = viewModel().addPhoto();
    await Future<void>.delayed(Duration.zero);

    expect(state().isCheckingPhotos, isTrue);
    expect(viewModel().canSave, isFalse);
    await viewModel().save();
    expect(me.photoSaves, isEmpty);

    gate.complete(true);
    await adding;
    expect(viewModel().canSave, isTrue);
  });

  test('저장하는 동안은 isSubmitting 이고 다시 눌러도 한 번만 보낸다', () async {
    await open(_profile());
    me.holdSavePhotos = Completer<void>();

    final saving = viewModel().save();

    expect(state().isSubmitting, isTrue);
    expect(viewModel().canSave, isFalse);
    await viewModel().save();
    expect(me.photoSaves, hasLength(1));
    me.holdSavePhotos!.complete();
    await saving;
    expect(state().isSubmitting, isFalse);
  });

  test('저장이 끝나면 completed 이고 내 프로필(15-5)을 다시 읽는다', () async {
    await open(_profile());

    await viewModel().save();
    await container.read(myProfileProvider.future);

    expect(state().completed, isTrue);
    expect(me.calls, 2, reason: '저장 뒤 invalidate 로 GET /me/profile 을 한 번 더 부른다');
  });

  test('409 "사진이 바뀌었어요…" 면 그 문구를 보이고 칸은 그대로 — 다시 열면 새 값이 오도록 내 프로필은 다시 읽는다', () async {
    await open(_profile());
    viewModel().removePhoto(2);
    me.savePhotosResult = const FailureResult(ServerRejectedFailure('사진이 바뀌었어요, 다시 열어 주세요'));

    await viewModel().save();
    await container.read(myProfileProvider.future);

    expect(state().errorMessage, '사진이 바뀌었어요, 다시 열어 주세요');
    expect(state().completed, isFalse);
    expect(state().isSubmitting, isFalse);
    expect([for (final photo in state().photos) photo.key], ['p-a', 'p-b']);
    // 계획서 2-2 — 실패해도 서버가 일부를 바꿨을 수 있다(⑤~⑦). 15-5 와 다음 15e 가 지금 서버 값을 보게 한다.
    expect(me.calls, 2);
  });

  test('저장 중에 화면을 떠나도(autoDispose) 끝난 저장이 오류를 내지 않고 15-5 는 다시 읽힌다', () async {
    await open(_profile());
    me.holdSavePhotos = Completer<void>();
    final saving = viewModel().save();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    me.holdSavePhotos!.complete();
    await saving;
    await container.read(myProfileProvider.future);

    expect(me.photoSaves, hasLength(1));
    expect(me.calls, 2);
  });

  test('my_photos_is_filled_from_the_server_each_time_it_opens — 고치다 만 칸은 닫으면 사라진다(Review Focus 5)', () async {
    await open(_profile());
    viewModel().removePhoto(0);
    viewModel().swapPhotos(0, 1);

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    subscription = container.listen(myPhotosViewModelProvider, (_, _) {});

    expect([for (final photo in state().photos) photo.key], ['p-a', 'p-b', 'p-c']);
  });

  test('저장한 뒤 다시 열면 저장된 서버 값으로 채워진다', () async {
    await open(_profile());
    viewModel().removePhoto(2);
    await viewModel().save();
    me.profile = Success(_profile(ids: ['p-a', 'p-b']));
    await container.read(myProfileProvider.future);

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    subscription = container.listen(myPhotosViewModelProvider, (_, _) {});

    expect([for (final photo in state().photos) photo.key], ['p-a', 'p-b']);
  });
}
