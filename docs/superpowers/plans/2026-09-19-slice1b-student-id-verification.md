# 조각 1b — 학생증 사진 인증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이메일 인증(조각 1a)을 마친 사용자가 학생증(또는 학생카드) 사진과 실명을 제출하면, 서버가 Google Cloud Vision OCR로 학교명 + 실명을 자동 대조해 통과시키거나, 애매하면 사람이 Supabase 대시보드에서 재검토하는 흐름을 완성한다. 통과 전까지는 다음 단계(학과·학번 확인 3c)로 넘어가지 못하게 라우터에서 강제한다.

**Architecture:** 1a와 동일한 원칙 — 클라이언트는 Supabase Auth 세션(`accessToken`)만 들고 있고, 실제 판정·쓰기는 전부 FastAPI(Cloud Run)가 `service_role`로 한다. Flutter는 사진을 고르고(client 압축·JPEG 재인코딩·얼굴 존재 여부만 기기 안에서 확인) `multipart/form-data`로 FastAPI에 올린다. FastAPI가 Supabase Storage에 업로드하고, Vision API로 OCR을 돌려 학교명 + 실명이 텍스트에 둘 다 보이면 즉시 `verified`, 아니면 `pending`으로 남기고 디스코드 웹훅으로 담당자에게 알린다. 사람이 Supabase 대시보드에서 `profiles.student_verification`을 직접 `verified`/`rejected`로 바꾸는 경우를 포함해 **모든 확정 경로를 Postgres 트리거 하나로 통일**한다 — `profiles.student_verification`이 `pending`에서 `verified`/`rejected`로 바뀌는 순간 트리거가 그 프로필의 최신 시도 기록(`file_path`)을 찾아 `storage.objects`에서 직접 지운다. FastAPI가 자동 통과시킨 경우도 결국 같은 UPDATE 문을 쓰므로 별도 삭제 코드가 필요 없다(2026-09-19 설계, 이 계획에서 결정).

**Tech Stack:** Flutter/Riverpod(기존 스택), FastAPI + httpx(기존 스택, PostgREST·Storage REST 직접 호출 — `supabase-py` SDK 도입하지 않음, 1a와 동일 패턴), `google-cloud-vision`(신규, 서버), `google_mlkit_face_detection` · `flutter_image_compress` · `http`(신규, 클라이언트)

**Spec:** `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` §7.3·§7.4, `docs/ERD.md` §3·§9·§12-4, `frontend/docs/DESIGN.md` §9 화면 `3b`·`3c`

## Global Constraints

스펙·CLAUDE.md·GIT.md·SUPABASE.md 에서 그대로 가져온 전역 요구사항 (1a와 동일 + 이번 조각 추가분).

- **Flutter**: 코드·네이밍 영어, 주석·문서 한국어 / `else` 금지 — early return 또는 `switch` 표현식 / 메서드 본문 10줄 이하 / Model 계층 인스턴스 변수 2개 이하(UiState 예외) / getter 노출 금지, 필드는 `_private` / 원시값은 값 객체로 포장 / 축약 금지 / 모든 비-private 클래스는 테스트를 가짐 / 색상·간격은 `core/theme/` 토큰만 참조 / ViewModel은 Flutter 위젯 타입을 참조하지 않는다
- **새 의존성 추가는 사전 사용자 확인** — 아래 4개를 새로 추가한다. **Task A1·B1 실행 전에 반드시 사용자 승인을 받는다.**
  - Flutter: `google_mlkit_face_detection`(온디바이스 얼굴 검출, 설계 §7.3 명시 요구), `flutter_image_compress`(업로드 전 압축·JPEG 재인코딩, 설계 §7.4), `http`(FastAPI 로 보내는 멀티파트 업로드 — 현재 `pubspec.lock`에 간접 의존성으로만 존재, 직접 의존성으로 승격)
  - 백엔드: `google-cloud-vision`(OCR, 2026-09-19 사용자 결정)
- **Git**: `docs/GIT.md` 따름 — gitmoji 커밋, `<타입>/<주제>` 작업 브랜치 → 푸시 → draft PR, merge는 사용자. **커밋·PR에 도구 표식을 넣지 않는다**
- **Supabase 클라우드 쓰기**(마이그레이션 적용, Storage/Secret Manager 설정 등)는 **매번 사용자가 직접 승인한 뒤에만** 한다 — Part C는 전부 이 승인 게이트 뒤에 있다
- **키 취급**: 프로젝트 URL·anon 키·`service_role` 키·Vision 인증·디스코드 웹훅 URL은 문서·코드·커밋에 쓰지 않는다. 디스코드 웹훅 URL은 Secret Manager(`discord-webhook-url`)에 둔다(1a `DEPLOY.md` 패턴과 동일)
- 이 계획은 **조각 1b만** 다룬다. 온보딩 04 이후 화면(조각 2), 어뷰징 방지(동일 기기·전화번호 차단, 조각 7), 전용 관리자 페이지는 범위 밖이다

---

## 범위 밖 (이 조각에서 하지 않는 것)

- **전용 관리자 페이지** — 재검토는 Supabase 대시보드에서 사람이 직접 한다(2026-09-19 결정). 필요해지면 추후 별도 조각
- **재시도 상한** — 이번 결정으로 상한을 두지 않는다(설계 §13 미결3 중 상한 부분은 "없음"으로 해소, 고객 지원 경로는 계속 미결)
- **학과·학번 검증 수단** — 3c는 자기 입력값을 그대로 저장한다. 학생증과 대조하지 않는다(§13 미결66, 그대로 열어둠)
- **정기 재인증** — 1a에서 이미 결정, 1b도 그대로 따른다(졸업 여부 안 따짐)
- **BottomNav·"Bottom Bar CTA" 공용 위젯으로의 전면 교체** — 최종검토Fable1이 전한 pen 갱신 내용(하단 내비 단일화, 새 `BottomCtaBar` 마스터)은 3b·3c CTA 버튼 배치에 반영하되(Task A11·A12), 1a에서 이미 만든 `SignUpScreen`·`VerifyCodeScreen`을 이 패턴으로 리팩터링하는 건 범위 밖이다 — 화면을 만질 다음 기회에 같이 한다. **주의: pencil MCP가 이 세션에서 연결 실패해 `.pen`을 직접 읽지 못했다.** 아래 3b·3c 레이아웃은 `frontend/docs/DESIGN.md` §9 텍스트 스펙 + 최종검토Fable1이 전한 치수(흰 배경·상단 stroke `#DDDDDD` 1px·padding 16/24/28/24)를 따른 것이라, **실제 구현 전에 pencil MCP 재연결 후 `datingApp.pen`으로 한 번 더 대조한다(Task A11 Step 0)**

---

## File Structure

### Part A — Flutter

