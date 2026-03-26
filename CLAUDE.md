# $(project_name) - Claude AI 작업 가이드

## 프로젝트 정보
- **이름**: $(project_name)
- **카테고리**: [core/modules/experiments/archived/tools]
- **상태**: 🟢 활성 | 🟡 개발중 | 🔴 아카이브

## 폴더 구조
```
./
├─ src/         소스 코드 (수정 허용)
├─ tests/       테스트 (테스트 추가 권장)
├─ docs/        문서 (읽기 전용 권장)
├─ examples/    예제
├─ .claude/     메모리 (자동 관리)
└─ CLAUDE.md    이 파일
```

## 메모리 관리
- **메모리 위치**: `.claude/projects/$(project_name)/memory/`
- **MEMORY.md**: 프로젝트 진행 상황
- **규칙**:
  - 세션 간 정보 유지
  - 완료된 작업은 COMPLETED 파일로 아카이브
  - 다음 세션을 위해 액션 아이템 기록

## 커밋 규칙
- feat: 새 기능
- fix: 버그 수정
- docs: 문서 업데이트
- refactor: 코드 정리
- test: 테스트 추가

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>

## 다음 단계
[ ] 프로젝트 목표 정의
[ ] README.md 작성
[ ] 첫 테스트 추가
