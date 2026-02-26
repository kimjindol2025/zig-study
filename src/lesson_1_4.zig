/// src/lesson_1_4.zig - Zig 전공 101: 1-4. 함수(Functions)와 에러 핸들링의 기초
///
/// Assignment 1-4: 함수 설계 과제
///
/// 철학: "에러를 값으로 취급한다"
/// Zig의 가장 강력한 특징: 직관적이면서도 강력한 에러 처리

const std = @import("std");

// ============================================================================
// 1️⃣ 에러 정의 (Error Set)
// ============================================================================

/// 파일 관련 에러를 정의합니다.
const FileError = error{
    NotFound,
    AccessDenied,
    PermissionDenied,
    IOError,
};

/// 수학 연산 관련 에러
const MathError = error{
    DivisionByZero,
    Overflow,
    InvalidInput,
};

// ============================================================================
// 2️⃣ 일반 함수 (에러 없음)
// ============================================================================

/// 두 수를 더합니다.
fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// 두 수를 곱합니다.
fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

/// 절댓값을 계산합니다.
fn absolute(x: i32) i32 {
    return if (x < 0) -x else x;
}

// ============================================================================
// 3️⃣ 에러를 반환하는 함수 (Error Union Type)
// ============================================================================

/// 두 수를 나눕니다. (0으로 나누면 에러)
fn divide(a: i32, b: i32) MathError!i32 {
    if (b == 0) {
        return MathError.DivisionByZero;
    }
    return a / b;
}

/// Assignment 1-4: 숫자가 0보다 작으면 AccessDenied, 아니면 +10
fn processNumber(num: i32) FileError!i32 {
    if (num < 0) {
        return FileError.AccessDenied;
    }
    return num + 10;
}

/// 입력을 검증합니다.
fn validateInput(input: i32) MathError!void {
    if (input < 0) {
        return MathError.InvalidInput;
    }
}

/// 파일을 열려고 시도합니다. (시뮬레이션)
fn openFile(filename: []const u8) FileError!void {
    if (filename.len == 0) {
        return FileError.NotFound;
    }
    std.debug.print("파일 열기: {s}\n", .{filename});
}

// ============================================================================
// 4️⃣ defer를 사용한 리소스 관리
// ============================================================================

/// 리소스를 사용하고 정리합니다.
fn useResource() !void {
    std.debug.print("1. 리소스 확보\n", .{});
    defer std.debug.print("3. 리소스 해제 (자동 실행)\n", .{});

    std.debug.print("2. 작업 수행\n", .{});

    // defer 블록이 어디에 있든, 함수 종료 직전에 실행됨
}

/// 에러가 발생할 수 있는 상황에서도 defer는 실행됩니다.
fn useResourceWithError(should_fail: bool) FileError!void {
    std.debug.print("1. 리소스 확보\n", .{});
    defer std.debug.print("3. 리소스 해제 (에러 발생 시에도)\n", .{});

    std.debug.print("2. 작업 수행\n", .{});

    if (should_fail) {
        return FileError.IOError;
    }
}

// ============================================================================
// 5️⃣ 프라이빗 함수 (pub 없음)
// ============================================================================

/// 이 함수는 이 파일 내부에서만 사용 가능합니다.
fn internalHelper(x: i32) i32 {
    return x * 2;
}

// ============================================================================
// 6️⃣ 공개 함수 (pub)
// ============================================================================

/// 다른 모듈에서도 접근 가능한 함수입니다.
pub fn publicAPI(value: i32) i32 {
    return internalHelper(value);
}

