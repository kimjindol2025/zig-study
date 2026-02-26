# 🗺️ Zig Syntax Grand Map (전공 101 완전 정리)

> **기록이 증명이다** - Zig의 모든 문법을 한 장에 담다

---

## 📋 개요

Zig는 "숨겨진 제어 흐름이 없다"는 철학 아래, 문법의 수를 극도로 줄이면서도 강력한 표현력을 제공합니다. 이 문서는 Zig 전공 101 (1-1 ~ 1-5)의 모든 핵심 개념을 체계적으로 정리한 **완전 리퍼런스**입니다.

---

## 1️⃣ 선언과 타입 (Declarations & Types)

### 기본 선언

| 키워드 | 설명 | 예제 |
|--------|------|------|
| **const** | 불변 상수 (기본값) | `const x: i32 = 10;` |
| **var** | 가변 변수 (명확한 이유 필요) | `var y: i32 = 20; y = 30;` |
| **undefined** | 명시적 미초기화 | `var z: i32 = undefined; z = 5;` |

### 정수 타입 (Integer Types)

```
부호 있음 (Signed):    i8, i16, i32, i64, i128
부호 없음 (Unsigned):  u8, u16, u32, u64, u128
```

| 타입 | 범위 | 예제 |
|------|------|------|
| **i8** | -128 ~ 127 | `const small: i8 = -42;` |
| **u8** | 0 ~ 255 | `const byte: u8 = 255;` |
| **i32** | -2³¹ ~ 2³¹-1 | `const regular: i32 = 100;` |
| **u32** | 0 ~ 2³²-1 | `const count: u32 = 1000;` |
| **i64** | -2⁶³ ~ 2⁶³-1 | `const big: i64 = 9999999999;` |

### 부동 소수점 타입

```
f16 (16-bit), f32 (32-bit), f64 (64-bit), f128 (128-bit)
```

| 타입 | 예제 |
|------|------|
| **f32** | `const pi: f32 = 3.14;` |
| **f64** | `const precise: f64 = 3.14159265359;` |

### 특수 타입

| 타입 | 설명 | 예제 |
|------|------|------|
| **bool** | 참/거짓 | `const active: bool = true;` |
| **void** | 값이 없음 | `fn noReturn() void { }` |
| **noreturn** | 절대 반환 안 함 | `fn exit() noreturn { while(true){} }` |
| **type** | 타입 자체를 값으로 | `const T: type = i32;` |

### 타입 추론과 캐스팅

```zig
const a = @as(i32, 5);              // 명시적 지정
const b: i32 = 10;                  // 타입 선언
const c = b;                         // 타입 자동 추론

const smaller: i32 = 100;
const larger: i64 = @intCast(smaller);  // 명시적 캐스팅
```

### 오버플로우 처리

```zig
const max: u8 = 255;
const wrapped: u8 = max +% 1;       // Wrapping: 0
const saturated: u8 = max +| 10;    // Saturation: 255
// const error: u8 = max + 1;       // ❌ 컴파일 에러!
```

---

## 2️⃣ 제어 흐름 (Control Flow)

### if 문 (표현식)

```zig
// if를 표현식으로 사용하여 값 할당
const grade = if (score >= 90)
    "A"
else if (score >= 80)
    "B"
else
    "C";

// if 블록
if (score >= 60) {
    std.debug.print("Pass\n", .{});
} else {
    std.debug.print("Fail\n", .{});
}
```

### while 루프

```zig
// 조건 반복
var counter: u32 = 0;
while (counter < 10) : (counter += 1) {
    // : (counter += 1)은 continue 시 실행
    std.debug.print("{}\n", .{counter});
}

// 무한 루프
while (true) {
    if (shouldBreak) break;
    // 작업 수행
}
```

### for 루프 (배열 순회)

```zig
const items = [_]i32{ 10, 20, 30 };

// 요소만 순회
for (items) |item| {
    std.debug.print("{}\n", .{item});
}

// 인덱스와 함께 순회
for (items, 0..) |item, idx| {
    std.debug.print("Index {}: {}\n", .{ idx, item });
}

// 두 배열 동시 순회
const a = [_]i32{ 1, 2, 3 };
const b = [_]i32{ 10, 20, 30 };
for (a, b) |av, bv| {
    std.debug.print("{} + {} = {}\n", .{ av, bv, av + bv });
}
```

