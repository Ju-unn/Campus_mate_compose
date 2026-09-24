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
    this.realNameError,
    this.rejectReason,
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

  /// 서버가 준 반려 사유. 반려 배너만 쓰는 값이라 [errorMessage] 와 자리를 나눈다 —
  /// 한 칸을 같이 쓰면 반려된 뒤 조회·제출이 한 번 실패하는 순간 사유가 그 오류 문구로 덮인다.
  final String? rejectReason;

  /// 실명 입력이 글자 규칙에 어긋날 때 입력칸 아래에 보여줄 안내.
  /// [errorMessage] 와 자리를 나눈 이유는, 반려 사유 배너가 같은 칸을 쓰기 때문이다 —
  /// 한 칸을 같이 쓰면 반려된 사용자가 이름을 고치는 순간 반려 사유가 안내 문구로 덮인다.
  final String? realNameError;

  bool get canSubmit => realName != null && selectedPhoto != null && !isSubmitting;
}
