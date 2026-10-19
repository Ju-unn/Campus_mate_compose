-- 졸업생 인증(졸업증명서) 1/2: 프로필 칸 2개 · 신청 표 · 사진 임시 버킷.
-- 계획서 docs/superpowers/plans/2026-10-19-graduate-verification.md Task 1 (대장 결정 D2~D16, 사용자 10-19 "출시 전에 넣는다").
-- 졸업생은 학교 메일이 없어 사진 한 장으로 인증받는다. 승인되면 학교 메일 사람과 같은 상태(university_id ·
-- school_email_verified_at)가 되어 가입 관문 · 온보딩 · 매칭이 코드 변경 없이 똑같이 돈다(함수는 다음 파일).
-- 배포 순서: 이 파일 → 다음 파일 → 서버. 서버가 먼저 나가면 프로필 칸 읽기(verification_method)가 칸 없음으로 실패한다.
-- 시험: supabase/tests/graduate_verification_test.sql · rls_slice0_test.sql(권한 목록)

-- 1. 프로필 칸.
--    verification_method: 가입 때 고른 인증 길(null = 아직 안 고름 = 학교 메일로 간주 — 옛 앱 호환). 앱 안 선택만으로는 쓰지 않고
--      [다음] 을 누를 때 서버가 쓴다. 승인 뒤에는 서버가 바꾸지 못한다(인증 뒤 변경 금지).
--    graduate_verified_at: 졸업생 인증으로 통과한 시각(내부 칸, 다른 사람에게 보이지 않는다 — D2).
alter table public.profiles
  add column verification_method text,
  add column graduate_verified_at timestamptz,
  add constraint profiles_verification_method_check
    check (verification_method in ('school_email', 'graduate_certificate')),
  -- 졸업생 승인은 학교 메일 인증과 같은 두 칸을 채운다 — 졸업생 표시만 있고 인증 시각이 없는 모양은 만들 수 없다.
  add constraint profiles_graduate_verified_requires_school_email
    check (graduate_verified_at is null or school_email_verified_at is not null);

comment on column public.profiles.verification_method is
  '가입 인증 길: school_email | graduate_certificate | null(미선택 = 학교 메일). FastAPI PUT /me/verification-method 가 쓴다';
comment on column public.profiles.graduate_verified_at is
  '졸업생 인증(졸업증명서)으로 통과한 시각. 승인 함수가 school_email_verified_at 과 같이 채운다. 내부 칸 — 표시하지 않는다';

-- 2. 신청 표. 사진과 평문(OCR 번호 · OCR 학교 글자 · 이전 학교 메일)은 결정(승인 · 반려 · 취소 · 만료)을 한 순간 지운다.
--    남는 것: 학교, 결정, 시각, 해시(bytea)뿐. 이름 · 학번 · 생년월일은 어디에도 저장하지 않는다(학번은 해시로만).
create table public.graduate_verification_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending',
  -- 반려 사유(관리자가 고르는 코드) 또는 취소 이유. 문구는 앱 · 푸시 · 관리자 웹이 같은 코드를 같은 글자로 바꾼다.
  reason text,
  -- 비공개 버킷 graduate-cert-temp 의 경로. 결정 즉시 서버가 파일을 지우고 비운다 — 못 지웠으면 매시 배치가 다시 지운다.
  photo_path text,
  -- 서버 글자 인식 결과. 관리자 화면 미리 채우기와 중복 경고에만 쓴다(자동 승인에는 쓰지 않는다).
  ocr_state text not null,
  ocr_document_number text,
  ocr_school_text text,
  -- 선택 입력. 읽기 전용 중복 점검에만 쓰고 school_email_claims · signup_blocks 에는 쓰지 않는다.
  previous_school_email text,
  -- HMAC(키 identity_hmac_key, 이름공간 접두사로 학교 메일 해시와 겹치지 않음). document_hmac 은 신청 때 OCR 번호로 미리 계산해 둘 수 있고
  -- 승인 때 관리자가 확인한 번호의 해시로 바뀐다. student_hmac 은 승인 때 관리자가 학번을 넣었을 때만 있다.
  document_hmac bytea,
  student_hmac bytea,
  key_version smallint not null default 1,
  university_id uuid references public.universities (id) on delete restrict,
  -- 신청 화면의 동의 줄을 누른 시각(D11). 서버가 신청 때 한 번 채운다.
  consented_at timestamptz not null default now(),
  -- FK 없음(admin_actions 와 같다) — 관리자 auth 계정이 지워져도 누가 결정했는지는 남는다.
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),

  constraint graduate_requests_status_check check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  constraint graduate_requests_ocr_state_check check (ocr_state in ('read', 'nothing_found', 'failed')),
  constraint graduate_requests_previous_email_length check (previous_school_email is null or char_length(previous_school_email) <= 254),
  -- 상태쌍: 칸마다 따로 믿지 않고 상태별로 있어야 할 것 · 없어야 할 것을 한 곳에서 고정한다.
  -- 사유가 비면 `in` 이 null 이라 check 를 그냥 통과하므로 `reason is not null` 을 같이 둔다.
  constraint graduate_requests_state_pairs check (
    case status
      when 'pending' then reason is null and decided_by is null and decided_at is null and university_id is null
                          and photo_path is not null
      when 'approved' then reason is null and university_id is not null and document_hmac is not null
                           and decided_by is not null and decided_at is not null
      when 'rejected' then reason is not null
                           and reason in ('unreadable', 'not_certificate', 'unverifiable', 'school_unsupported')
                           and decided_by is not null and decided_at is not null
      when 'cancelled' then reason is not null
                            and reason in ('switched', 'expired', 'verified_otherwise', 'account_withdrawn')
                            and decided_by is null and decided_at is not null
    end
  ),
  -- 결정된 줄에는 평문이 없다(승인 · 반려 · 취소 · 만료 공통). 서버가 깜빡해도 DB 가 거부한다.
  constraint graduate_requests_no_plaintext_after_decision check (
    status = 'pending'
    or (ocr_document_number is null and ocr_school_text is null and previous_school_email is null)
  ),
  -- 학번 해시는 관리자가 승인할 때만 생긴다.
  constraint graduate_requests_student_hmac_only_approved check (student_hmac is null or status = 'approved')
);

