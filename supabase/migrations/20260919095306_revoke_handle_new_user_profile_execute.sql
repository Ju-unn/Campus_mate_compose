-- Advisor 0028/0029 WARN 정리: SECURITY DEFINER 함수가 anon·authenticated 에 RPC 로 노출됨.
-- 트리거 전용 함수라 실제로 불릴 일은 없지만(트리거는 함수 소유자 권한으로 돎, 이 revoke 와 무관),
-- RPC 표면을 줄여 lint 를 끄고 방어선을 하나 더 둔다.
revoke execute on function public.handle_new_user_profile() from anon, authenticated, public;
