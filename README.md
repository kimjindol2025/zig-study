# 🎓 Zig 전공 과정

> **기록이 증명이다** - Your record is your proof.

Zig의 철학을 배우고 실습하는 전공 수준의 학습 프로젝트입니다.

## 📖 학습 과정

### Zig 전공 101: 기초

#### **1-1. Hello, Zig! (설치와 첫 컴파일)** ✅ 완성

#### **1-2. 변수, 상수, 그리고 엄격한 타입 시스템** ✅ 완성

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

### **1-2. 변수, 상수, 그리고 엄격한 타입 시스템** ✅ 완성

**학습 목표**:
- Zig의 가변성(Mutability) 이해
- 정적 타입과 명시적 캐스팅
- 정수 오버플로우 방지
- undefined 값의 명시적 관리

**Zig의 핵심 철학**:
```
"명시적인 상태 관리"
컴파일러가 여러분의 의도를 완벽히 파악할 수 있도록 설계해야 한다.
```

**주요 개념**:

1. **가변성의 엄격함**
   ```zig
   const current_age: i32 = 26;      // 상수 (기본값)
   var books_to_read: i32 = 12;      // 변수 (명확한 이유 필요)

   // current_age = 27;              // ❌ 컴파일 에러!
   books_to_read += 1;               // ✅ 정상 작동
   ```
   - **const**: 불변 (기본값, 모든 선언은 const여야 함)
   - **var**: 변수 (값이 변경될 필요가 있을 때만)

2. **정적 타입과 명시적 캐스팅**
   ```zig
   const small_int: i8 = 127;        // -128 ~ 127
   const unsigned: u8 = 255;          // 0 ~ 255
   const regular: i32 = 2147483647;   // -2^31 ~ 2^31-1

   // 명시적 캐스팅
   const larger: i64 = @intCast(regular);  // i32 → i64
   ```
   - 정수 타입: i8, u8, i32, u32, i64, u64 등
   - 자동 타입 변환 금지 (명시적 `@intCast()` 필수)

3. **정수 오버플로우 방지**
   ```zig
   const max: u8 = 255;

   const wrapped: u8 = max +% 1;      // Wrapping: 0으로 감싸짐
   const saturated: u8 = max +| 10;   // Saturation: 최댓값 유지

   // max + 1 → ❌ 컴파일 에러!
   ```
   - `+`: 기본 덧셈 (오버플로우 감지)
   - `+%`: Wrapping 덧셈 (0부터 재시작)
   - `+|`: Saturation 덧셈 (최댓값 유지)

4. **undefined 값의 명시적 관리**
   ```zig
   var x: i32 = undefined;  // 명시적으로 미초기화 표기
   x = 100;                  // 이제 안전하게 사용
   ```
   - 미초기화 변수는 명시적으로 `undefined` 할당 필수
   - undefined 상태의 값을 읽으면 런타임 에러 발생

**Assignment 1-2 완성 목록**:
- ✅ 변수 선언: 현재 나이 (const), 올해 읽을 책 권수 (var)
- ✅ 연산 실험: 책 권수에 1을 더하기
- ✅ 타입 오류 유도: u8에 300 할당 시 컴파일 에러 분석
- ✅ 오버플로우 방지: +%, +| 연산자 실습
- ✅ undefined 관리: 미초기화 값의 명시적 표기
- ✅ 단위 테스트: 8가지 타입 시스템 검증

---

## 🚀 사용 방법

### 메인 프로그램 실행 (1-1)
```bash
zig build run
```

### Lesson 1-2 실행 (변수와 타입 시스템)
```bash
zig build run-1-2
```

### Lesson 1-3 실행 (제어문)
```bash
zig build run-1-3
```

### Lesson 1-4 실행 (함수와 에러 핸들링)
```bash
zig build run-1-4
```

### Lesson 1-5 실행 (구조체와 메서드)
```bash
zig build run-1-5
```

### Lesson 1-6 실행 (포인터와 메모리 관리)
```bash
zig build run-1-6
```

### Lesson 1-7 실행 (배열과 슬라이스)
```bash
zig build run-1-7
```

### Lesson 1-8 실행 (열거형과 태그된 공용체)
```bash
zig build run-1-8
```

### Lesson 1-9 실행 (할당자)
```bash
zig build run-1-9
```

### Lesson 1-10 실행 (Comptime)
```bash
zig build run-1-10
```

### Lesson 1-11 실행 (C 호환성)
```bash
zig build run-1-11
```

### Lesson 1-12 실행 (멀티스레딩)
```bash
zig build run-1-12
```

### Lesson 1-13 실행 (대규모 시스템 아키텍처)
```bash
zig build run-1-13
```

### Lesson 2-1 실행 (고성능 네트워크 프로그래밍)
```bash
zig build run-2-1
```

### 모든 테스트 실행
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
- **1-2**: 변수, 상수, 그리고 엄격한 타입 시스템 ✅
- **1-3**: 제어문 - if, while, for 그리고 특별한 switch ✅
- **1-4**: 함수(Functions)와 에러 핸들링의 기초 ✅
- **1-5**: 구조체(Structs)와 메서드 ✅
- **1-6**: 포인터(Pointers)와 메모리 관리 ✅
- **1-7**: 배열(Arrays)과 슬라이스(Slices) - 메모리 안전의 파수꾼 ✅
- **1-8**: 열거형(Enums)과 태그된 공용체(Tagged Unions) - 상태 설계의 정석 ✅
- **1-9**: 할당자(Allocators) - 힙 메모리의 명시적 제어 ✅
- **1-10**: Comptime - 컴파일 타임에 실행되는 코드 ✅

### Zig 전공 201 (고급)
- **1-11**: C 호환성(C Interoperability) - 기존 유산과의 완벽한 결합 ✅
- **1-12**: 멀티스레딩(Multi-threading)과 원자적 연산(Atomics) ✅
- **1-13**: 대규모 시스템 아키텍처 - 3계층 설계의 정석 ✅ 🎓 **전공 101, 201 완성!**
- **2-1**: 고성능 네트워크 프로그래밍 (TCP/UDP) ✅ 🔥 **201 시작!**
- **2-2**: 데이터베이스 드라이버 연동 및 SQL 인터페이스 설계 📅
- **2-3**: 고성능 알고리즘과 SIMD 최적화 📅

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
2026년 2월 26일 - **Zig 전공 101, 201 완성!** 🎓 (Lesson 1-13: 대규모 시스템 아키텍처)
2026년 2월 26일 - **Zig 전공 201 실전 시작!** 🚀 (Lesson 2-1: 고성능 네트워크 프로그래밍)
