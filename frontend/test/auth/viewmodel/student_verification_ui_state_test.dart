import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final realName = RealName.tryParse('홍길동')!;
  final photo = File('${Directory.systemTemp.path}/student_id.jpg');

  test('기본 상태는 상태 조회 중이고 아직 인증 전이다', () {
    const state = StudentVerificationUiState();

    expect(state.isLoadingStatus, isTrue);
    expect(state.status, 'none');
    expect(state.canSubmit, isFalse);
  });

  test('실명과 사진이 모두 있고 제출 중이 아니면 제출할 수 있다', () {
    final state = StudentVerificationUiState(realName: realName, selectedPhoto: photo);

    expect(state.canSubmit, isTrue);
  });

  test('실명이 없으면 제출할 수 없다', () {
    final state = StudentVerificationUiState(selectedPhoto: photo);

    expect(state.canSubmit, isFalse);
  });

  test('사진이 없으면 제출할 수 없다', () {
    final state = StudentVerificationUiState(realName: realName);

    expect(state.canSubmit, isFalse);
  });

  test('이미 제출 중이면 다시 제출할 수 없다', () {
    final state = StudentVerificationUiState(realName: realName, selectedPhoto: photo, isSubmitting: true);

    expect(state.canSubmit, isFalse);
  });
}
