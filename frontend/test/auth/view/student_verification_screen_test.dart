import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/auth/model/student_verification_repository_provider.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_face_detector.dart';
import '../model/fake_image_compressor.dart';
import '../model/fake_student_verification_repository.dart';

/// 미리보기 테스트용 1×1 투명 PNG. 디코드되는 진짜 파일이어야 `Image.file` 이 그려진다.
const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  late FakeStudentVerificationRepository repository;
  late FakeFaceDetector faceDetector;
  late File photo;

  setUpAll(() {
    photo = File('${Directory.systemTemp.path}/student_verification_screen_test.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64));
  });

  tearDownAll(() => photo.deleteSync());

  setUp(() {
    repository = FakeStudentVerificationRepository();
    faceDetector = FakeFaceDetector();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        studentVerificationRepositoryProvider.overrideWithValue(repository),
        faceDetectorProvider.overrideWithValue(faceDetector),
        imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = buildContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StudentVerificationScreen()),
      ),
    );
    return container;
  }

  /// 화면을 띄우고 상태 조회 응답까지 받아낸다.
  /// `pending` 이면 폴링 타이머가 계속 돌아 `pumpAndSettle` 이 끝나지 않으므로 프레임을 직접 센다.
  Future<ProviderContainer> pumpLoadedScreen(WidgetTester tester) async {
    final container = await pumpScreen(tester);
    await tester.pump(Duration.zero); // 상태 조회 응답이 도착한다
    await tester.pump(); // 도착한 상태로 다시 그린다
    return container;
  }

  ElevatedButton findCallToAction(WidgetTester tester) {
    return tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  }

  group('StudentVerificationScreen', () {
    testWidgets('상태를 불러오는 동안에는 스피너만 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('pen Rg1VT 카피를 보여준다', (tester) async {
      await pumpLoadedScreen(tester);

      expect(find.text('학생 인증'), findsOneWidget);
      expect(find.text('학교와 재학 상태를 확인해요'), findsOneWidget);
      expect(find.text('학생증'), findsOneWidget);
      expect(find.text('졸업증명서'), findsOneWidget);
      expect(find.text('실명 · 필수'), findsOneWidget);
      expect(find.text('사진을 첨부해주세요'), findsOneWidget);
      expect(find.text('학생증에 표기된 이름'), findsOneWidget); // 실명 입력칸 플레이스홀더 (pen Rg1VT)
      expect(find.text('인증 서류는 프로필에 공개되지 않아요.'), findsOneWidget);
      expect(find.text('확인 요청하기'), findsOneWidget);
    });

    testWidgets('졸업증명서 탭을 고르면 실명 힌트와 업로드 안내가 함께 바뀐다', (tester) async {
      await pumpLoadedScreen(tester);

      await tester.tap(find.text('졸업증명서'));
      await tester.pump();

      expect(find.text('졸업증명서에 표기된 이름'), findsOneWidget);
      expect(find.text('이름·학교·졸업 일자가 선명하게 보여야 해요'), findsOneWidget);
      expect(find.text('학생증에 표기된 이름'), findsNothing);
    });

    testWidgets('반려 배너가 떠도 고른 탭이 학생증으로 되돌아가지 않는다', (tester) async {
      // 배너가 붙으면 그 아래 위젯 자리가 한 칸씩 밀린다 —
      // 탭 상태를 폼 안에 두면 `State` 가 새로 만들어져 학생증으로 돌아간다(권고 7).
      final container = await pumpLoadedScreen(tester);
      container.read(studentVerificationViewModelProvider.notifier).pickFromGallery = () async => photo;
      repository.nextSubmitResult = const Success(
        VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'),
      );
      await tester.tap(find.text('졸업증명서'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.ensureVisible(find.text('사진을 첨부해주세요'));
      await tester.tap(find.text('사진을 첨부해주세요'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('확인 요청하기'));
      await tester.pumpAndSettle();

      expect(find.text('사유: 사진이 흐려요 · 다시 올리면 다시 확인해요'), findsOneWidget);
      expect(find.text('졸업증명서에 표기된 이름'), findsOneWidget);
    });

    testWidgets('거절이면 히어로 자리에 거절 배너를 보여준다', (tester) async {
      repository.nextFetchStatusResult = const Success(
        VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'),
      );

      await pumpLoadedScreen(tester);

      expect(find.text('인증이 거절됐어요'), findsOneWidget);
      expect(find.text('사유: 사진이 흐려요 · 다시 올리면 다시 확인해요'), findsOneWidget);
      // 마스코트·제목·부제 자리를 배너가 대신한다(pen `yrG1J`).
      expect(find.text('학교와 재학 상태를 확인해요'), findsNothing);
      // 배너 아래 폼은 원래 3b 그대로라 바로 다시 제출할 수 있다.
      expect(find.text('확인 요청하기'), findsOneWidget);
    });

    testWidgets('거절 사유가 없으면 안내만 보여준다', (tester) async {
      repository.nextFetchStatusResult = const Success(VerificationOutcome(status: 'rejected'));

      await pumpLoadedScreen(tester);

      expect(find.text('다시 올리면 다시 확인해요'), findsOneWidget);
      expect(find.textContaining('사유:'), findsNothing);
    });

    testWidgets('처음 제출하는 화면에는 배너가 없다', (tester) async {
      await pumpLoadedScreen(tester);

      expect(find.text('인증이 거절됐어요'), findsNothing);
      expect(find.text('학교와 재학 상태를 확인해요'), findsOneWidget);
    });

    testWidgets('실명과 사진이 모두 없으면 CTA 가 비활성이다', (tester) async {
      await pumpLoadedScreen(tester);

      expect(findCallToAction(tester).enabled, isFalse);
    });

    testWidgets('실명만 입력하고 사진이 없으면 CTA 가 여전히 비활성이다', (tester) async {
      await pumpLoadedScreen(tester);

      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.pump();

      expect(findCallToAction(tester).enabled, isFalse);
    });

    testWidgets('실명과 사진이 모두 있으면 미리보기가 뜨고 CTA 가 활성화된다', (tester) async {
      final container = await pumpLoadedScreen(tester);
      container.read(studentVerificationViewModelProvider.notifier).pickFromGallery = () async => photo;

      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.ensureVisible(find.text('사진을 첨부해주세요')); // 작은 화면에서는 업로드 존이 스크롤 밖이다
      await tester.tap(find.text('사진을 첨부해주세요'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((widget) => widget is Image && widget.image is FileImage), findsOneWidget);
      expect(findCallToAction(tester).enabled, isTrue);
    });

    testWidgets('제출이 실패하면 안내 문구와 함께 입력한 실명이 남은 폼으로 돌아온다', (tester) async {
      faceDetector.nextResult = false; // 기기 안 1차 필터에서 걸린다
      final container = await pumpLoadedScreen(tester);
      container.read(studentVerificationViewModelProvider.notifier).pickFromGallery = () async => photo;
      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.ensureVisible(find.text('사진을 첨부해주세요'));
      await tester.tap(find.text('사진을 첨부해주세요'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('확인 요청하기'));
      await tester.pumpAndSettle();

      expect(find.text('얼굴이 보이는 사진으로 다시 올려주세요'), findsOneWidget);
      expect(find.text('홍길동'), findsOneWidget);
      expect(findCallToAction(tester).enabled, isTrue); // 바로 다시 제출할 수 있다
    });

    testWidgets('pending 이면 재시도 버튼 없이 대기 화면만 보여준다', (tester) async {
      repository.nextFetchStatusResult = const Success(VerificationOutcome(status: 'pending'));

      await pumpLoadedScreen(tester);

      expect(find.text('조금 더 확인이 필요해요'), findsOneWidget);
      expect(find.text('담당자가 서류를 확인하고 있어요. 완료되면 알림으로 알려드릴게요.'), findsOneWidget);
      expect(find.text('나중에 확인하기'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('pending 이면 30초마다 상태를 다시 물어본다', (tester) async {
      repository.nextFetchStatusResult = const Success(VerificationOutcome(status: 'pending'));
      await pumpLoadedScreen(tester);
      repository.nextFetchStatusResult = const Success(
        VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'),
      );

      await tester.pump(const Duration(seconds: 30));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('사유: 사진이 흐려요 · 다시 올리면 다시 확인해요'), findsOneWidget);
    });

    testWidgets('pending 중 폴링이 한 번 실패해도 대기 화면이 유지된다', (tester) async {
      repository.nextFetchStatusResult = const Success(VerificationOutcome(status: 'pending'));
      await pumpLoadedScreen(tester);
      repository.nextFetchStatusResult = const FailureResult(NetworkFailure());

      await tester.pump(const Duration(seconds: 30));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('조금 더 확인이 필요해요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // 빈 제출 폼으로 떨어지지 않는다
    });

    testWidgets('반려되면 사유를 보여주고 폼으로 다시 제출할 수 있다', (tester) async {
      repository.nextFetchStatusResult = const Success(
        VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'),
      );

      await pumpLoadedScreen(tester);

      expect(find.text('사유: 사진이 흐려요 · 다시 올리면 다시 확인해요'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });
}