| 파일 | 책임 |
| --- | --- |
| `frontend/pubspec.yaml` (수정) | `google_mlkit_face_detection`·`flutter_image_compress`·`http` 추가 |
| `frontend/lib/common/failure.dart` (수정) | `NoFaceDetectedFailure`·`ServerRejectedFailure` 추가 |
| `frontend/lib/auth/model/real_name.dart` | 실명 값 객체 |
| `frontend/lib/auth/model/department.dart` | 학과 값 객체 |
| `frontend/lib/auth/model/student_number.dart` | 학번 값 객체 |
| `frontend/lib/auth/model/verification_gate.dart` | 라우터 게이트용 상태 enum |
| `frontend/lib/auth/model/verification_gate_repository.dart` | 게이트 조회 인터페이스 |
| `frontend/lib/auth/model/http_verification_gate_repository.dart` | FastAPI `GET /me/verification-status` 구현체 |
| `frontend/lib/auth/model/student_verification_repository.dart` | 학생증 제출·상태 조회 인터페이스 |
| `frontend/lib/auth/model/http_student_verification_repository.dart` | FastAPI 구현체(멀티파트 업로드) |
| `frontend/lib/auth/model/school_info_repository.dart` | 학과·학번 제출 인터페이스 + FastAPI 구현체 |
| `frontend/lib/auth/model/face_detector.dart` | 얼굴 검출 인터페이스 + ML Kit 구현체 |
| `frontend/lib/auth/model/image_compressor.dart` | 압축·JPEG 재인코딩 인터페이스 + 구현체 |
| `frontend/lib/auth/viewmodel/student_verification_ui_state.dart` | 3b 화면 상태 |
| `frontend/lib/auth/viewmodel/student_verification_view_model.dart` | 3b 흐름 제어 |
| `frontend/lib/auth/view/student_verification_screen.dart` | DESIGN.md 화면 `3b` |
| `frontend/lib/auth/viewmodel/school_info_ui_state.dart` | 3c 화면 상태 |
| `frontend/lib/auth/viewmodel/school_info_view_model.dart` | 3c 흐름 제어 |
| `frontend/lib/auth/view/school_info_screen.dart` | DESIGN.md 화면 `3c` |
| `frontend/lib/core/router/app_routes.dart` (수정) | `studentVerification`·`schoolInfo` 경로 추가 |
| `frontend/lib/core/router/verification_gate_listenable.dart` | 게이트 상태 캐시 + `go_router` 재평가 트리거 |
| `frontend/lib/core/router/auth_redirect.dart` (수정) | 게이트 인식 리다이렉트 |
| `frontend/lib/core/router/app_router.dart` (수정) | 새 라우트 등록, 게이트 리스너블 연결 |
| `frontend/lib/main.dart` (수정) | `VerificationGateListenable` 실제 연결 |

### Part B — `backend/`

| 파일 | 책임 |
| --- | --- |
| `backend/pyproject.toml` (수정) | `google-cloud-vision` 추가 |
| `backend/app/settings.py` (수정) | `discord_webhook_url`·`google_cloud_project` 추가 |
| `backend/app/main.py` (수정) | 새 라우터 등록 |
| `backend/app/student_verification/__init__.py` | |
| `backend/app/student_verification/schemas.py` | 요청·응답 pydantic 모델 |
| `backend/app/student_verification/current_user.py` | Bearer 토큰 → 사용자 id (Supabase Auth 호출) |
| `backend/app/student_verification/image_validation.py` | 크기·매직바이트 검사 |
| `backend/app/student_verification/storage.py` | `student-id-temp` 업로드(REST) |
| `backend/app/student_verification/ocr.py` | Vision API 텍스트 추출 |
| `backend/app/student_verification/matching.py` | 학교명·실명 대조 |
| `backend/app/student_verification/discord_notifier.py` | 재검토 알림 웹훅 |
| `backend/app/student_verification/repository.py` | PostgREST 조회·쓰기 |
| `backend/app/student_verification/router.py` | `POST /student-verification`, `GET /me/verification-status`, `POST /school-info` |
| `backend/tests/student_verification/test_*.py` | 모듈별 단위 테스트 |

### Part C — Supabase·GCP 설정 (사용자 승인 후)

| 파일 | 책임 |
| --- | --- |
| `supabase/migrations/20260914055607_add_student_verification.sql` (기존, 적용만) | `verification_status` enum·`profiles.student_verification` |
| `supabase/migrations/20260914055617_create_profile_private.sql` (기존, 적용만) | `profile_private` 테이블·RLS |
| `supabase/migrations/20260914055624_create_student_id_temp_bucket.sql` (기존, 적용만) | `student-id-temp` 버킷 |
| `supabase/migrations/20260914055631_revoke_rls_auto_enable_execute.sql` (기존, 적용만) | advisor WARN 대응 — PR #32 와 같은 파일인지 적용 직전에 `list_migrations` 로 확인(중복 적용 방지) |
| `supabase/migrations/20260914061304_create_student_verification_attempts.sql` (기존, 적용만) | `student_verification_attempts` 테이블 |
| `supabase/migrations/20260914061821_set_profile_photos_bucket_limits.sql` (기존, 적용만) | `profile-photos` 제한 |
| `supabase/migrations/<timestamp>_add_school_info_to_profiles.sql` (신규) | `profiles.department`·`profiles.student_number` 컬럼 |
| `supabase/migrations/<timestamp>_create_student_verification_finalized_trigger.sql` (신규) | 확정 시 학생증 사진 삭제 트리거 |
| `supabase/tests/rls_slice1_test.sql` (수정) | 신규 컬럼 grant, 삭제 트리거 pgTAP 추가 |
| `backend/DEPLOY.md` (수정) | `GOOGLE_CLOUD_PROJECT`·`DISCORD_WEBHOOK_URL` 시크릿 등록·배포 절차 추가, Vision API 활성화 |

---

## Part A: Flutter

### Task A1: 의존성 추가 (사용자 승인 필요)

**Files:**
- Modify: `frontend/pubspec.yaml`

- [ ] **Step 1: 사용자에게 3개 의존성(위 Global Constraints 목록) 승인을 받는다.** 승인 전에는 이 Task를 실행하지 않는다
- [ ] **Step 2: 추가**

```yaml
dependencies:
  google_mlkit_face_detection: ^0.13.1
  flutter_image_compress: ^2.3.0
  http: ^1.2.2
```

- [ ] **Step 3: 설치 확인**

Run: `flutter pub get`
Expected: 에러 없이 lock 파일 갱신

- [ ] **Step 4: 커밋**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "➕ chore: 학생증 인증용 의존성 3개 추가(face_detection·image_compress·http)"
```

---

### Task A2: Failure 서브타입 추가

**Files:**
- Modify: `frontend/lib/common/failure.dart`
- Test: `frontend/test/common/failure_test.dart`

- [ ] **Step 1: 실패하는 테스트**

```dart
test('얼굴이 없으면 재촬영을 안내한다', () {
  const failure = NoFaceDetectedFailure();
  expect(failure.toDisplayMessage(), '얼굴이 보이는 사진으로 다시 올려주세요');
});

test('서버 거부 사유를 그대로 보여준다', () {
  const failure = ServerRejectedFailure('이미 검토 중이에요');
  expect(failure.toDisplayMessage(), '이미 검토 중이에요');
});
```

- [ ] **Step 2: 실패 확인** — `flutter test test/common/failure_test.dart`
- [ ] **Step 3: 구현**

```dart
/// 학생증 사진에서 얼굴을 찾지 못한 경우(기기 안 ML Kit 판단, 설계 §7.3).
final class NoFaceDetectedFailure extends Failure {
  const NoFaceDetectedFailure();

  @override
  String toDisplayMessage() => '얼굴이 보이는 사진으로 다시 올려주세요';
}

/// 학생증 인증 서버가 거부한 경우(예: 검토 중 재제출). 서버 메시지를 그대로 보여준다.
final class ServerRejectedFailure extends Failure {
  const ServerRejectedFailure(this._message);

  final String _message;

