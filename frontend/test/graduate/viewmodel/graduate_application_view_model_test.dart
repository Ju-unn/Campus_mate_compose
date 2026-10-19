import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_ui_state.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../../auth/model/fake_verification_gate_repository.dart';
import '../model/fake_graduate_verification_repository.dart';

void main() {
  late FakeGraduateVerificationRepository repository;
  late FakeVerificationGateRepository gateRepository;
  late FakeImageCompressor compressor;
  late ProviderContainer container;
  final picked = File('picked.jpg');

  /// 갤러리 도우미(image_picker)가 앱 캐시에 만든 사본을 지우라고 받은 경로 — 졸업증명서는 민감해 원본 사본을 남기지 않는다.
  late List<String> deleted;
  ProviderSubscription<GraduateApplicationUiState>? subscription;

  setUp(() {
    deleted = [];
    subscription = null;
    repository = FakeGraduateVerificationRepository();
    gateRepository = FakeVerificationGateRepository();
    compressor = FakeImageCompressor()..nextResult = File('compressed.jpg');
    container = ProviderContainer(overrides: [
      graduateVerificationRepositoryProvider.overrideWithValue(repository),
      verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      imageCompressorProvider.overrideWithValue(compressor),
    ]);
    addTearDown(container.dispose);
  });

  /// autoDispose 라 듣는 쪽이 있어야 살아 있다. 갤러리는 늘 [picked] 를 고른 것으로 한다.
  Future<GraduateApplicationViewModel> viewModel() async {
    subscription = container.listen(graduateApplicationViewModelProvider, (_, _) {});
    final model = container.read(graduateApplicationViewModelProvider.notifier)
      ..pickFromGallery = (() async => picked)
      ..deleteCopy = ((file) async => deleted.add(file.path));
    await pumpEventQueue();
    return model;
  }

  GraduateApplicationUiState state() => container.read(graduateApplicationViewModelProvider);

  /// 사진 · 동의를 채워 보낼 수 있는 상태로 만든다.
  Future<GraduateApplicationViewModel> readyToSubmit() async {
    final model = await viewModel();
    await model.pickPhoto();
    model.changeAgreed(true);
    return model;
  }

  // pen `oaPh3`(사진 칸의 삭제 X) — 고른 사진만 비우고 나머지 입력은 지킨다. 보내는 중에는 비우지 않는다.
  group('사진 빼기', () {
    test('사진만 비우고 이메일 · 동의는 그대로다', () async {
      final model = await readyToSubmit();
      model.changePreviousEmail('old@univ.ac.kr');

      model.removePhoto();

      expect(state().photo, isNull);
      expect(state().previousEmailInput, 'old@univ.ac.kr');
      expect(state().agreed, isTrue);
      expect(state().canSubmit, isFalse);
    });

    test('보내는 중에는 사진을 빼지 못한다', () async {
      final model = await readyToSubmit();
      repository.holdSubmit = Completer<void>();
      final submitting = model.submit();
      await pumpEventQueue();

      model.removePhoto();

      expect(state().photo!.path, 'compressed.jpg');
      repository.holdSubmit!.complete();
      await submitting;
    });
  });

  // 졸업증명서 사본 정리(독립 검토 사소1, 대장 10-19): 고르는 즉시 압축하고 image_picker 가 만든 원본 사본은 바로 지운다.
  // 압축본은 올린 뒤 · 빼거나 바꿀 때 · 화면을 떠날 때 지운다(로그아웃 · 탈퇴 때는 기존 discardAll 이 이름으로 쓸어 간다).
  group('사진 사본 정리', () {
    test('고르면 바로 압축하고 갤러리 도우미가 만든 원본 사본을 지운다 — 상태에는 압축본이 든다', () async {
      final model = await viewModel();

      await model.pickPhoto();

      expect(compressor.compressedSources, [picked]);
      expect(deleted, ['picked.jpg']);
      expect(state().photo!.path, 'compressed.jpg');
    });

    test('압축이 원본을 그대로 돌려주면(압축기 폴백) 원본은 아직 지우지 않는다 — 쓰는 사진이다', () async {
      compressor.nextResult = null;
      final model = await viewModel();

      await model.pickPhoto();

      expect(deleted, isEmpty);
      expect(state().photo!.path, 'picked.jpg');
    });

    test('압축이 사진을 못 읽으면 사진을 두지 않고 안내하며 원본 사본은 지운다', () async {
      compressor.nextError = Exception('읽을 수 없는 사진');
      final model = await viewModel();

      await model.pickPhoto();

      expect(state().photo, isNull);
      expect(state().errorMessage, graduatePhotoUnreadableMessage);
      expect(deleted, ['picked.jpg']);
    });

    test('사진을 빼면 압축본을 지운다', () async {
      final model = await viewModel();
      await model.pickPhoto();
      deleted.clear();

      model.removePhoto();
      await pumpEventQueue();

      expect(compressor.discardedPaths, ['compressed.jpg']);
      expect(deleted, ['compressed.jpg']);
    });

    test('다른 사진으로 바꾸면 앞 압축본을 지운다', () async {
      final model = await viewModel();
      await model.pickPhoto();
      compressor.nextResult = File('second.jpg');
      deleted.clear();

      await model.pickPhoto();
      await pumpEventQueue();

      expect(state().photo!.path, 'second.jpg');
      expect(compressor.discardedPaths, ['compressed.jpg']);
      expect(deleted, ['picked.jpg', 'compressed.jpg']);
    });

    test('올리기에 성공하면 압축본을 지우고 상태에서 사진을 비운다', () async {
      final model = await readyToSubmit();
      deleted.clear();

      await model.submit();
      await pumpEventQueue();

      expect(compressor.discardedPaths, ['compressed.jpg']);
      expect(deleted, ['compressed.jpg']);
      expect(state().photo, isNull);
    });

    test('올리기가 실패하면 압축본을 그대로 둔다 — 다시 눌러 같은 사진을 올린다', () async {
      repository.submitResult = const FailureResult(NetworkFailure());
      final model = await readyToSubmit();
      deleted.clear();

      await model.submit();
      await pumpEventQueue();

      expect(compressor.discardedPaths, isEmpty);
      expect(deleted, isEmpty);
      expect(state().photo!.path, 'compressed.jpg');
      repository.submitResult = const Success(GraduatePending(attemptsLeft: 1));
      await model.submit();
      expect(repository.submitted.map((entry) => entry.$1), ['compressed.jpg', 'compressed.jpg']);
    });

    test('화면을 떠나면(취소 · 뒤로가기) 압축본을 지운다', () async {
      final model = await viewModel();
      await model.pickPhoto();
      deleted.clear();

      subscription!.close();
      await pumpEventQueue();

      expect(compressor.discardedPaths, ['compressed.jpg']);
      expect(deleted, ['compressed.jpg']);
    });

    test('고르는 사이(압축 중) 화면을 떠나도 압축본 · 원본 사본이 남지 않는다', () async {
      final model = await viewModel();
      final started = Completer<void>();
      final release = Completer<File?>();
      model.pickFromGallery = () async {
        started.complete();
        return release.future;
      };
      final picking = model.pickPhoto();
      await started.future;

      subscription!.close();
      await pumpEventQueue();
      release.complete(picked);
      await picking;
      await pumpEventQueue();

      expect(deleted, contains('picked.jpg'));
    });
  });

  group('보낼 수 있는 조건', () {
    test('사진도 동의도 없으면 보낼 수 없다', () async {
      final model = await viewModel();

      expect(state().canSubmit, isFalse);
      await model.pickPhoto();
      expect(state().canSubmit, isFalse, reason: '동의 안 함');
      model.changeAgreed(true);
      expect(state().canSubmit, isTrue);
    });

    test('동의만 있고 사진이 없으면 보낼 수 없다', () async {
      final model = await viewModel();

      model.changeAgreed(true);

      expect(state().canSubmit, isFalse);
    });

    test('동의를 다시 끄면 보낼 수 없다', () async {
      final model = await readyToSubmit();

      model.changeAgreed(false);

      expect(state().canSubmit, isFalse);
    });

    test('이전 학교 메일은 비어 있어도 되고, 적었다면 형식이 맞아야 한다', () async {
      final model = await readyToSubmit();

      expect(state().canSubmit, isTrue, reason: '비어 있음');
      model.changePreviousEmail('a@');
      expect(state().canSubmit, isFalse, reason: '형식 틀림');
      expect(state().isPreviousEmailInvalid, isTrue);
      model.changePreviousEmail('old@univ.ac.kr');
      expect(state().canSubmit, isTrue);
      expect(state().isPreviousEmailInvalid, isFalse);
      model.changePreviousEmail('   ');
      expect(state().canSubmit, isTrue, reason: '공백만 = 비어 있음');
    });

    test('사진을 고르지 않고 닫으면 아무것도 바뀌지 않는다', () async {
      final model = (await viewModel())..pickFromGallery = () async => null;

      await model.pickPhoto();

      expect(state().photo, isNull);
    });
  });

  group('보내기', () {
    test('압축한 사진과 메일을 올리고, 압축본은 성공해도 지운다', () async {
      final model = await readyToSubmit();
      model.changePreviousEmail('Old@Univ.ac.kr');

      await model.submit();

      expect(compressor.compressedSources, [picked]);
      expect(repository.submitted, [('compressed.jpg', 'old@univ.ac.kr')]);
      expect(compressor.discardedPaths, ['compressed.jpg']);
    });

    test('성공하면 관문을 한 번 다시 묻는다 — 화면 이동은 관문이 한다', () async {
      final model = await readyToSubmit();

      await model.submit();

      expect(gateRepository.fetchCount, 1);
      expect(state().errorMessage, isNull);
      expect(state().isSubmitting, isFalse);
    });

    test('이메일을 비워 두면 메일 없이 올린다', () async {
      final model = await readyToSubmit();

      await model.submit();

      expect(repository.submitted.single.$2, isNull);
    });

    test('올리기가 실패하면 안내하고 관문은 건드리지 않는다', () async {
      repository.submitResult = const FailureResult(NetworkFailure());
      final model = await readyToSubmit();

      await model.submit();

      expect(state().errorMessage, '네트워크 연결을 확인해 주세요');
      expect(gateRepository.fetchCount, 0);
    });

    test('실패하면 고른 사진 · 동의 · 메일은 그대로라 다시 누를 수 있다', () async {
      repository.submitResult = const FailureResult(NetworkFailure());
      final model = await readyToSubmit();
      model.changePreviousEmail('old@univ.ac.kr');

      await model.submit();

      expect(state().photo!.path, 'compressed.jpg');
      expect(state().agreed, isTrue);
      expect(state().previousEmailInput, 'old@univ.ac.kr');
      expect(state().canSubmit, isTrue);
    });

    test('조건이 안 되면 보내지 않는다', () async {
      final model = await viewModel();

      await model.submit();

      expect(compressor.compressedSources, isEmpty);
      expect(repository.submitted, isEmpty);
    });

    test('보내는 중에 연타해도 한 번만 올라간다', () async {
      repository.holdSubmit = Completer<void>();
      final model = await readyToSubmit();

      final first = model.submit();
      await pumpEventQueue();
      expect(state().isSubmitting, isTrue);
      expect(state().canSubmit, isFalse);
      final second = model.submit();
      repository.holdSubmit!.complete();
      await Future.wait([first, second]);

      expect(repository.submitted, hasLength(1));
    });

    test('다른 기기가 먼저 냈다면(409 already_pending) 문구를 보이고 관문을 다시 묻는다', () async {
      repository.submitResult = const FailureResult(
        ServerRejectedFailure('이미 심사 중이에요, 결과를 기다려 주세요', code: 'already_pending'),
      );
      final model = await readyToSubmit();

      await model.submit();

      expect(state().errorMessage, '이미 심사 중이에요, 결과를 기다려 주세요');
      expect(gateRepository.fetchCount, 1);
    });

    test('그 밖의 거절(400 동의 필요 등)에는 관문을 건드리지 않는다', () async {
      repository.submitResult = const FailureResult(
        ServerRejectedFailure('개인정보 수집에 동의해 주세요', code: 'consent_required'),
      );
      final model = await readyToSubmit();

      await model.submit();

      expect(state().errorMessage, '개인정보 수집에 동의해 주세요');
      expect(gateRepository.fetchCount, 0);
    });
  });

  group('횟수를 다 쓴 경우(문의 안내 상태)', () {
    test('보내기가 429 면 신청 불가 상태로 바뀐다', () async {
      repository.submitResult = const FailureResult(RateLimitedFailure('신청 횟수를 모두 썼어요, 문의해 주세요'));
      final model = await readyToSubmit();

      await model.submit();

      expect(state().isExhausted, isTrue);
      expect(state().canSubmit, isFalse);
      expect(state().errorMessage, isNull, reason: '문의 안내가 대신 보인다');
    });

    test('반려 뒤 남은 횟수가 0 이면 처음부터 문의 안내 상태다', () async {
      repository.stateResult = const Success(GraduateRejected(reason: GraduateRejectReason.unverifiable, attemptsLeft: 0));

      await viewModel();

      expect(state().isExhausted, isTrue);
      expect(state().canSubmit, isFalse);
    });

    test('문의 안내 상태에서는 사진을 골라도 보낼 수 없다', () async {
      repository.stateResult = const Success(GraduateRejected(reason: null, attemptsLeft: 0));
      final model = await viewModel();

      await model.pickPhoto();
      model.changeAgreed(true);

      expect(state().canSubmit, isFalse);
    });
  });

  group('반려 뒤 다시 신청하는 폼', () {
    test('서버 반려 사유와 남은 횟수를 읽어 둔다', () async {
      repository.stateResult = const Success(GraduateRejected(reason: GraduateRejectReason.unreadable, attemptsLeft: 2));

      await viewModel();

      expect(state().rejection?.reason, GraduateRejectReason.unreadable);
      expect(state().rejection?.attemptsLeft, 2);
      expect(state().isExhausted, isFalse);
      expect(repository.fetchStateCount, 1);
    });

    test('처음 신청하는 폼에는 반려 정보가 없다', () async {
      repository.stateResult = const Success(null);

      await viewModel();

      expect(state().rejection, isNull);
      expect(state().isExhausted, isFalse);
    });

    test('읽기가 실패해도 폼은 쓸 수 있다 — 서버가 횟수를 막아 준다', () async {
      repository.stateResult = const FailureResult(NetworkFailure());
      final model = await readyToSubmit();

      expect(state().rejection, isNull);
      expect(state().canSubmit, isTrue);
      await model.submit();
      expect(repository.submitted, hasLength(1));
    });

    test('반려 정보를 읽는 사이 사용자가 적은 값은 읽기가 끝나도 덮이지 않는다', () async {
      repository.stateResult = const Success(GraduateRejected(reason: GraduateRejectReason.unreadable, attemptsLeft: 2));
      repository.holdFetchState = Completer<void>();
      container.listen(graduateApplicationViewModelProvider, (_, _) {});
      final model = container.read(graduateApplicationViewModelProvider.notifier)
        ..pickFromGallery = (() async => picked)
        ..deleteCopy = ((file) async => deleted.add(file.path));
      await model.pickPhoto();
      model.changeAgreed(true);
      model.changePreviousEmail('old@univ.ac.kr');

      repository.holdFetchState!.complete();
      await pumpEventQueue();

      expect(state().rejection?.reason, GraduateRejectReason.unreadable);
      expect(state().previousEmailInput, 'old@univ.ac.kr');
      expect(state().photo!.path, 'compressed.jpg');
      expect(state().agreed, isTrue);
    });
  });
}