// ============================================================================
// 메인 함수: 모든 함수 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-4. 함수와 에러 핸들링\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    // ============================================================================
    // 1️⃣ 일반 함수 (에러 없음)
    // ============================================================================

    try stdout.print("1️⃣ 일반 함수 (에러 없음)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const sum = add(5, 10);
    try stdout.print("add(5, 10) = {}\n", .{sum});

    const product = multiply(3, 7);
    try stdout.print("multiply(3, 7) = {}\n", .{product});

    const abs_neg = absolute(-42);
    try stdout.print("absolute(-42) = {}\n\n", .{abs_neg});

    // ============================================================================
    // 2️⃣ 에러를 반환하는 함수 - try 사용
    // ============================================================================

    try stdout.print("2️⃣ 에러 처리: try 사용 (정상 케이스)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const div_success = try divide(20, 5);
    try stdout.print("divide(20, 5) = {} (성공)\n\n", .{div_success});

    // ============================================================================
    // 3️⃣ 에러 처리: catch 사용 (기본값)
    // ============================================================================

    try stdout.print("3️⃣ 에러 처리: catch 사용 (기본값 제공)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const div_by_zero = divide(10, 0) catch 0;
    try stdout.print("divide(10, 0) catch 0 = {} (에러 발생 → 기본값)\n\n", .{div_by_zero});

    // ============================================================================
    // 4️⃣ Assignment 1-4: processNumber 함수
    // ============================================================================

    try stdout.print("4️⃣ Assignment 1-4: processNumber 함수\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try stdout.print("📝 에러 정의:\n", .{});
    try stdout.print("const FileError = error {{\n", .{});
    try stdout.print("    NotFound,\n", .{});
    try stdout.print("    AccessDenied,  ← 우리가 사용할 에러\n", .{});
    try stdout.print("    ...\n", .{});
    try stdout.print("}}\n\n", .{});

    try stdout.print("📝 함수 정의:\n", .{});
    try stdout.print("fn processNumber(num: i32) FileError!i32 {{\n", .{});
    try stdout.print("    if (num < 0) return FileError.AccessDenied;\n", .{});
    try stdout.print("    return num + 10;\n", .{});
    try stdout.print("}}\n\n", .{});

    // 정상 케이스: 양수
    const result_positive = try processNumber(5);
    try stdout.print("✅ processNumber(5) = {} (정상)\n", .{result_positive});

    // 에러 케이스: 음수 (catch 사용)
    const result_negative = processNumber(-10) catch blk: {
        try stdout.print("❌ processNumber(-10) → FileError.AccessDenied\n", .{});
        break :blk 0;  // 기본값
    };
    try stdout.print("   결과: {} (에러 처리됨)\n\n", .{result_negative});

    // ============================================================================
    // 5️⃣ 에러 처리: if 패턴 (Optional)
    // ============================================================================

    try stdout.print("5️⃣ 에러 처리: if 패턴으로 성공/실패 구분\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const value: i32 = 15;
    if (processNumber(value)) |success| {
        try stdout.print("processNumber({}) 성공: {}\n", .{ value, success });
    } else |err| {
        try stdout.print("processNumber({}) 실패: {}\n", .{ value, err });
    }

    const negative_value: i32 = -5;
    if (processNumber(negative_value)) |success| {
        try stdout.print("processNumber({}) 성공: {}\n", .{ negative_value, success });
    } else |err| {
        try stdout.print("processNumber({}) 실패: {} (AccessDenied)\n", .{ negative_value, err });
    }

    try stdout.print("\n", .{});

    // ============================================================================
    // 6️⃣ defer: 지연 실행
    // ============================================================================

    try stdout.print("6️⃣ defer: 리소스 정리 (자동 실행)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try useResource();
    try stdout.print("\n", .{});

    // defer는 에러 발생 시에도 실행됨
    try stdout.print("defer는 에러 발생 시에도 실행됩니다:\n", .{});
    if (useResourceWithError(true)) {
        try stdout.print("성공\n", .{});
    } else |_| {
        try stdout.print("(위의 defer 메시지 확인)\n", .{});
    }

    try stdout.print("\n", .{});

    // ============================================================================
    // 7️⃣ 함수의 가시성 (Visibility)
    // ============================================================================

    try stdout.print("7️⃣ 함수의 가시성\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try stdout.print("pub fn publicAPI(): 다른 모듈에서 접근 가능\n", .{});
    try stdout.print("fn internalHelper(): 파일 내부에서만 접근 가능\n\n", .{});

    const api_result = publicAPI(10);
    try stdout.print("publicAPI(10) = {} (internalHelper 호출)\n\n", .{api_result});

    // ============================================================================
    // 🎯 Assignment 1-4 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\n", .{});
    try stdout.print("✅ Assignment 1-4 완료!\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    try stdout.print("📋 정리:\n", .{});
    try stdout.print("  ✓ 함수의 기본 구조 (fn, 매개변수, 반환값)\n", .{});
    try stdout.print("  ✓ 에러 유니온 타입 (! 기호)\n", .{});
    try stdout.print("  ✓ 에러 처리의 3총사 (try, catch, if 패턴)\n", .{});
    try stdout.print("  ✓ defer로 리소스 정리 (자동 실행)\n", .{});
    try stdout.print("  ✓ 함수의 가시성 (pub 키워드)\n", .{});
    try stdout.print("  ✓ Assignment: FileError + processNumber 함수\n\n", .{});

    try stdout.print("🎯 핵심 원칙:\n", .{});
    try stdout.print("  1. 매개변수는 기본적으로 const (불변)\n", .{});
    try stdout.print("  2. 에러를 값으로 취급 (예외 아님)\n", .{});
    try stdout.print("  3. 에러 처리는 명시적 (try, catch, if)\n", .{});
    try stdout.print("  4. defer로 뒷정리 보장\n\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 함수와 에러 핸들링을 이해했습니다!\n", .{});
    try stdout.print("🚀 다음: 1-5. 구조체(Structs)와 메서드\n", .{});
}

// ============================================================================
// 테스트: 함수와 에러 처리 검증
// ============================================================================

test "basic functions" {
    try std.testing.expectEqual(@as(i32, 15), add(5, 10));
    try std.testing.expectEqual(@as(i32, 21), multiply(3, 7));
    try std.testing.expectEqual(@as(i32, 42), absolute(-42));
}

test "divide without error" {
    const result = try divide(20, 5);
    try std.testing.expectEqual(@as(i32, 4), result);
}

test "divide with error" {
    const result = divide(10, 0) catch 0;
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "processNumber success" {
    const result = try processNumber(5);
    try std.testing.expectEqual(@as(i32, 15), result);
}

test "processNumber error" {
    const result = processNumber(-10) catch 0;
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "validateInput success" {
    try validateInput(5);
    // 에러 없이 통과
}

test "validateInput error" {
    try std.testing.expectError(MathError.InvalidInput, validateInput(-5));
}

test "publicAPI" {
    const result = publicAPI(10);
    try std.testing.expectEqual(@as(i32, 20), result);
}

test "openFile success" {
    try openFile("test.txt");
    // 파일 열기 성공 (출력 확인)
}

test "openFile error" {
    try std.testing.expectError(FileError.NotFound, openFile(""));
}