  @override
  String toDisplayMessage() => _message;
}
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(auth): 학생증 인증 Failure 2종 추가`)

---

### Task A3: RealName · Department · StudentNumber 값 객체

**Files:**
- Create: `frontend/lib/auth/model/real_name.dart`, `frontend/lib/auth/model/department.dart`, `frontend/lib/auth/model/student_number.dart`
- Test: 대응하는 `frontend/test/auth/model/*_test.dart` 3개

세 값 객체 모두 같은 모양이다 — 앞뒤 공백 제거, 빈 문자열이면 `null`, 최대 길이만 다르게 검사한다(실명 30자, 학과 30자, 학번 20자 — DESIGN.md 3c 예시 "컴퓨터공학과"·"21"에 여유를 둔 값, 임의 상한이라 사용자 확인 없이 결정해도 되는 수준으로 판단).

- [ ] **Step 1: 실패하는 테스트 (RealName 예시, 나머지 2개도 동일 패턴)**

```dart
test('빈 문자열이면 null', () {
  expect(RealName.tryParse('   '), isNull);
});

test('앞뒤 공백을 잘라낸다', () {
  expect(RealName.tryParse(' 김가나 ')!.toRequestValue(), '김가나');
});

test('30자를 넘으면 null', () {
  expect(RealName.tryParse('가' * 31), isNull);
});
```

- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현 (RealName, Department·StudentNumber는 최대 길이만 바꿔 동일하게)**

```dart
/// 학생증 사진과 대조할 실명 값 객체(설계 §7.3, `profile_private.real_name`).
final class RealName {
  RealName._(this._value);

  final String _value;

  static RealName? tryParse(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized.length > 30) {
      return null;
    }
    return RealName._(normalized);
  }

  String toRequestValue() => _value;

  @override
  bool operator ==(Object other) => other is RealName && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(auth): RealName·Department·StudentNumber 값 객체 추가`)

---

### Task A4: FaceDetector · ImageCompressor

**Files:**
- Create: `frontend/lib/auth/model/face_detector.dart`, `frontend/lib/auth/model/image_compressor.dart`
- Test: `frontend/test/auth/model/face_detector_test.dart`(Fake 대상), `frontend/test/auth/model/image_compressor_test.dart`(Fake 대상)

ML Kit·`flutter_image_compress`는 플랫폼 채널이라 위젯/통합 테스트 없이는 진짜 구현체를 유닛 테스트하지 못한다. 인터페이스 + Fake만 여기서 테스트하고, 진짜 구현체는 Task A11에서 실기기로 확인한다(frontend/CLAUDE.md §8 규칙대로).

- [ ] **Step 1: 인터페이스 정의**

```dart
import 'dart:io';

/// 학생증 사진에 얼굴이 보이는지 기기 안에서 판단한다(설계 §7.3, 서버로 보내기 전 1차 필터).
abstract interface class FaceDetector {
  Future<bool> hasFace(File image);
}
```

```dart
import 'dart:io';

/// 업로드 전 사진을 압축하고 JPEG 로 다시 인코딩한다(설계 §7.4).
abstract interface class ImageCompressor {
  Future<File> compressToJpeg(File source);
}
```

- [ ] **Step 2: 구현체**

```dart
import 'dart:io';

import 'package:campus_mate/auth/model/face_detector.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class MlKitFaceDetector implements FaceDetector {
  MlKitFaceDetector() : _detector = FaceDetector(options: FaceDetectorOptions());

  final FaceDetector _detector;

  @override
  Future<bool> hasFace(File image) async {
    final faces = await _detector.processImage(InputImage.fromFile(image));
    return faces.isNotEmpty;
  }
}
```

```dart
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class FlutterImageCompressor implements ImageCompressor {
  @override
  Future<File> compressToJpeg(File source) async {
    final targetDir = await getTemporaryDirectory();
    final targetPath = '${targetDir.path}/student-id-${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      quality: 85,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      return source;
    }
    return File(result.path);
  }
}
```

**주의:** `path_provider`는 `flutter_image_compress`가 내부적으로 요구하지 않지만 임시 저장 경로를 얻으려고 여기서 새로 쓴다 — 이것도 신규 의존성이라 **Task A1 승인 목록에 빠졌다.** Task A1 실행 전에 사용자에게 `path_provider` 추가도 같이 물어본다(계획 작성 중 뒤늦게 발견, Ruling: 목록에 추가하고 진행 — 값싼 표준 패키지라 반려 가능성 낮다고 보고 계획은 그대로 두되 승인 단계에서 반드시 같이 확인).

- [ ] **Step 3: Fake 작성 (테스트용, `lib/`에 두지 않음)**

```dart
class FakeFaceDetector implements FaceDetector {
  bool nextResult = true;

  @override
  Future<bool> hasFace(File image) async => nextResult;
}
```

- [ ] **Step 4: 커밋** (`✨ feat(auth): FaceDetector·ImageCompressor 인터페이스와 구현체 추가`)

---

### Task A5: StudentVerificationRepository

**Files:**
- Create: `frontend/lib/auth/model/student_verification_repository.dart`, `frontend/lib/auth/model/http_student_verification_repository.dart`
- Test: `frontend/test/auth/model/http_student_verification_repository_test.dart`(`package:http`의 `MockClient` 사용)

**Interfaces:**
- Produces: `StudentVerificationRepository.submit(RealName, File photo) -> Future<Result<VerificationOutcome>>`, `.fetchStatus() -> Future<Result<VerificationOutcome>>`
- `VerificationOutcome`은 `{status: pending|verified|rejected, rejectReason: String?}`을 담는 불변 클래스(원칙 7 예외 — 서버 응답을 그대로 옮기는 DTO라 UiState에 준하는 예외로 취급)

FastAPI 백엔드 URL·anon key는 1a와 동일하게 `--dart-define`으로 주입한다(`API_BASE_URL` 신규 define 필요 — Task A1 승인 때 같이 확인). `Authorization: Bearer <accessToken>`은 `Supabase.instance.client.auth.currentSession!.accessToken`에서 가져온다.

- [ ] **Step 1: 실패하는 테스트 작성** — 성공(200, `{"status":"verified"}`), 검토중 재제출(409, `{"detail":"이미 검토 중이에요"}` → `ServerRejectedFailure`), 얼굴 없음은 클라이언트에서 걸러 서버까지 가지 않으므로 여기서 테스트하지 않는다
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 인터페이스 + 구현**

```dart
import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/common/result.dart';

/// 3b 화면의 제출 결과.
class VerificationOutcome {
  const VerificationOutcome({required this.status, this.rejectReason});

  final String status; // 'pending' | 'verified' | 'rejected'
  final String? rejectReason;
}

abstract interface class StudentVerificationRepository {
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo);
  Future<Result<VerificationOutcome>> fetchStatus();
}
```

```dart
import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class HttpStudentVerificationRepository implements StudentVerificationRepository {
  const HttpStudentVerificationRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/student-verification'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}'
      ..fields['real_name'] = realName.toRequestValue()
      ..files.add(await http.MultipartFile.fromPath('photo', photo.path));
    return _send(request);
  }

  @override
  Future<Result<VerificationOutcome>> fetchStatus() async {
    final request = http.Request('GET', Uri.parse('$_baseUrl/me/verification-status'))
      ..headers['Authorization'] = 'Bearer ${_auth.currentSession!.accessToken}';
    return _send(request);
  }

  Future<Result<VerificationOutcome>> _send(http.BaseRequest request) async {
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Success(VerificationOutcome(status: body['status'] as String, rejectReason: body['reject_reason'] as String?));
    }
    if (response.statusCode == 429) {
      return const FailureResult(RateLimitedFailure());
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return FailureResult(ServerRejectedFailure(body['detail'] as String? ?? '알 수 없는 오류가 발생했습니다'));
  }
}
```

(`dart:convert`의 `jsonDecode` import 를 빠뜨리지 않는다.)

- [ ] **Step 4: Provider 작성** (`auth_repository_provider.dart` 옆에 `student_verification_repository_provider.dart` 신규 — `API_BASE_URL`은 `String.fromEnvironment`로 읽는다)
- [ ] **Step 5: 통과 확인, Step 6: 커밋** (`✨ feat(auth): StudentVerificationRepository 를 FastAPI 호출로 구현`)

---

### Task A6: SchoolInfoRepository

**Files:**
- Create: `frontend/lib/auth/model/school_info_repository.dart`, `frontend/lib/auth/model/http_school_info_repository.dart`
- Test: `frontend/test/auth/model/http_school_info_repository_test.dart`

Task A5와 같은 모양이다 — `submit(Department, StudentNumber) -> Future<Result<void>>`, JSON POST `/school-info`(멀티파트 아님). 구현은 A5의 `_send` 패턴을 그대로 따른다.

- [ ] **Step 1~6**: A5와 동일한 TDD 순서. 커밋 메시지 `✨ feat(auth): SchoolInfoRepository 추가`

---

### Task A7: VerificationGate

**Files:**
- Create: `frontend/lib/auth/model/verification_gate.dart`, `frontend/lib/auth/model/verification_gate_repository.dart`, `frontend/lib/auth/model/http_verification_gate_repository.dart`
- Test: `frontend/test/auth/model/http_verification_gate_repository_test.dart`

라우터가 쓸 굵은 단위 상태. 3b·3c 화면 내부 상태(pending·rejected 사유 등)는 Task A5·A6의 `VerificationOutcome`이 따로 맡고, 이 값은 "어느 화면으로 보낼지"만 판단한다.

- [ ] **Step 1: 정의**

```dart
/// go_router 가 다음 화면을 정할 때만 쓰는 굵은 단위 상태.
/// 3b 화면 안의 세부 상태(검토중 사유 등)는 VerificationOutcome 이 따로 다룬다.
enum VerificationGate {
  needsStudentVerification,
  needsSchoolInfo,
  complete,
}
```

- [ ] **Step 2: 인터페이스**

```dart
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/result.dart';

abstract interface class VerificationGateRepository {
  Future<Result<VerificationGate>> fetchGate();
}
```

- [ ] **Step 3: 구현 — `/me/verification-status` 응답에서 `status`·`has_school_info`를 읽어 매핑**

```dart
@override
Future<Result<VerificationGate>> fetchGate() async {
  // ... Task A5 의 _send 와 동일한 GET 호출 ...
  return Success(_toGate(body['status'] as String, body['has_school_info'] as bool));
}

VerificationGate _toGate(String status, bool hasSchoolInfo) {
  if (status != 'verified') {
    return VerificationGate.needsStudentVerification;
  }
  if (!hasSchoolInfo) {
    return VerificationGate.needsSchoolInfo;
  }
  return VerificationGate.complete;
}
```

- [ ] **Step 4: 테스트 3케이스(각 enum 값), Step 5: 커밋** (`✨ feat(auth): VerificationGateRepository 추가`)

---

### Task A8: StudentVerificationViewModel (3b)

**Files:**
- Create: `frontend/lib/auth/viewmodel/student_verification_ui_state.dart`, `frontend/lib/auth/viewmodel/student_verification_view_model.dart`
- Test: 대응 `_test.dart` 2개

**흐름:** `build()`에서 먼저 `fetchStatus()`를 호출해 현재 상태(none/pending/rejected)를 반영한다(앱을 나갔다 돌아온 pending 사용자를 위해). 사용자가 실명 입력 + 사진 선택 → `submit()`이 압축 → 얼굴 검출(실패 시 서버 호출 없이 `NoFaceDetectedFailure`) → 업로드 순으로 처리한다.

```dart
/// 3b 학생증 인증 화면 상태.
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

  final String realNameInput;
  final RealName? realName;
  final File? selectedPhoto;
  final bool isSubmitting;
  final bool isLoadingStatus;
  final String status; // 'none' | 'pending' | 'rejected' — 'verified' 면 라우터가 이미 3c 로 보냄
  final String? errorMessage;

  bool get canSubmit => realName != null && selectedPhoto != null && !isSubmitting;
}
```

```dart
class StudentVerificationViewModel extends Notifier<StudentVerificationUiState> {
  @override
  StudentVerificationUiState build() {
    Future.microtask(_loadStatus);
    return const StudentVerificationUiState();
  }

  Future<void> _loadStatus() async {
    final result = await ref.read(studentVerificationRepositoryProvider).fetchStatus();
    state = result.when(
      onSuccess: (outcome) => StudentVerificationUiState(status: outcome.status, isLoadingStatus: false),
      onFailure: (failure) => StudentVerificationUiState(isLoadingStatus: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  void changeRealName(String value) {
    state = _copyWith(realNameInput: value, realName: RealName.tryParse(value));
  }

  Future<void> pickPhoto() async {
    final picked = await ref.read(imagePickerProvider).pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return;
    }
    state = _copyWith(selectedPhoto: File(picked.path));
  }

  Future<void> submit() async {
    final realName = state.realName;
    final photo = state.selectedPhoto;
    if (realName == null || photo == null) {
      return;
    }
    state = _copyWith(isSubmitting: true);
    final compressed = await ref.read(imageCompressorProvider).compressToJpeg(photo);
    if (!await ref.read(faceDetectorProvider).hasFace(compressed)) {
      state = _copyWith(isSubmitting: false, errorMessage: const NoFaceDetectedFailure().toDisplayMessage());
      return;
    }
    final result = await ref.read(studentVerificationRepositoryProvider).submit(realName, compressed);
    state = result.when(
      onSuccess: (outcome) => StudentVerificationUiState(status: outcome.status, isLoadingStatus: false),
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  StudentVerificationUiState _copyWith({/* ... 필드별 named 파라미터 ... */}) {
    // frontend/CLAUDE.md 원칙 6(메서드 10줄) 을 지키려면 copyWith 는 각 필드를 상태에서 받아오는
    // 표준 패턴으로 작성한다(1a SignUpUiState 는 필드 4개라 생략했지만 여긴 6개라 필요).
    throw UnimplementedError('구현 시 표준 copyWith 패턴 적용');
  }
}
```

- [ ] **Step 1: 실패하는 테스트** — `build()`가 상태를 로드한다 / 실명·사진 없으면 `canSubmit` false / 얼굴 없으면 서버 호출 없이 에러 / 제출 성공하면 `status`가 갱신된다 / 제출 실패하면 `errorMessage`
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 위 코드대로 구현하되 `_copyWith`를 실제 필드 복사 코드로 채운다**
- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(auth): StudentVerificationViewModel 구현`)

