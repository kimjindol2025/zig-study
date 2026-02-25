# 🎓 Zig 전공 과정

> **기록이 증명이다** - Your record is your proof.

Zig의 철학을 배우고 실습하는 전공 수준의 학습 프로젝트입니다.

## 📖 학습 과정

### Zig 전공 101: 기초

#### **1-1. Hello, Zig! (설치와 첫 컴파일)** ✅ 완성

**학습 목표**:
- Zig 개발 환경 구축
- 프로젝트 초기화 (`zig init`)
- Hello World 프로그램 작성
- 빌드 및 실행 (`zig build run`)

**Zig의 핵심 철학**:
```
"숨겨진 제어 흐름이 없다"
모든 메모리 할당과 오류 처리는 명시적이어야 한다.
```

**주요 개념**:

1. **Hello World 분석**
   ```zig
   const std = @import("std");

   pub fn main() !void {
       const stdout = std.io.getStdOut().writer();
       try stdout.print("Hello, Zig!\n", .{});
   }
   ```
   - `const std = @import("std")`: 표준 라이브러리 임포트
   - `pub fn main() !void`: 메인 진입점 (! = 오류 가능)
   - `try` 키워드: 오류 처리 명시
   - `.{}`: 포맷 인자

2. **Zig Build System (build.zig)**
   - Makefile, CMake와 달리 Zig 코드로 작성
   - 빌드 로직이 명확하고 커스터마이징 가능
   - `zig build run`: 컴파일 후 즉시 실행

3. **comptime의 마법** (다음 수업 예고)
   - 컴파일 시점에 코드 실행
   - 제네릭 구현 (복잡한 문법 없음)
   - 메타프로그래밍

**프로젝트 구조**:
```
zig-study/
├── build.zig           # Zig 빌드 스크립트
├── src/
│   ├── main.zig        # 메인 진입점
│   └── root.zig        # 라이브러리 루트
└── README.md           # 이 파일
```

**Assignment 1-1 완성 목록**:
- ✅ 환경 구축 (zig version 확인)
- ✅ 프로젝트 초기화 (`zig init` 패턴)
- ✅ Hello World 분석
- ✅ src/main.zig 수정 (학번 + "학습 시작" 메시지)
- ✅ 프로그램 실행 (zig build run)

---

## 🚀 사용 방법

### 프로그램 실행
```bash
zig build run
```

### 테스트 실행
```bash
zig build test
```

### 프로그램만 빌드
```bash
zig build
```

---

## 📝 학습 로드맵

### Zig 전공 101 (기초)
- **1-1**: Hello, Zig! (설치와 첫 컴파일) ✅
- **1-2**: 변수, 상수, 그리고 엄격한 타입 시스템 📅
- **1-3**: 함수와 제어 흐름 📅

### Zig 전공 201 (고급)
- **2-1**: 메모리와 포인터의 명시적 관리 📅
- **2-2**: 에러 처리와 Error Set 📅
- **2-3**: 구조체와 열거형 (Type System) 📅

### Zig 전공 301 (실무)
- **3-1**: 제네릭 프로그래밍 (comptime) 📅
- **3-2**: 고성능 알고리즘 (SIMD, 벤치마킹) 📅
- **3-3**: 실제 프로젝트 구현 📅

---

## 🎓 주요 개념

### Zig의 철학

1. **명시성 (Explicitness)**
   - 숨겨진 제어 흐름 금지
   - 모든 메모리 할당 명시
   - 오류 처리 명시

2. **안전성 (Safety)**
   - 강타입 (Type System)
   - 범위 검사 (Bounds Checking)
   - 정의되지 않은 행동 방지

3. **성능 (Performance)**
   - C 수준의 성능
   - 컴파일 타임 최적화 (comptime)
   - SIMD 지원

---

## 📚 참고 자료

- 공식 문서: https://ziglang.org/
- Zig 학습 가이드: https://ziglang.org/learn/
- 커뮤니티: https://discord.gg/gxD46H7

---

## 🎯 Assignment 1-1 검증

**출력 예상**:
```
🎓 Zig 전공 과정 시작!
학번: CLU-2026-ZIG-001
📝 Assignment 1-1: Hello, Zig! (설치와 첫 컴파일)

═══════════════════════════════════════════════════════════
Hello, Zig Graduate School!
═══════════════════════════════════════════════════════════

📚 오늘의 학습:
  1️⃣ 환경 구축 (Laboratory Setup)
  ...
✅ 프로그램 실행 성공!
기록이 증명이다 - Zig 학습을 시작합니다.
```

**검증 체크리스트**:
- ✅ 프로그램이 컴파일됨
- ✅ 학번 (CLU-2026-ZIG-001) 출력됨
- ✅ "학습 시작" 관련 메시지 출력됨
- ✅ 오류 없이 정상 종료됨

---

**기록이 증명이다** - Zig 전공을 시작합니다! 🦎

2026년 2월 26일 - Assignment 1-1 완성
