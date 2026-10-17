-- FAQ 5개를 학생증 · 졸업증명서 인증 제거와 수도권 학교 확대에 맞춘다(2026-10-17 사용자 승인 "문구적용해").
-- 학생증 단계가 없어져(서버 PR #582 · 앱 PR #583) 실명을 받지 않고, 가입 가능 학교가 서울권 20곳에서
-- 서울 · 경기 · 인천 대학교와 사이버대 · 방송통신대 일부(65곳)로 늘었다.
--   ① account "누가 가입할 수 있나요?" — 학생증 확인 문장 · "서울권 일부 대학" 을 새 사실로
--   ② account "학생증 확인은 어떻게 하나요?" → 질문과 답을 "학교 인증은 어떻게 하나요?" 로
--   ③ photo_profile "실명은 왜 받나요?" → "실명을 받나요?" 받지 않는다로
--   ④ photo_profile "상대 이름 대신 닉네임만 보이는 이유는?" — 학생증 확인 문장을 뺀다
--   ⑤ account "알림이 오지 않아요." — 묶어 보내는 알림 목록에서 "학생증 결과" 를 뺀다(replace, 나머지 문장은 그대로)
-- 질문으로 찾는다 — id 는 운영과 로컬이 다르다. 이미 바꾼 뒤 다시 돌려도 결과가 같다(①~④ 는 같은 값을 다시 쓰고,
-- ⑤ 는 옛 구절이 없으면 그대로). 그대로 두는 FAQ: 추가 카드의 "흐리게 처리한 아바타"(유료 카드 미리보기는 여전히 흐림),
-- "상대에게 내 프로필이 어떻게 보이나요?" 의 "실명 · 전화번호 … 는 보이지 않아요"(여전히 사실).
-- 시험: supabase/tests/faq_test.sql (문항 수 · 카테고리 규칙은 바뀌지 않는다).

update public.faq
set answer = '카카오, 구글, Apple 계정으로 로그인한 뒤(Apple은 아이폰에서만), 등록된 학교 메일로 한 번 인증하면 가입할 수 있어요. '
             || '졸업생도 학교 메일을 쓸 수 있으면 가입할 수 있어요. '
             || '태어난 해 기준으로 만 19세가 되는 해부터 가입할 수 있어요(2026년에는 2007년생부터). '
             || '지금은 서울·경기·인천 지역 대학교와 사이버대·방송통신대 일부만 가입할 수 있어요.',
    updated_at = now()
where category = 'account'
  and question = '누가 가입할 수 있나요? 재학생이 아니어도 되나요?';

update public.faq
set question = '학교 인증은 어떻게 하나요?',
    answer = '학교 메일로 받은 6자리 인증번호를 넣으면 끝나요. 학생증이나 졸업증명서는 받지 않아요. '
             || '우리 학교가 없으면 문의 메일로 알려 주세요.',
    updated_at = now()
where category = 'account'
  and question in ('학생증 확인은 어떻게 하나요?', '학교 인증은 어떻게 하나요?');

update public.faq
set question = '실명을 받나요?',
    answer = '받지 않아요. 앱 어디서나 닉네임으로만 표시돼요.',
    updated_at = now()
where category = 'photo_profile'
  and question in ('실명은 왜 받나요?', '실명을 받나요?');

update public.faq
set answer = '앱은 실명을 받지 않아서 어디서나 닉네임으로만 표시돼요. 닉네임은 한글·영문 2~5자이고 다른 사람과 겹칠 수 없어요.',
    updated_at = now()
where category = 'photo_profile'
  and question = '상대 이름 대신 닉네임만 보이는 이유는?';

update public.faq
set answer = replace(answer, '받은 신청·매칭·지인 리뷰·학생증 결과 알림은', '받은 신청·매칭·지인 리뷰 알림은'),
    updated_at = now()
where category = 'account'
  and question = '알림이 오지 않아요.'
  and answer like '%학생증 결과%';