---

### Task A9: SchoolInfoViewModel (3c)

**Files:**
- Create: `frontend/lib/auth/viewmodel/school_info_ui_state.dart`, `frontend/lib/auth/viewmodel/school_info_view_model.dart`
- Test: 대응 `_test.dart` 2개

Task A8보다 단순하다 — `Department`·`StudentNumber` 둘 다 유효해야 `canSubmit`, `submit()`은 `SchoolInfoRepository.submit()` 호출 후 성공 시 `completed = true`(라우터가 이 값을 보고 게이트를 재평가하도록 트리거).

- [ ] **Step 1~5**: Task A5·A8과 같은 TDD 순서. 커밋 메시지 `✨ feat(auth): SchoolInfoViewModel 구현`

---

### Task A10: 라우팅 — VerificationGate 연결

**Files:**
- Modify: `frontend/lib/core/router/app_routes.dart`, `frontend/lib/core/router/auth_redirect.dart`, `frontend/lib/core/router/app_router.dart`, `frontend/lib/main.dart`
- Create: `frontend/lib/core/router/verification_gate_listenable.dart`
- Test: `frontend/test/core/router/auth_redirect_test.dart`(수정), `frontend/test/core/router/verification_gate_listenable_test.dart`

**Interfaces:**
- Consumes: `VerificationGate`(Task A7), `AuthSessionListenable`(1a)
- Produces: 게이트를 반영한 `AuthRedirect.resolve`

**설계.** `AuthRedirect`는 순수 Dart라 Riverpod을 모른다. `VerificationGateListenable`이 캐시 역할을 한다 — `AuthSessionListenable`(1a, 세션 변화 감지)이 알려줄 때마다 게이트를 다시 조회해 캐시하고 `notifyListeners()`한다. 조회가 끝나기 전(`unknown`)에는 **미인증 상태와 동일하게 다뤄 `needsStudentVerification`으로 간주한다** — 실제로 이미 통과한 사용자라도 게이트가 도착하는 즉시 다시 리다이렉트되므로 짧은 깜빡임 이상의 피해는 없고, 반대로 낙관적으로 통과시키면 "통과 전까지 다음 단계로 못 감"(설계 §7.3) 원칙이 깨진다.

