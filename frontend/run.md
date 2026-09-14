# 실행 방법

Supabase 키는 소스에 넣지 않고 실행할 때 주입한다.

## 개발 실행

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

## 테스트

```bash
flutter test
```

테스트는 키 없이 돌아간다. 네트워크에 붙는 코드는 테스트하지 않는다.

## 주의

`--dart-define` 값을 이 파일에 적지 않는다. 실제 키는 각자 로컬에 보관한다.

SUPABASE_ANON_KEY 에는 Supabase 대시보드의 publishable key(sb_publishable_…) 나 legacy anon key 어느 쪽을 넣어도 된다. 라이브러리 안에서 같은 자리다.