### switch 문 (전수 검사 필수)

```zig
// 기본 switch
const status = 2;
const message = switch (status) {
    1 => "준비 중",
    2 => "진행 중",
    3 => "완료",
    else => "알 수 없음",  // 필수!
};

// 다중 케이스
const parity = switch (number) {
    1, 3, 5, 7, 9 => "홀수",
    2, 4, 6, 8 => "짝수",
    else => "범위 초과",
};

// ❌ 주의: else를 생략하면 컴파일 에러!
// 모든 경우를 처리해야 함
```

### break와 continue

```zig
// break: 루프 탈출
while (true) {
    if (shouldExit) break;
}

// continue: 다음 반복으로
for (items) |item| {
    if (item == skipValue) continue;
    // 처리 로직
}
```

### 블록 식 (Block Expression)

```zig
// 레이블이 있는 블록
const result = blk: {
    var sum: i32 = 0;
    for (items) |item| {
        sum += item;
    }
    break :blk sum;  // 블록의 결과값 반환
};

// 조건부 블록
const value = if (condition) blk: {
    // 복잡한 로직
    break :blk computedValue;
} else blk: {
    // 다른 로직
    break :blk defaultValue;
};
```

---

## 3️⃣ 함수와 에러 처리 (Functions & Errors)

### 함수 선언

```zig
// 기본 함수
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// 매개변수는 기본적으로 const (불변)
fn printValue(x: i32) void {
    // x = 10;  // ❌ 컴파일 에러!
    std.debug.print("{}\n", .{x});
}

// pub: 외부 모듈에서 접근 가능
pub fn publicAPI() i32 {
    return 42;
}

// 프라이빗 함수 (이 파일 내에서만 사용)
fn internalHelper() void { }
```

### 에러 처리

```zig
// 에러 세트 정의
const FileError = error{
    NotFound,
    AccessDenied,
    PermissionDenied,
};

// 에러를 반환하는 함수
fn openFile(path: []const u8) FileError!void {
    if (path.len == 0) {
        return FileError.NotFound;
    }
    // 파일 열기 로직
}

// 에러 처리 방법 1: try (에러 발생 시 즉시 리턴)
const result = try openFile("test.txt");

// 에러 처리 방법 2: catch (기본값 제공)
const safe = try openFile("file.txt") catch |err| {
    std.debug.print("Error: {}\n", .{err});
    0
};

// 에러 처리 방법 3: if 패턴
if (openFile("file.txt")) |success| {
    std.debug.print("성공\n", .{});
} else |err| {
    std.debug.print("실패: {}\n", .{err});
}
```

### defer와 errdefer

```zig
// defer: 스코프 종료 직전에 실행 (에러 발생 시에도)
fn useResource() !void {
    std.debug.print("1. 리소스 확보\n", .{});
    defer std.debug.print("3. 리소스 해제\n", .{});  // 항상 실행됨

    std.debug.print("2. 작업 수행\n", .{});
}

// errdefer: 에러 발생 시에만 실행
fn riskyOperation() !void {
    const resource = try allocate();
    errdefer deallocate(resource);  // 에러 발생 시만 실행

    try process(resource);
}
```

---

## 4️⃣ 구조화와 메모리 (Structures & Memory)

### 구조체 (Struct)

```zig
// 구조체 정의
const Student = struct {
    name: []const u8,
    score: u32,
    is_active: bool = true,  // 기본값

    // 메서드 (self: Type = read-only)
    pub fn isPassed(self: Student) bool {
        return self.score >= 60;
    }

    // 수정 가능 메서드 (self: *Type)
    pub fn updateScore(self: *Student, newScore: u32) void {
        self.score = newScore;
    }

    // 정적 메서드 (self 없음)
    pub fn init(name: []const u8, score: u32) Student {
        return Student{
            .name = name,
            .score = score,
        };
    }
};

// 구조체 사용
const student = Student.init("철학", 85);
const passed = student.isPassed();
```