- [ ] **Step 1: 실패하는 테스트 (AuthRedirect)**

```dart
test('인증됐지만 학생증 미인증이면 3b 로 보낸다', () {
  final redirect = AuthRedirect(true, VerificationGate.needsStudentVerification);
  expect(redirect.resolve(AppRoutes.home), AppRoutes.studentVerification);
});

test('학생증은 통과했지만 학과 정보가 없으면 3c 로 보낸다', () {
  final redirect = AuthRedirect(true, VerificationGate.needsSchoolInfo);
  expect(redirect.resolve(AppRoutes.home), AppRoutes.schoolInfo);
});

test('게이트를 모두 통과하면 3b·3c 에 머물지 않는다', () {
  final redirect = AuthRedirect(true, VerificationGate.complete);
  expect(redirect.resolve(AppRoutes.studentVerification), AppRoutes.home);
});

test('이미 목적지에 있으면 리다이렉트하지 않는다', () {
  final redirect = AuthRedirect(true, VerificationGate.needsStudentVerification);
  expect(redirect.resolve(AppRoutes.studentVerification), isNull);
});
```

- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: AppRoutes 확장**

```dart
static const String studentVerification = '/student-verification';
static const String schoolInfo = '/school-info';
```

- [ ] **Step 4: AuthRedirect 구현**

```dart
class AuthRedirect {
  const AuthRedirect(this._isAuthenticated, this._gate);

  final bool _isAuthenticated;
  final VerificationGate _gate;

  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  String? _resolveForMember(String location) {
    final gateTarget = _gateTarget();
    if (gateTarget != null) {
      return location == gateTarget ? null : gateTarget;
    }
    if (location == AppRoutes.login || location == AppRoutes.splash
        || location == AppRoutes.studentVerification || location == AppRoutes.schoolInfo) {
      return AppRoutes.home;
    }
    return null;
  }

  String? _gateTarget() {
    return switch (_gate) {
      VerificationGate.needsStudentVerification => AppRoutes.studentVerification,
      VerificationGate.needsSchoolInfo => AppRoutes.schoolInfo,
      VerificationGate.complete => null,
    };
  }

  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login || location == AppRoutes.verifyCode) {
      return null;
    }
    return AppRoutes.login;
  }
}
```

- [ ] **Step 5: VerificationGateListenable 작성**

```dart
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:flutter/foundation.dart';

/// 게이트 상태를 캐시하고, 바뀌면 go_router 재평가를 트리거한다.
/// AuthSessionListenable(1a) 이 알려줄 때마다 refresh() 를 호출해 쓴다.
class VerificationGateListenable extends ChangeNotifier {
  VerificationGateListenable(this._repository);

  final VerificationGateRepository _repository;
  VerificationGate _cached = VerificationGate.needsStudentVerification;

  VerificationGate get value => _cached;

  Future<void> refresh() async {
    final result = await _repository.fetchGate();
    result.when(
      onSuccess: (gate) {
        if (gate != _cached) {
          _cached = gate;
          notifyListeners();
        }
      },
      onFailure: (_) {}, // 실패하면 캐시를 유지한다 — 다음 세션 변화 때 다시 시도
    );
  }
}
```

- [ ] **Step 6: AppRouter·main.dart 연결** — `AppRouter.create`에 `verificationGate: () => VerificationGate` 콜백을 추가하고 `refreshListenable`을 `Listenable.merge([authListenable, gateListenable])`로 바꾼다. `main.dart`에서 세션이 바뀔 때마다(`AuthSessionListenable` 콜백 안에서) `gateListenable.refresh()`를 호출한다
- [ ] **Step 7: 라우트 등록** — `AppRoutes.studentVerification` → `StudentVerificationScreen`, `AppRoutes.schoolInfo` → `SchoolInfoScreen` (`AuthRedirect`가 이미 미인증·게이트 미충족을 막으므로 화면 자체에 가드 불필요)
- [ ] **Step 8: 통과 확인, Step 9: 커밋** (`✨ feat(core): 라우터에 학생증·학과 인증 게이트 연결`)

---

### Task A11: StudentVerificationScreen (3b)

**Files:**
- Create: `frontend/lib/auth/view/student_verification_screen.dart`
- Test: `frontend/test/auth/view/student_verification_screen_test.dart`

- [ ] **Step 0: pencil MCP로 `datingApp.pen`의 화면 `3b`·"53. Bottom Bar CTA"(A8INC6)를 직접 읽고 아래 레이아웃을 대조한다.** 이 세션에서는 pencil MCP 연결 실패로 못 했다 — 구현 세션에서 재확인 필수
- [ ] **Step 1: 실패하는 테스트** — 로딩 중 스피너 / 실명·사진 없으면 CTA 비활성 / `status == 'pending'`이면 "조금 더 확인이 필요해요" 대기 화면 / `status == 'rejected'`면 반려 사유 노출 후 재제출 가능
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현** — DESIGN.md §9 `3b` 구성을 따른다: `campus-trust-icon-v1` 히어로 → 안내 문구 → `text-field`(실명) → 사진 업로더(`image_picker` 갤러리 선택, 선택된 파일 미리보기) → 하단 CTA. `state.isLoadingStatus`면 전체를 로딩 스피너로 대체하고, `state.status == 'pending'`이면 업로드 폼 대신 마스코트 + "조금 더 확인이 필요해요, 완료되면 알려드릴게요"만 보여준다(재시도 버튼 없음 — 라우터가 `fetchStatus` 폴링으로 알아서 넘겨준다, Step 4). `state.status == 'rejected'`면 `state.errorMessage`에 반려 사유를 담아 폼 위에 배너로 보여주고 재제출은 그대로 허용(재제출 상한 없음, 이번 결정)
- [ ] **Step 4: pending 폴링** — `pending` 상태일 때 화면이 보이는 동안 30초 간격으로 `fetchStatus()`를 다시 부른다(`Timer.periodic`, `dispose`에서 취소). 사람 재검토는 분·시간 단위로 걸리므로 실시간 스트림 없이 폴링으로 충분하다(YAGNI — Realtime 구독은 안 씀)
- [ ] **Step 5: 통과 확인, Step 6: 커밋** (`✨ feat(auth): StudentVerificationScreen 구현`)

---

### Task A12: SchoolInfoScreen (3c)

**Files:**
- Create: `frontend/lib/auth/view/school_info_screen.dart`
- Test: `frontend/test/auth/view/school_info_screen_test.dart`

- [ ] **Step 0**: Task A11과 동일하게 pencil MCP로 화면 `3c` 재확인
- [ ] **Step 1~6**: Task A11과 같은 TDD 순서. DESIGN.md §9 `3c` 구성 그대로 — App Bar("학생 인증") → 헤드라인 → 학교 확인 행(읽기 전용, `graduation-cap` + 학교명 + `badge-check`, 학교명은 `verification_gate` 응답이 아니라 `GET /me/verification-status`를 확장해 함께 내려주거나 별도 `profiles` select — **Ruling: 이미 로그인한 사용자는 `profiles.university_id`를 직접 select 할 수 있으므로(RLS 본인 행 허용) 새 엔드포인트 없이 `Supabase.instance.client.from('profiles').select('universities(name)')`로 조회한다** — 왜 이 화면만 FastAPI를 안 거치냐면, 읽기 전용 + 이미 RLS로 본인 것만 보이는 조회라 §7.1 원칙("남의 데이터가 섞이는 조회·쓰기"에 해당 안 함)의 예외 대상이 아니라 애초에 원칙 적용 대상 밖이다) → `text-field`(학과) → `text-field`(학번) → 공개 범위 안내 → CTA. 커밋 메시지 `✨ feat(auth): SchoolInfoScreen 구현`

