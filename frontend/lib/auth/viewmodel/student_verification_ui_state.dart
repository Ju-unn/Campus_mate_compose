import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';

/// 학생증 인증 화면(DESIGN.md 화면 3b)의 상태.
class StudentVerificationUiState {
  const StudentVerificationUiState({
    this.realNameInput = '',
    this.realName,
    this.selectedPhoto,
    this.isSubmitting = false,
    this.isLoadingStatus = true,
    this.status = 'none',
    this.errorMessage,
  });

  /// 입력창에 그대로 보여줄 원본 문자열.
  final String realNameInput;

  /// 형식이 올바를 때만 값이 있다. `null` 이면 CTA 를 누를 수 없다.
  final RealName? realName;

  /// 갤러리에서 고른 학생증 사진. 압축 전 원본이다.
  final File? selectedPhoto;

  /// 제출이 서버 응답을 기다리는 중인지.
  final bool isSubmitting;

  /// 화면을 열자마자 도는 상태 조회가 끝나지 않았는지.
  final bool isLoadingStatus;

  /// 'none' | 'pending' | 'rejected' — 'verified' 면 라우터가 이미 3c 로 보낸다.
  final String status;

  /// 조회·제출이 실패했거나 얼굴을 찾지 못했을 때 보여줄 문구.
  final String? errorMessage;

  bool get canSubmit => realName != null && selectedPhoto != null && !isSubmitting;
}
