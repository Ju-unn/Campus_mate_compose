-- 1.0.7 1-1 신분 고르기 + 신분 배지(사용자 결정 11-24 「대학생 · 대학원생 · 졸업생」, ERD §3 profiles, backend/DEPLOY.md §4 "신분 고르기 + 신분 배지 — DB + 서버", 브랜치 feat/academic-status-server).
-- 가입 3c 에서 고르고 15-6 에서 바꾼다(자유 선택, 확인 절차 없음). 카드 · 내 프로필의 "학교 인증" 배지 자리에 이 이름을 보인다.
-- null = 아직 안 고름 — 이미 가입한 사람 · 옛 앱(1.0.6)이다. 배지는 지금처럼 "학교 인증" 이다(사용자 「이미 가입해서 입력 안된 사람은 기본은 학교인증」).
-- 그래서 기존 줄은 채우지 않는다(백필 없음).
--
-- 칸과 제약은 do 블록 하나에 둔다(선례 20261123170000) — 잠금 시간 제한이 걸리고 반쪽 적용이 없다.
-- 잠금은 오래 기다리지 않는다(lock_timeout 5초) — 못 잡으면 아무것도 안 바뀐 채 실패하니 다시 적용하면 된다.
-- 기본값이 없는 null 칸 더하기라 표를 다시 쓰지 않는다.
--
-- 배포 순서: 이 파일 → 서버. 서버가 먼저 나가면 카드 · 내 프로필 select 의 academic_status 가 칸 없음으로 실패한다.
do $$
begin
  perform set_config('lock_timeout', '5s', true);

  alter table public.profiles add column academic_status text;

  alter table public.profiles
    add constraint profiles_academic_status_check
      check (academic_status in ('undergraduate', 'graduate_student', 'alumni'));
end;
$$;

comment on column public.profiles.academic_status is
  '신분(1.0.7 1-1): undergraduate 대학생 · graduate_student 대학원생 · alumni 졸업생. null = 아직 안 고름(이미 가입 · 옛 앱) — 배지는 "학교 인증". 쓰기는 서버(service_role)만';

-- RLS · grant 는 바꾸지 않는다. authenticated 의 표 select 는 정책 "profiles are readable by owner" 로 본인 줄만 보인다.
