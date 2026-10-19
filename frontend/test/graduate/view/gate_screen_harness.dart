import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../../auth/model/fake_verification_gate_repository.dart';
import '../model/fake_graduate_verification_repository.dart';

/// 졸업생 관문 화면 시험이 같이 쓰는 준비물. 화면은 pen 크기(360×780)로 띄우고 가짜 저장소 셋을 건다.
class GateHarness {
  final FakeGraduateVerificationRepository repository = FakeGraduateVerificationRepository();
  final FakeVerificationGateRepository gateRepository = FakeVerificationGateRepository();
  final FakeImageCompressor compressor = FakeImageCompressor();

  /// 화면에서 꺼낸 컨테이너 — 뷰모델 훅(갤러리 대체)을 걸 때 쓴다.
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    if (disableAnimations) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    container = ProviderContainer(overrides: [
      graduateVerificationRepositoryProvider.overrideWithValue(repository),
      verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      imageCompressorProvider.overrideWithValue(compressor),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
  }
}

/// 화면 안 글자 중 [text] 를 가진 것의 스타일.
TextStyle styleOf(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style!;
}