---

## Part B: `backend/`

### Task B1: 의존성 추가 (사용자 승인 필요)

**Files:**
- Modify: `backend/pyproject.toml`

- [ ] **Step 1: 승인 확인** — `google-cloud-vision`, Global Constraints 참고
- [ ] **Step 2: 추가**

```toml
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "httpx>=0.27",
    "pydantic-settings>=2.6",
    "google-cloud-vision>=3.9",
]
```

- [ ] **Step 3: 설치 확인** — `pip install -e ".[dev]"`
- [ ] **Step 4: 커밋** (`➕ chore(backend): google-cloud-vision 추가`)

---

### Task B2: Settings 확장

**Files:**
- Modify: `backend/app/settings.py`
- Modify: `backend/tests/test_settings.py`

- [ ] **Step 1: 실패하는 테스트** — `discord_webhook_url`·`google_cloud_project` 필드 존재 확인
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    auth_hook_signing_secret: str
    discord_webhook_url: str
    google_cloud_project: str

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"

    @property
    def storage_url(self) -> str:
        return f"{self.supabase_url}/storage/v1"

    @property
    def auth_url(self) -> str:
        return f"{self.supabase_url}/auth/v1"
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`🔧 chore(backend): 학생증 인증 설정값 추가`)

---

### Task B3: current_user — Bearer 토큰 검증

**Files:**
- Create: `backend/app/student_verification/current_user.py`
- Test: `backend/tests/student_verification/test_current_user.py`

**설계.** JWT를 직접 검증(서명 키 관리)하지 않고 Supabase Auth의 `GET /auth/v1/user`를 그대로 호출해 검증을 위임한다 — 1a `signup_policy.py`가 PostgREST를 직접 호출하는 것과 같은 패턴(httpx만 쓰고 SDK를 늘리지 않는다). `apikey` 헤더에는 이미 서버가 갖고 있는 `service_role` 키를 쓴다(Flutter가 보낸 사용자 토큰은 `Authorization`에, `apikey`는 프로젝트 식별용이라 서버 키를 재사용해도 안전 — Supabase Auth 서버 쪽 요구사항일 뿐 권한 상승이 아니다).

- [ ] **Step 1: 실패하는 테스트** — 유효한 토큰이면 user id 반환(httpx 모킹) / `Authorization` 헤더 없으면 401 / Supabase가 401 돌려주면 그대로 401
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
from uuid import UUID

import httpx
from fastapi import Header, HTTPException

from app.settings import Settings


async def get_current_user_id(
    settings: Settings,
    client: httpx.AsyncClient,
    authorization: str | None = Header(default=None),
) -> UUID:
    if authorization is None:
        raise HTTPException(status_code=401, detail="로그인이 필요해요")
    response = await client.get(
        f"{settings.auth_url}/user",
        headers={"Authorization": authorization, "apikey": settings.supabase_service_role_key},
    )
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="세션이 만료됐어요, 다시 로그인해 주세요")
    return UUID(response.json()["id"])
```

(라우터에서는 FastAPI `Depends`로 감싸 `client`·`settings`를 주입한다 — 1a `router.py`의 `get_settings()`·`_client_override` 패턴을 그대로 따른다.)

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): Supabase Auth 로 사용자 토큰 검증`)

---

### Task B4: 파일 검증

**Files:**
- Create: `backend/app/student_verification/image_validation.py`
- Test: `backend/tests/student_verification/test_image_validation.py`

**설계.** 매직바이트만 표준 라이브러리로 직접 비교한다 — `imghdr`은 3.13에서 제거됐고 `python-magic`은 새 의존성이라 YAGNI, JPEG·PNG 딱 2종만 검사하면 되므로 바이트 프리픽스 비교로 충분하다(ponytail 원칙 3·6).

- [ ] **Step 1: 실패하는 테스트** — JPEG 시그니처(`FF D8 FF`) 통과 / PNG 시그니처(`89 50 4E 47 0D 0A 1A 0A`) 통과 / 그 외 바이트 거부 / 10MB 초과 거부
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
_MAX_SIZE = 10 * 1024 * 1024
_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def is_valid_student_id_photo(data: bytes) -> bool:
    if len(data) > _MAX_SIZE:
        return False
    return data.startswith(_JPEG_MAGIC) or data.startswith(_PNG_MAGIC)
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): 학생증 사진 매직바이트·크기 검증`)

---

### Task B5: Storage 업로드

**Files:**
- Create: `backend/app/student_verification/storage.py`
- Test: `backend/tests/student_verification/test_storage.py`

- [ ] **Step 1: 실패하는 테스트** — 업로드 성공 시 객체 경로 반환(httpx 모킹), 실패 시 예외
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
from uuid import UUID, uuid4

import httpx


class StudentIdStorage:
    """`student-id-temp` 비공개 버킷에 업로드한다(설계 §7.4). 삭제는 이 클래스가 하지 않는다 —
    profiles.student_verification 이 확정되는 순간 Postgres 트리거가 대신 지운다(2026-09-19 설계)."""

    def __init__(self, storage_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._storage_url = storage_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }
        self._client = client

    async def upload(self, profile_id: UUID, data: bytes, content_type: str) -> str:
        path = f"{profile_id}/{uuid4()}.jpg"
        response = await self._client.post(
            f"{self._storage_url}/object/student-id-temp/{path}",
            content=data,
            headers={**self._headers, "Content-Type": content_type},
        )
        response.raise_for_status()
        return path
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): StudentIdStorage 업로드 구현`)

---

### Task B6: OCR

**Files:**
- Create: `backend/app/student_verification/ocr.py`
- Test: `backend/tests/student_verification/test_ocr.py`

- [ ] **Step 1: 실패하는 테스트** — Vision 클라이언트를 모킹해 `text_annotations`가 있으면 합친 텍스트 반환, 없으면 빈 문자열
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
from google.cloud import vision


class VisionOcr:
    """Google Cloud Vision 으로 학생증 이미지에서 텍스트를 추출한다(2026-09-19 결정).
    ADC(Cloud Run 서비스 계정)로 인증하므로 별도 API 키가 없다."""

    def __init__(self, client: vision.ImageAnnotatorAsyncClient):
        self._client = client

    async def extract_text(self, image_bytes: bytes) -> str:
        image = vision.Image(content=image_bytes)
        response = await self._client.text_detection(image=image)
        if response.error.message:
            raise RuntimeError(response.error.message)
        annotations = response.text_annotations
        return annotations[0].description if annotations else ""
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): Vision OCR 클라이언트 추가`)

---

### Task B7: 대조 로직

**Files:**
- Create: `backend/app/student_verification/matching.py`
- Test: `backend/tests/student_verification/test_matching.py`

**설계.** 공백을 지우고 대소문자를 낮춰 부분 문자열 포함 검사만 한다(설계 §7.3 "OCR 텍스트 안에 학교명과 3b 실명이 둘 다 보일 때") — 오탈자 보정 등 퍼지 매칭은 이번 결정 범위 밖(애매하면 사람이 본다는 게 이 설계의 안전판).

- [ ] **Step 1: 실패하는 테스트** — 학교명·실명 둘 다 있으면 True / 하나만 있으면 False / 줄바꿈·공백이 섞여도 True / 대소문자(영문 학교명 대비) 무시
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
def matches_school_and_name(ocr_text: str, school_name: str, real_name: str) -> bool:
    normalized = _normalize(ocr_text)
    return _normalize(school_name) in normalized and _normalize(real_name) in normalized


def _normalize(value: str) -> str:
    return "".join(value.lower().split())
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): 학교명·실명 대조 로직 추가`)

---

### Task B8: Discord 알림