### 열거형 (Enum)

```zig
const Color = enum {
    Red,
    Green,
    Blue,

    pub fn toHex(self: Color) []const u8 {
        return switch (self) {
            .Red => "#FF0000",
            .Green => "#00FF00",
            .Blue => "#0000FF",
        };
    }
};

const favorite = Color.Red;
```

### 포인터 (Pointers)

```zig
// 싱글 아이템 포인터
var x: i32 = 10;
const ptr: *i32 = &x;      // 주소 가져오기
ptr.* = 20;                // 역참조로 값 수정
const value = ptr.*;       // 역참조로 값 읽기

// 다중 아이템 포인터 (배열 포인터)
var arr = [_]i32{ 1, 2, 3 };
const arrayPtr: [*]i32 = &arr;
arrayPtr[0] = 10;          // 배열처럼 접근
```

### 슬라이스 (Slice)

```zig
const items = [_]i32{ 10, 20, 30, 40, 50 };

// 슬라이스 (포인터 + 길이)
const slice: []const i32 = items[1..4];  // [20, 30, 40]
const first = slice[0];                  // 20

// 슬라이스는 동적으로 부분 배열 참조
for (slice) |item| {
    std.debug.print("{}\n", .{item});
}
```

### Optional 타입 (Nullable)

```zig
// Optional 타입: null 허용
const maybe_value: ?i32 = 42;
const maybe_null: ?i32 = null;

// if 패턴으로 Optional 처리
if (maybe_value) |value| {
    std.debug.print("Value: {}\n", .{value});
} else {
    std.debug.print("No value\n", .{});
}

// orelse로 기본값 제공
const safe_value = maybe_value orelse 0;
```

---

## 5️⃣ Zig만의 특수 병기 (Meta-programming)

### comptime (컴파일 타임 실행)

```zig
// 컴파일 타임에 값 계산
const BUFFER_SIZE = comptime blk: {
    var size: usize = 1024;
    size *= 2;  // 컴파일 타임에 계산
    break :blk size;
};

// comptime 함수: 컴파일 타임에만 호출 가능
fn fibonacci(comptime n: u32) u32 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

const fib10 = fibonacci(10);  // 컴파일 타임 계산
```

### inline (인라인 강제)

```zig
// inline 함수: 컴파일러가 반드시 인라인화
inline fn add(a: i32, b: i32) i32 {
    return a + b;
}

// inline for: 루프를 펼침
inline for (0..3) |i| {
    // 컴파일 타임에 전개됨
    std.debug.print("Iteration {}\n", .{i});
}
```

### @import와 내장 함수

```zig
// 라이브러리 불러오기
const std = @import("std");

// 타입 변환
const small: i32 = 100;
const large: i64 = @intCast(small);

// 포인터 캐스팅
const as_u8_ptr: *const u8 = @ptrCast(&x);

// 크기 계산
const size = @sizeOf(i32);  // 4 (bytes)
const align = @alignOf(i64);  // 8

// 타입 정보
const type_name = @typeName(i32);  // "i32"
```

---

## 6️⃣ 문법 간의 관계도 (Logic Flow)

```
┌─────────────────────────────────────────────────┐
│         Zig의 핵심 설계 철학                      │
│  "숨겨진 제어 흐름이 없다"                      │
└─────────────────────────────────────────────────┘
          ↓           ↓           ↓
    ┌─────────────┬──────────┬──────────────┐
    │             │          │              │
    ▼             ▼          ▼              ▼
┌────────┐  ┌────────┐  ┌────────┐  ┌────────────┐
│선언과   │  │제어    │  │함수와  │  │구조화와    │
│타입    │→│흐름    │→│에러    │→│메모리     │
│        │  │        │  │처리    │  │           │
└────────┘  └────────┘  └────────┘  └────────────┘
│           │          │              │
└─const/var─┴if/while ─┴try/catch ────┴struct/enum─
  type safety  무조건   명시적         조합
              처리     안전성


                    ↓
    ┌──────────────────────────────┐
    │   comptime & inline          │
    │   (메타프로그래밍)           │
    │   - 컴파일 타임 실행         │
    │   - 타입 생성                │
    │   - 제네릭 구현              │
    └──────────────────────────────┘
                    ↓
        대규모 시스템 설계에서
        강력한 안전판 역할
```

