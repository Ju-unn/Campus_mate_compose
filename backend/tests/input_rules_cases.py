"""앱 · 서버가 같이 쓰는 입력 검사 표(fixtures/input_rules_cases.json). 앱 시험은 frontend/test/common/input_rules_cases.dart 로 같은 파일을 읽는다."""
import json
from pathlib import Path

CASES = json.loads((Path(__file__).parent / "fixtures" / "input_rules_cases.json").read_text(encoding="utf-8"))