**Files:**
- Create: `backend/app/student_verification/discord_notifier.py`
- Test: `backend/tests/student_verification/test_discord_notifier.py`

- [ ] **Step 1: 실패하는 테스트** — 웹훅 URL로 POST, 본문에 학교명 없이(개인정보 최소화 — 사진도 텍스트도 실명 자체는 안 보낸다, 재검토 담당자는 어차피 대시보드에서 사진을 직접 연다) "학생증 재검토가 1건 있어요"류 텍스트만 담기는지
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
import httpx


class DiscordNotifier:
    def __init__(self, webhook_url: str, client: httpx.AsyncClient):
        self._webhook_url = webhook_url
        self._client = client

    async def notify_pending_review(self) -> None:
        # 사진·실명·학교명은 보내지 않는다(설계 §7.3, 2026-09-19 결정) — 담당자가 대시보드에서 직접 연다.
        response = await self._client.post(self._webhook_url, json={"content": "학생증 재검토가 1건 있어요. Supabase 대시보드에서 확인해 주세요."})
        response.raise_for_status()
```

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): 디스코드 재검토 알림 추가`)

---

### Task B9: Repository — PostgREST 쓰기

**Files:**
- Create: `backend/app/student_verification/repository.py`
- Test: `backend/tests/student_verification/test_repository.py`

**Interfaces:**
- Consumes: Task B3~B8 전부
- Produces: `StudentVerificationRepository` — Task B10 라우터가 씀

- [ ] **Step 1: 실패하는 테스트** — 아래 6개 메서드 각각 httpx 모킹으로: 현재 상태 조회, 실명 upsert, 시도 기록 insert, 상태 업데이트, 학교명 조회(대조용), 학과·학번 업데이트
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**

```python
from uuid import UUID

import httpx


class StudentVerificationRepository:
    def __init__(self, postgrest_url: str, service_role_key: str, client: httpx.AsyncClient):
        self._postgrest_url = postgrest_url
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = client

    async def fetch_gate_status(self, profile_id: UUID) -> dict:
        response = await self._client.get(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}", "select": "student_verification,department,universities(name)"},
            headers=self._headers,
        )
        response.raise_for_status()
        return response.json()[0]

    async def fetch_reject_reason(self, profile_id: UUID) -> str | None:
        response = await self._client.get(
            f"{self._postgrest_url}/student_verification_attempts",
            params={"profile_id": f"eq.{profile_id}", "order": "submitted_at.desc", "limit": "1", "select": "reject_reason"},
            headers=self._headers,
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["reject_reason"] if rows else None

    async def upsert_real_name(self, profile_id: UUID, real_name: str) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/profile_private",
            json={"profile_id": str(profile_id), "real_name": real_name, "updated_at": "now()"},
            headers={**self._headers, "Prefer": "resolution=merge-duplicates"},
        )
        response.raise_for_status()

    async def record_attempt(self, profile_id: UUID, file_path: str, result: str) -> None:
        response = await self._client.post(
            f"{self._postgrest_url}/student_verification_attempts",
            json={"profile_id": str(profile_id), "file_path": file_path, "result": result},
            headers=self._headers,
        )
        response.raise_for_status()

    async def update_verification_status(self, profile_id: UUID, status: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"student_verification": status},
            headers=self._headers,
        )
        response.raise_for_status()

    async def save_school_info(self, profile_id: UUID, department: str, student_number: str) -> None:
        response = await self._client.patch(
            f"{self._postgrest_url}/profiles",
            params={"id": f"eq.{profile_id}"},
            json={"department": department, "student_number": student_number},
            headers=self._headers,
        )
        response.raise_for_status()
```

**주의(구현 시 확인):** `profiles` 테이블의 `service_role` grant 가 `department`·`student_number` 컬럼까지 자동으로 포함하는지 Task C1 마이그레이션에서 명시로 확인한다(컬럼 추가만으로는 기존 `grant select, insert, update, delete on table public.profiles to service_role`가 이미 테이블 전체 권한이라 자동 포함되지만, SUPABASE.md §5 "자동 grant를 믿지 않는다" 원칙에 따라 마이그레이션에서 재확인 문구를 남긴다).

- [ ] **Step 4: 통과 확인, Step 5: 커밋** (`✨ feat(backend): StudentVerificationRepository — PostgREST 쓰기 구현`)

---

### Task B10: 라우터

**Files:**
- Create: `backend/app/student_verification/schemas.py`, `backend/app/student_verification/router.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/student_verification/test_router.py`(`TestClient`, 1a `test_auth_hooks_router.py` 패턴)

**흐름 (POST /student-verification):**
1. `current_user_id` 의존성으로 인증
2. 현재 `profiles.student_verification` 조회 — `pending`이면 409
3. 파일 크기·매직바이트 검증(Task B4) — 실패하면 400
4. Storage 업로드(Task B5)
5. 실명 upsert(Task B9)
6. 시도 기록 insert, `result='pending'`(항상 먼저 pending으로 남긴다 — 테이블 제약 `result <> 'none'`과 맞고, 곧바로 verified로 바뀌어도 트리거가 성립하려면 "pending → verified" 전이가 실제로 있어야 한다)
7. OCR 대조(Task B6·B7) — 학교명은 `fetch_gate_status`가 이미 같이 내려준 값을 재사용(추가 조회 없음)
8. 대조 성공 → `update_verification_status(verified)`(트리거가 파일을 지운다) → 응답 `{"status": "verified"}`
9. 대조 실패 → `status`는 이미 `pending`이라 별도 update 불필요 → 디스코드 알림(Task B8) → 응답 `{"status": "pending"}`

**흐름 (GET /me/verification-status):** `fetch_gate_status` + (status가 rejected면) `fetch_reject_reason` → `{"status", "has_school_info": department is not null, "reject_reason"}`

**흐름 (POST /school-info):** 인증 → `student_verification == 'verified'` 아니면 403 → `save_school_info` → `{"ok": true}`

- [ ] **Step 1: 실패하는 테스트** — 7개 케이스(성공 verified/pending, 검토중 재제출 409, 잘못된 파일 400, 인증 없음 401, status 조회 3케이스, school-info 성공/미인증 403)
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: schemas.py**

```python
from pydantic import BaseModel


class VerificationStatusResponse(BaseModel):
    status: str
    has_school_info: bool
    reject_reason: str | None = None


class SchoolInfoRequest(BaseModel):
    department: str
    student_number: str
```

- [ ] **Step 4: router.py 구현** — 1a `auth_hooks/router.py`의 `get_settings()`·`_client_override` 패턴, `@lru_cache` 재사용
- [ ] **Step 5: main.py 에 등록**

```python
from app.student_verification.router import router as student_verification_router

app.include_router(student_verification_router)
```

- [ ] **Step 6: 통과 확인, Step 7: 커밋** (`✨ feat(backend): 학생증 인증·학과 확인 엔드포인트 구현`)

---

## Part C: Supabase·GCP 설정 (사용자 승인 후)

### Task C1: 신규 마이그레이션 작성 (클라우드 적용 아님, 파일만)

**Files:**
- Create: `supabase/migrations/<timestamp>_add_school_info_to_profiles.sql`
- Create: `supabase/migrations/<timestamp>_create_student_verification_finalized_trigger.sql`
- Modify: `supabase/tests/rls_slice1_test.sql`

파일명은 저장소 루트에서 `supabase migration new add_school_info_to_profiles`·`supabase migration new create_student_verification_finalized_trigger`로 만든다(SUPABASE.md §4, 직접 지어내지 않는다).

- [ ] **Step 1: `add_school_info_to_profiles.sql`**