---

## 7️⃣ 중요한 패턴들 (Essential Patterns)

### init 패턴 (생성자)

```zig
const Point = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Point {
        return Point{ .x = x, .y = y };
    }
};

const p = Point.init(10, 20);
```

### deinit 패턴 (정리)

```zig
const Resource = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Resource {
        return Resource{
            .data = try allocator.alloc(u8, 100),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Resource) void {
        self.allocator.free(self.data);
    }
};

// 사용
var resource = try Resource.init(allocator);
defer resource.deinit();
```

### Error Handling 패턴

```zig
// 방법 1: try (에러 전파)
const value = try riskyOperation();

// 방법 2: catch (기본값)
const safe = riskyOperation() catch 0;

// 방법 3: if 패턴 (구분)
if (riskyOperation()) |value| {
    // 성공
} else |err| {
    // 실패
}
```

---

## 📊 완전 체크리스트

### 기본 개념 이해도

- [ ] `const` vs `var` 차이를 명확히 이해
- [ ] 정수 타입 범위 (i8, u8, i32, etc.)
- [ ] 오버플로우 처리 (+%, +|)
- [ ] 타입 추론과 명시적 캐스팅

### 제어 흐름

- [ ] if를 표현식으로 사용
- [ ] while의 continue 표현식
- [ ] for의 멀티 캡처 (|item, idx|)
- [ ] switch의 전수 검사 (else 필수)
- [ ] 블록 식 (break :label)

### 함수와 에러

- [ ] pub 키워드로 공개 함수 정의
- [ ] error 세트 정의
- [ ] ! 유니온 타입 이해
- [ ] try, catch, if 패턴 모두 사용 가능
- [ ] defer와 errdefer 차이

### 구조와 메모리

- [ ] 구조체 정의 및 초기화
- [ ] self (read-only) vs *self (수정)
- [ ] init 생성자 패턴
- [ ] Optional 타입 (?T)
- [ ] 포인터 기본 (&x, ptr.*)

### 고급 개념

- [ ] comptime의 기본 이해
- [ ] inline 함수의 역할
- [ ] @import 및 내장 함수
- [ ] 메모리 안전성의 중요성

---

## 🎓 학습 권장 순서

**1단계: 기초** (1-1 ~ 1-5 완료)
- 선언과 타입 ✅
- 제어 흐름 ✅
- 함수와 에러 처리 ✅
- 구조체와 메서드 ✅

**2단계: 심화** (1-6 예정)
- 포인터와 메모리 관리
- Allocator 패턴
- 안전한 메모리 제어

**3단계: 고급** (1-7 이후)
- comptime과 meta-programming
- 제네릭 프로그래밍
- 대규모 시스템 설계

---

## 💡 핵심 원칙 (Core Principles)

1. **명시성 (Explicitness)**
   - 숨겨진 제어 흐름이 없다
   - 모든 의도를 명확히 표현

2. **안전성 (Safety)**
   - 타입 안전성 강제
   - 에러 처리 강제
   - 메모리 안전성 보장

3. **성능 (Performance)**
   - C 수준의 성능
   - 컴파일 타임 최적화 (comptime)
   - Zero-cost abstraction

4. **단순성 (Simplicity)**
   - 최소한의 문법
   - 강력한 표현력
   - 일관된 설계 철학

---

## 🗺️ 다음 여정

이 Grand Map을 바탕으로, 다음 단계는 **"실제 시스템 설계"**입니다:

- **1-6**: 포인터와 메모리 관리 (저수준 제어)
- **1-7**: 제네릭 프로그래밍 (comptime)
- **1-8**: 프로젝트 설계 (대규모 시스템)

---

**기록이 증명이다** - Zig의 모든 문법을 한눈에 보았습니다! 🦎

이 지도가 여러분의 **"연구 지침서"**가 되길 바랍니다.