comment on table public.graduate_verification_requests is
  '졸업생 인증 신청(졸업증명서 사진). FastAPI 전용, 클라이언트 접근 없음. 결정 즉시 사진 · 평문(OCR 번호 · 학교 글자 · 이전 학교 메일)을 비우고 해시만 남긴다';

-- 프로필당 대기는 하나. 거의 동시에 낸 두 번째는 23505 → 서버 409.
create unique index graduate_requests_one_pending_key
  on public.graduate_verification_requests (profile_id) where status = 'pending';
-- 같은 증명서를 두 계정에(문서 해시) · 같은 사람이 두 계정에(학번 해시) 쓰는 것을 막는다. 반려 · 취소된 줄은 겹쳐도 된다.
create unique index graduate_requests_document_approved_key
  on public.graduate_verification_requests (document_hmac) where status = 'approved';
create unique index graduate_requests_student_approved_key
  on public.graduate_verification_requests (student_hmac) where status = 'approved';
-- 관리자 목록(오래된 순)과 14일 만료 배치가 대기 줄만 훑는다.
create index graduate_requests_pending_created_at_index
  on public.graduate_verification_requests (created_at) where status = 'pending';
-- 프로필별 최근 신청(시도 횟수 · 지난 신청 기록) 조회와 탈퇴 cascade.
create index graduate_requests_profile_created_at_index
  on public.graduate_verification_requests (profile_id, created_at desc);
-- FK 칸 인덱스 관례(school_email_claims_university_id_index 와 같다). 학교를 지우려 할 때 restrict 검사가 표를 훑지 않는다.
create index graduate_requests_university_id_index
  on public.graduate_verification_requests (university_id) where university_id is not null;

-- RLS: 정책 없음 = 클라이언트는 자기 신청도 읽지 못한다(school_email_claims 와 같다). 상태는 FastAPI 가 내려준다.
alter table public.graduate_verification_requests enable row level security;

revoke all on table public.graduate_verification_requests from anon, authenticated, service_role;
grant select, insert, update, delete on table public.graduate_verification_requests to service_role;

-- 3. 사진 임시 버킷. 다른 버킷처럼 클라이언트용 storage.objects 정책은 없다 — FastAPI 가 service_role 로 올리고 지운다.
--    student-id-temp 와 따로 둔다: 그 버킷에는 옛 학생증 사진이 남아 있을 수 있고 "사용자 승인 뒤 삭제" 대기 중이다.
--    버킷 제한은 신고된 content type · 크기로만 막으므로 파일 내용(매직 바이트)은 FastAPI 가 올리기 전에 본다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('graduate-cert-temp', 'graduate-cert-temp', false, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
