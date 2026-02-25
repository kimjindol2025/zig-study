/// src/lesson_1_2.zig - Zig 전공 101: 1-2. 변수, 상수, 그리고 엄격한 타입 시스템
///
/// Assignment 1-2: 타입 설계 과제
///
/// 철학: "명시적인 상태 관리"
/// 컴파일러가 여러분의 의도를 완벽히 파악할 수 있도록 설계해야 한다.

const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-2. 변수, 상수, 그리고 엄격한 타입 시스템\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    // ============================================================================
    // 1️⃣ 가변성(Mutability)의 엄격함
    // ============================================================================

    try stdout.print("1️⃣ 가변성(Mutability)의 엄격함\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    // const: 컴파일 타임 또는 런타임에 값이 결정된 후 변경 불가
    const current_age: i32 = 26;  // Assignment: 현재 나이 (const)

    // var: 값이 변경될 수 있음
    var books_to_read: i32 = 12;  // Assignment: 올해 읽을 책의 권수 (var)

    try stdout.print("const current_age: i32 = {};\n", .{current_age});
    try stdout.print("var books_to_read: i32 = {};\n\n", .{books_to_read});

    // const를 변경하려고 하면 컴파일 에러 발생!
    // current_age = 27; // ❌ 컴파일 에러!

    // var는 정상 작동
    books_to_read += 1;  // ✅ 정상 작동
    try stdout.print("books_to_read += 1 → {}\n", .{books_to_read});

    try stdout.print("\n📝 원칙:\n", .{});
    try stdout.print("   - const: 기본값 (모든 선언은 const여야 함)\n", .{});
    try stdout.print("   - var: 명확한 이유가 있을 때만 사용\n\n", .{});

    // ============================================================================
    // 2️⃣ 연산 실험: 책 권수에 1을 더하는 코드
    // ============================================================================

    try stdout.print("2️⃣ 연산 실험: 책 권수 증가\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    var books_read: i32 = 0;
    const books_target: i32 = books_to_read;

    try stdout.print("목표: {} 권의 책을 읽기\n\n", .{books_target});

    // 월별 책 읽기 시뮬레이션
    try stdout.print("📚 월별 진행:\n", .{});
    for (1..13) |month| {
        books_read += 1;
        const progress: f32 = @as(f32, @floatFromInt(books_read)) /
                              @as(f32, @floatFromInt(books_target)) * 100.0;
        try stdout.print("  [{d:2}월] 책 {} 권 읽음 (진행률: {d:.1}%)\n", .{
            month, books_read, progress
        });
    }

    try stdout.print("\n✅ 올해 목표 달성!\n\n", .{});

    // ============================================================================
    // 3️⃣ 정적 타입과 명시적 캐스팅
    // ============================================================================

    try stdout.print("3️⃣ 정적 타입과 명시적 캐스팅\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    // 정수 타입: i8, u8, i32, u32, i64, u64 등
    const small_int: i8 = 127;           // i8: -128 ~ 127
    const unsigned_int: u8 = 255;        // u8: 0 ~ 255
    const regular_int: i32 = 2147483647; // i32: -2^31 ~ 2^31-1
    const large_int: i64 = 9223372036854775807; // i64: -2^63 ~ 2^63-1

    try stdout.print("정수 타입:\n", .{});
    try stdout.print("  i8 (작은 정수): {}\n", .{small_int});
    try stdout.print("  u8 (0~255): {}\n", .{unsigned_int});
    try stdout.print("  i32 (보통 정수): {}\n", .{regular_int});
    try stdout.print("  i64 (큰 정수): {}\n\n", .{large_int});

    // 타입 추론
    const a = @as(i32, 5);  // 명시적 지정
    const b: f32 = 10.5;    // 타입 선언
    const c: i32 = 20;      // 타입 선언

    try stdout.print("타입 추론:\n", .{});
    try stdout.print("  @as(i32, 5) → {}\n", .{a});
    try stdout.print("  const b: f32 = 10.5 → {d:.1}\n", .{b});
    try stdout.print("  const c: i32 = 20 → {}\n\n", .{c});

    // 명시적 캐스팅
    const larger: i64 = @intCast(regular_int); // i32 → i64 (안전)
    const smaller: i32 = @intCast(larger);     // i64 → i32 (위험하지만 명시적)

    try stdout.print("명시적 캐스팅:\n", .{});
    try stdout.print("  i32({}) → i64({})\n", .{regular_int, larger});
    try stdout.print("  i64({}) → i32({})\n\n", .{larger, smaller});

    // ============================================================================
    // 4️⃣ 타입 오류 유도: u8에 300 할당
    // ============================================================================

    try stdout.print("4️⃣ 타입 오류 분석: u8 범위 초과\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try stdout.print("❌ 컴파일 에러 예시:\n", .{});
    try stdout.print("   var overflow_test: u8 = 300;\n", .{});
    try stdout.print("   → error: integer value 300 cannot fit into type 'u8'\n", .{});
    try stdout.print("   → u8 범위: 0 ~ 255\n\n", .{});

    // 올바른 방법: 명시적 캐스팅 또는 타입 변경
    const value_300: i32 = 300;
    const casted_value: u8 = @intCast(value_300 % 256);  // 모듈러로 범위 내로

    try stdout.print("✅ 올바른 해결 방법:\n", .{});
    try stdout.print("   const value_300: i32 = 300;\n", .{});
    try stdout.print("   const casted_value: u8 = @intCast(value_300 % 256);\n", .{});
    try stdout.print("   → 결과: {}\n\n", .{casted_value});

    // ============================================================================
    // 5️⃣ 초기화되지 않은 값 (undefined)
    // ============================================================================

    try stdout.print("5️⃣ 초기화되지 않은 값 (undefined)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    var uninitialized: i32 = undefined;
    try stdout.print("var uninitialized: i32 = undefined;\n", .{});
    try stdout.print("→ 값이 아직 도착하지 않았음을 명시적으로 기록\n\n", .{});

    uninitialized = 42;
    try stdout.print("uninitialized = 42;\n", .{});
    try stdout.print("→ 이제 안전하게 사용 가능: {}\n\n", .{uninitialized});

    try stdout.print("⚠️  주의:\n", .{});
    try stdout.print("   - undefined 상태의 값을 읽으면 런타임 에러 또는 예측 불가능한 동작\n", .{});
    try stdout.print("   - 개발자가 메모리 상태를 완벽히 통제해야 함\n\n", .{});

    // ============================================================================
    // 6️⃣ 정수 오버플로우 방지
    // ============================================================================

    try stdout.print("6️⃣ 정수 오버플로우 방지\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const max_u8: u8 = 255;
    try stdout.print("const max_u8: u8 = 255;\n\n", .{});

    // 기본 덧셈: 오버플로우 감지
    try stdout.print("❌ 기본 덧셈 (오버플로우 감지):\n", .{});
    try stdout.print("   max_u8 + 1 → 컴파일 에러!\n", .{});
    try stdout.print("   (C와 달리 Zig는 기본적으로 오버플로우 감지)\n\n", .{});

    // Wrapping 덧셈 (+%)
    const wrapped: u8 = max_u8 +% 1;  // 0으로 감싸짐
    try stdout.print("✅ Wrapping 덧셈 (+%):\n", .{});
    try stdout.print("   max_u8 +% 1 = {} (다시 0부터 시작)\n\n", .{wrapped});

    // Saturation 덧셈 (+|)
    const saturated: u8 = max_u8 +| 10;  // 최댓값에서 멈춤
    try stdout.print("✅ Saturation 덧셈 (+|):\n", .{});
    try stdout.print("   max_u8 +| 10 = {} (최댓값에서 멈춤)\n\n", .{saturated});

    try stdout.print("연산자 정리:\n", .{});
    try stdout.print("   +  : 기본 덧셈 (오버플로우 에러)\n", .{});
    try stdout.print("   +% : Wrapping 덧셈 (0부터 재시작)\n", .{});
    try stdout.print("   +| : Saturation 덧셈 (최댓값 유지)\n\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-2 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\n", .{});
    try stdout.print("✅ Assignment 1-2 완료!\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    try stdout.print("📋 정리:\n", .{});
    try stdout.print("  ✓ 변수 선언: const (나이) vs var (책 권수)\n", .{});
    try stdout.print("  ✓ 연산 실험: books_to_read에 1을 더함\n", .{});
    try stdout.print("  ✓ 타입 오류: u8에 300 할당 시 컴파일 에러\n", .{});
    try stdout.print("  ✓ 오버플로우 방지: +%, +| 연산자 이해\n", .{});
    try stdout.print("  ✓ undefined 명시: 미초기화 값의 명시적 표기\n\n", .{});

    try stdout.print("🎯 핵심 원칙:\n", .{});
    try stdout.print("  1. 기본은 const → 변경 필요시만 var\n", .{});
    try stdout.print("  2. 명시적 캐스팅 (자동 변환 없음)\n", .{});
    try stdout.print("  3. 타입 오버플로우 감지\n", .{});
    try stdout.print("  4. 메모리 상태 완벽 통제\n\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 엄격한 타입 시스템을 이해했습니다!\n", .{});
    try stdout.print("🚀 다음: 1-3. 제어문 - if, while, for 그리고 Zig만의 switch\n", .{});
}

// ============================================================================
// 테스트: 타입 시스템 검증
// ============================================================================

test "const cannot be modified" {
    const constant: i32 = 10;
    // constant = 20; // ❌ 컴파일 에러

    try std.testing.expectEqual(@as(i32, 10), constant);
}

test "var can be modified" {
    var mutable: i32 = 10;
    mutable = 20;
    try std.testing.expectEqual(@as(i32, 20), mutable);
}

test "integer casting" {
    const small: i32 = 100;
    const large: i64 = @intCast(small);
    try std.testing.expectEqual(@as(i64, 100), large);
}

test "wrapping addition" {
    const max: u8 = 255;
    const wrapped: u8 = max +% 1;
    try std.testing.expectEqual(@as(u8, 0), wrapped);
}

test "saturation addition" {
    const max: u8 = 255;
    const saturated: u8 = max +| 10;
    try std.testing.expectEqual(@as(u8, 255), saturated);
}

test "undefined then initialization" {
    var x: i32 = undefined;
    x = 42;
    try std.testing.expectEqual(@as(i32, 42), x);
}

test "type inference" {
    const a = @as(i32, 5);
    const b: i32 = 5;
    try std.testing.expectEqual(a, b);
}

test "book reading progress" {
    var books_read: i32 = 0;
    const books_target: i32 = 12;

    for (1..13) |_| {
        books_read += 1;
    }

    try std.testing.expectEqual(books_target, books_read);
}