```sql
-- 조각 1b: 3c(학과·학번 확인) 화면이 쓰는 컬럼. 학생증과 대조하지 않는 자기 입력값이다(설계 §7.3, §13 미결66).
-- 기준 문서: docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md §7.3

alter table public.profiles
  add column department text,
  add column student_number text;

comment on column public.profiles.department is '자기 입력, 학생증 대조 없음(2026-09-13 결정)';
comment on column public.profiles.student_number is '자기 입력, 학생증 대조 없음(2026-09-13 결정)';

-- 기존 profiles grant(조각 0)가 테이블 단위라 새 컬럼도 자동 포함되지만,
-- SUPABASE.md §5 원칙대로 자동 grant 를 믿지 않고 명시로 재확인한다.
-- authenticated 는 본인 행 select 만(조각 0 RLS 그대로, 쓰기는 FastAPI 전용 — SUPABASE.md §5).
```

- [ ] **Step 2: `create_student_verification_finalized_trigger.sql`**

```sql
-- 조각 1b: 학생증 인증이 확정(verified/rejected)되는 순간 임시 사진을 지운다.
-- FastAPI 자동 통과든 사람이 Supabase 대시보드에서 손으로 바꾼 경우든 이 트리거 하나로 처리한다
-- (2026-09-19 설계 — 두 경로가 결국 같은 UPDATE 문을 타므로 삭제 코드를 한 곳에만 둔다).
-- 기준 문서: 설계 §7.3·§7.4, docs/ERD.md §9

create or replace function public.handle_student_verification_finalized()
returns trigger
language plpgsql
as $$
declare
  latest_path text;
begin
  -- pending 에서 확정으로 바뀔 때만 지운다. none 에서 곧장 바뀌는 경로는 없다(라우터·FastAPI 가 강제).
  if old.student_verification is distinct from 'pending'
     or new.student_verification not in ('verified', 'rejected') then
    return new;
  end if;

  select file_path into latest_path
    from public.student_verification_attempts
    where profile_id = new.id
    order by submitted_at desc
    limit 1;

  if latest_path is not null then
    delete from storage.objects
      where bucket_id = 'student-id-temp' and name = latest_path;
  end if;

  return new;
end;
$$;

-- SECURITY DEFINER 를 안 쓴다 — 이 UPDATE 를 실행하는 두 주체(FastAPI 의 service_role, Supabase
-- 대시보드의 postgres/superuser 연결) 모두 storage.objects 에 이미 충분한 권한이 있다(2026-09-19 설계).
create trigger student_verification_finalized
  after update of student_verification on public.profiles
  for each row
  execute function public.handle_student_verification_finalized();
```

- [ ] **Step 3: `rls_slice1_test.sql`에 pgTAP 추가** — 기존 파일 §4(service_role 블록) 뒤, §4c(auth.users 트리거) 앞에 삽입

```sql
-- 4d. 학생증 확정 시 사진 삭제 트리거 (postgres) -------------------------------

insert into storage.objects (bucket_id, name)
  values ('student-id-temp', '00000000-0000-0000-0000-0000000000aa/test.jpg');

set local role service_role;

select lives_ok(
  $$insert into public.student_verification_attempts (profile_id, file_path)
    values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000aa/test.jpg')$$,
  '학생증 시도 기록을 만든다'
);

select lives_ok(
  $$update public.profiles set student_verification = 'verified'
     where id = '00000000-0000-0000-0000-0000000000aa'$$,
  'service_role 이 학생증 인증 상태를 verified 로 바꾼다'
);

reset role;

select is_empty(
  $$select 1 from storage.objects
     where bucket_id = 'student-id-temp'
       and name = '00000000-0000-0000-0000-0000000000aa/test.jpg'$$,
  'verified 로 바뀌면 트리거가 학생증 사진을 지운다'
);
```

`select plan(35);`를 `select plan(38);`로 올리고(신규 3개), 기존 4b·4c 번호는 그대로 두고 4d를 그 사이에 끼워 넣는다(pgTAP은 번호가 아니라 실행 순서만 본다).

- [ ] **Step 4: 커밋** (`🗃️ db(slice1): 학과·학번 컬럼과 학생증 삭제 트리거 마이그레이션 초안 추가`) — **이 시점까지는 로컬 파일만, 클라우드 미적용**

---

### Task C2: GCP·Secret Manager 설정 (사용자 승인 후에만 실행)

**준비 완료 2026-09-20** — Vision API 사용 설정, 디스코드 웹훅 시크릿 등록까지는 사용자가 GCP 콘솔에서 직접 마쳤다(`backend/DEPLOY.md` §0 참조). **단, 실제 등록된 시크릿 이름은 `discord-review-webhook-url`이다** — 아래 초안 명령의 `discord-webhook-url`은 계획 작성 시점의 가칭이었고, 실제 배포 명령에는 `discord-review-webhook-url`을 쓴다. 남은 건 Cloud Run 서비스에 env/secret 연결(Step 3)과 `DEPLOY.md` 반영(Step 2)뿐이다.

**Files:**
- Modify: `backend/DEPLOY.md`

- [ ] **Step 1: 문서에 추가할 절차 정리**

```bash
gcloud services enable vision.googleapis.com

echo -n "<discord webhook url>" | gcloud secrets create discord-review-webhook-url --data-file=-

gcloud run services update campus-mate-backend \
  --region asia-northeast3 \
  --set-env-vars GOOGLE_CLOUD_PROJECT=<PROJECT_ID> \
  --set-secrets DISCORD_WEBHOOK_URL=discord-review-webhook-url:latest
```

Vision API는 Cloud Run 기본 컴퓨트 서비스 계정에 별도 IAM 역할이 필요 없다(API 활성화 + 유효한 ADC 자격으로 호출 가능, 리소스 단위 IAM 바인딩이 없는 API). 배포 후 `curl`로 실제 학생증 사진 한 장을 보내 Vision 호출이 402/403 없이 되는지 확인한다.

- [ ] **Step 2: `DEPLOY.md`에 위 절차를 §1·§2 사이에 추가**
- [ ] **Step 3: 위 명령을 사용자 승인 후 실제 실행**
- [ ] **Step 4: 커밋** (`📝 docs(deploy): Vision API·디스코드 웹훅 시크릿 등록 절차 추가`)

---

### Task C3: 클라우드 적용 (사용자 승인 후에만 실행)

- [ ] **Step 1: `list_migrations`로 현재 원격 상태 확인** — 특히 `20260914055631_revoke_rls_auto_enable_execute.sql`가 PR #32(`fix/revoke-trigger-execute`)와 같은 내용으로 이미 적용됐는지 먼저 확인, 적용됐다면 이 파일은 건너뛴다(중복 적용 방지)
- [ ] **Step 2: 나머지 5개 기존 마이그레이션 + Task C1의 신규 2개, 총 7개(또는 6개)를 `apply_migration`으로 순서대로 적용**(파일 내용 그대로, SUPABASE.md §4)
- [ ] **Step 3: `get_advisors`(security·performance)로 경고 0 확인**
- [ ] **Step 4: `supabase test db`로 `rls_slice1_test.sql` 실행 — 로컬 Docker 스택이 있으면.** 없으면(2026-09-13 결정대로 지금은 없음) 원격에서 직접 pgTAP을 돌리지 않고, Task C1의 새 케이스만 사용자가 스테이징 계정으로 수동 확인하는 것을 제안한다
- [ ] **Step 5: `docs/ERD.md` 상태줄 갱신** — 조각 1 적용 완료로 표시
- [ ] **Step 6: 커밋** (`📝 docs(erd): 조각 1 클라우드 적용 완료로 상태줄 갱신`)

---

## 완료 후

- Part A·B 커밋들을 `feat/slice1b-student-id-verification` 브랜치에 모아 push → draft PR (GIT.md §5.4)
- PR 본문에 Task A4 Step 2에서 뒤늦게 나온 `path_provider` 승인 필요 건을 명시
- Part C는 PR 리뷰·merge와 별개로, 사용자가 마이그레이션 적용을 승인하는 시점에 진행
