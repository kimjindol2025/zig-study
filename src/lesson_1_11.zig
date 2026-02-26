/// src/lesson_1_11.zig - Zig 전공 201: 1-11. C 호환성(C Interoperability)
///
/// Assignment 1-11: C 라이브러리와의 상호작용
///
/// 철학: "Zig는 C의 자산을 완벽히 활용한다"
/// Zig는 C 함수를 직접 호출하고, C 타입을 사용하며, C와 메모리를 공유할 수 있습니다.

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("math.h");
});

// ============================================================================
// 1️⃣ C 함수 직접 호출
// ============================================================================

/// C 표준 라이브러리의 strlen 함수를 직접 사용합니다.
fn cStringLength(cstr: [*:0]const u8) usize {
    return c.strlen(cstr);
}

/// C의 malloc/free를 사용하여 메모리를 할당합니다.
fn allocateWithCMalloc(size: usize) ?[*]u8 {
    const ptr = c.malloc(size);
    if (ptr == null) return null;
    return @ptrCast(ptr);
}

/// C의 malloc으로 할당한 메모리를 해제합니다.
fn freeWithCFree(ptr: ?*anyopaque) void {
    if (ptr != null) {
        c.free(ptr);
    }
}

/// C의 sqrt 함수를 호출합니다.
fn sqrtViaC(value: f64) f64 {
    return c.sqrt(value);
}

// ============================================================================
// 2️⃣ C 타입 매핑
// ============================================================================

/// C의 int는 Zig의 c_int입니다.
const MyInt = c_int;

/// C의 char는 Zig의 u8 또는 i8입니다.
const MyChar = u8;

/// C의 float는 Zig의 f32입니다.
const MyFloat = f32;

/// C의 double은 Zig의 f64입니다.
const MyDouble = f64;

/// C의 void 포인터는 Zig의 *anyopaque입니다.
const MyVoidPtr = *anyopaque;

/// C 스타일의 구조체
const CPoint = extern struct {
    x: c_int,
    y: c_int,
};

/// C 스타일의 열거형
const CColor = extern enum(c_uint) {
    Red = 0,
    Green = 1,
    Blue = 2,
};

// ============================================================================
// 3️⃣ extern 함수 (Zig에서 구현하되 C에서 호출 가능)
// ============================================================================

/// Zig에서 구현한 함수를 C에서도 호출할 수 있습니다.
export fn add_numbers(a: c_int, b: c_int) c_int {
    return a + b;
}

/// C 호환 함수 시그니처
export fn multiply_numbers(a: c_int, b: c_int) c_int {
    return a * b;
}

/// C 호환 문자열 함수
export fn get_greeting() [*:0]const u8 {
    return "Hello from Zig!";
}

// ============================================================================
// 4️⃣ C 문자열 (Null-terminated strings)
// ============================================================================

/// C 문자열 리터럴
const c_string: [*:0]const u8 = "This is a C string";

/// Zig 문자열을 C 문자열로 변환
fn zigStringToCString(allocator: std.mem.Allocator, zig_str: []const u8) ![*:0]u8 {
    const c_str = try allocator.allocSentinel(u8, zig_str.len, 0);
    @memcpy(c_str[0..zig_str.len], zig_str);
    return c_str;
}

/// C 문자열을 Zig 슬라이스로 변환
fn cStringToZigString(cstr: [*:0]const u8) []const u8 {
    var len: usize = 0;
    while (cstr[len] != 0) : (len += 1) {}
    return cstr[0..len];
}

// ============================================================================
// 5️⃣ 포인터와 메모리 공유
// ============================================================================

/// C 함수와 메모리를 공유합니다.
fn modifyViaPointer(ptr: *c_int, value: c_int) void {
    ptr.* = value;
}

/// 배열을 C 함수에 전달합니다.
fn processArray(array: [*]c_int, length: c_int) c_int {
    var sum: c_int = 0;
    var i: c_int = 0;
    while (i < length) : (i += 1) {
        sum += array[@as(usize, @intCast(i))];
    }
    return sum;
}

// ============================================================================
// 6️⃣ Assignment 1-11: C 라이브러리 래핑
// ============================================================================

/// C의 qsort를 Zig에서 안전하게 사용하는 래퍼
fn sortIntegers(allocator: std.mem.Allocator, numbers: []const i32) ![]i32 {
    // Zig의 배열을 복사 (C 함수가 수정할 수 있도록)
    const array = try allocator.dupe(i32, numbers);

    // C의 qsort는 외부 함수이므로 직접 호출 가능
    // (실제로는 비교 함수 포인터가 필요하지만, 여기서는 설명용)
    _ = array;

    return array;
}

/// C와 호환되는 구조체
const SystemInfo = extern struct {
    platform: [32]u8,
    version: c_int,
    features: c_uint,
};

/// C 구조체를 Zig에서 안전하게 사용
fn createSystemInfo(platform: []const u8) !SystemInfo {
    var info: SystemInfo = undefined;

    // platform 문자열을 복사 (오버플로우 방지)
    if (platform.len >= 32) {
        return error.PlatformNameTooLong;
    }

    @memcpy(info.platform[0..platform.len], platform);
    info.platform[platform.len] = 0; // null terminate

    info.version = 1;
    info.features = 0xFF;

    return info;
}

// ============================================================================
// 7️⃣ FFI 패턴: C 라이브러리 래핑
// ============================================================================

/// C에서 제공하는 파일 작업 함수들을 Zig에서 안전하게 사용
const FileOps = struct {
    /// C의 fopen 래핑 (실제로는 @cImport로 가능)
    fn open(filename: [:0]const u8, mode: [:0]const u8) ?*anyopaque {
        _ = filename;
        _ = mode;
        return null; // 데모용
    }

    /// C의 fclose 래핑
    fn close(file: ?*anyopaque) void {
        _ = file;
        // C의 fclose 호출
    }

    /// C의 fread 래핑
    fn read(file: ?*anyopaque, buffer: []u8) !usize {
        _ = file;
        _ = buffer;
        return 0; // 데모용
    }
};

// ============================================================================
// 8️⃣ C 호환성 확인
// ============================================================================

/// C와 호환되는 콜백 함수 타입
const CompareFunc = fn (*const anyopaque, *const anyopaque) callconv(.C) c_int;

/// C 스타일 콜백을 Zig에서 구현
fn compare_ints(a: *const anyopaque, b: *const anyopaque) callconv(.C) c_int {
    const int_a = @as(*const i32, @ptrCast(a)).*;
    const int_b = @as(*const i32, @ptrCast(b)).*;

    if (int_a < int_b) return -1;
    if (int_a > int_b) return 1;
    return 0;
}

// ============================================================================
// 메인 함수: 모든 C 호환성 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 201: 1-11. C 호환성(C Interoperability)\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // ============================================================================
    // 1️⃣ C 함수 직접 호출
    // ============================================================================

    try stdout.print("1️⃣ C 함수 직접 호출\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const test_cstr: [*:0]const u8 = "Hello, C World!";
    const len = cStringLength(test_cstr);

    try stdout.print("C의 strlen() 호출: \"{s}\"\\n", .{test_cstr});
    try stdout.print("길이: {}\\n\\n", .{len});

    // ============================================================================
    // 2️⃣ C 타입 매핑
    // ============================================================================

    try stdout.print("2️⃣ C 타입 매핑\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const c_int_val: c_int = 42;
    const c_float_val: f32 = 3.14;
    const c_double_val: f64 = 2.71828;

    try stdout.print("c_int (C의 int): {}\\n", .{c_int_val});
    try stdout.print("f32 (C의 float): {d:.2}\\n", .{c_float_val});
    try stdout.print("f64 (C의 double): {d:.5}\\n\\n", .{c_double_val});

    // ============================================================================
    // 3️⃣ C 구조체
    // ============================================================================

    try stdout.print("3️⃣ C 호환 구조체 (extern struct)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var point: CPoint = .{ .x = 10, .y = 20 };
    try stdout.print("CPoint {{ x: {}, y: {} }}\\n", .{ point.x, point.y });

    const color: CColor = .Green;
    try stdout.print("CColor (enum): {} (Green)\\n\\n", .{@intFromEnum(color)});

    // ============================================================================
    // 4️⃣ Zig 함수 (C에서 호출 가능)
    // ============================================================================

    try stdout.print("4️⃣ Zig 함수 (C에서 호출 가능 - export)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("export fn add_numbers(20, 30) = {}\\n", .{add_numbers(20, 30)});
    try stdout.print("export fn multiply_numbers(6, 7) = {}\\n", .{multiply_numbers(6, 7)});

    const greeting = get_greeting();
    try stdout.print("export fn get_greeting() = \"{s}\"\\n\\n", .{greeting});

    // ============================================================================
    // 5️⃣ C 문자열 변환
    // ============================================================================

    try stdout.print("5️⃣ C 문자열과 Zig 문자열 변환\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const zig_string = "Zig is awesome";
    const c_str_allocated = try zigStringToCString(allocator, zig_string);
    defer allocator.free(c_str_allocated);

    try stdout.print("Zig 문자열: {s}\\n", .{zig_string});
    try stdout.print("C 문자열로 변환: {s}\\n", .{c_str_allocated});

    const back_to_zig = cStringToZigString(c_str_allocated);
    try stdout.print("다시 Zig로: {s}\\n\\n", .{back_to_zig});

    // ============================================================================
    // 6️⃣ 포인터와 메모리 공유
    // ============================================================================

    try stdout.print("6️⃣ 포인터와 메모리 공유\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var value: c_int = 100;
    try stdout.print("수정 전: {}\\n", .{value});

    modifyViaPointer(&value, 200);
    try stdout.print("C 함수로 수정 후: {}\\n\\n", .{value});

    // ============================================================================
    // 7️⃣ Assignment 1-11: SystemInfo 구조체
    // ============================================================================

    try stdout.print("7️⃣ Assignment 1-11: C 호환 구조체\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const info = try createSystemInfo("Linux");

    try stdout.print("SystemInfo {{\\n", .{});
    try stdout.print("  platform: {s}\\n", .{@as([:0]const u8, @ptrCast(&info.platform))});
    try stdout.print("  version: {}\\n", .{info.version});
    try stdout.print("  features: 0x{X:0>2}\\n", .{info.features});
    try stdout.print("}}\\n\\n", .{});

    // ============================================================================
    // 8️⃣ C 호환성의 이점
    // ============================================================================

    try stdout.print("8️⃣ C 호환성의 이점\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("✓ C 라이브러리 직접 사용\\n", .{});
    try stdout.print("  - @cImport로 C 헤더 파일 임포트\\n", .{});
    try stdout.print("  - C 함수를 Zig에서 직접 호출\\n\\n", .{});

    try stdout.print("✓ 양방향 호환성\\n", .{});
    try stdout.print("  - Zig 함수를 export로 C에서 호출 가능\\n", .{});
    try stdout.print("  - C의 콜백을 Zig에서 구현\\n\\n", .{});

    try stdout.print("✓ 메모리 모델 일치\\n", .{});
    try stdout.print("  - 동일한 메모리 레이아웃\\n", .{});
    try stdout.print("  - 포인터 호환성\\n", .{});
    try stdout.print("  - extern struct로 C 타입 매핑\\n\\n", .{});

    try stdout.print("✓ 기존 자산 활용\\n", .{});
    try stdout.print("  - C 표준 라이브러리 (stdlib, string, math)\\n", .{});
    try stdout.print("  - 기존 C 프로젝트 통합\\n", .{});
    try stdout.print("  - 낮은 학습 곡선 (C 개발자)\\n\\n", .{});

    // ============================================================================
    // 9️⃣ C 호환 함수 시그니처
    // ============================================================================

    try stdout.print("9️⃣ C 호환 함수 시그니처 (callconv)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("export fn function_name(...) callconv(.C) return_type {{\\n", .{});
    try stdout.print("  // C 호출 규약(Calling Convention) 사용\\n", .{});
    try stdout.print("}}\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-11 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-11 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ @cImport로 C 헤더 임포트\\n", .{});
    try stdout.print("  ✓ C 함수 직접 호출\\n", .{});
    try stdout.print("  ✓ C 타입 매핑 (c_int, f32 등)\\n", .{});
    try stdout.print("  ✓ extern struct로 메모리 레이아웃 일치\\n", .{});
    try stdout.print("  ✓ export fn으로 C에서 호출 가능한 함수\\n", .{});
    try stdout.print("  ✓ C 문자열 변환 (null-terminated)\\n", .{});
    try stdout.print("  ✓ 포인터 호환성과 메모리 공유\\n", .{});
    try stdout.print("  ✓ callconv(.C)로 호출 규약 지정\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. Zig는 C와 메모리 호환\\n", .{});
    try stdout.print("  2. @cImport로 C 라이브러리 통합\\n", .{});
    try stdout.print("  3. export fn으로 양방향 호출\\n", .{});
    try stdout.print("  4. extern struct로 C 타입 표현\\n", .{});
    try stdout.print("  5. 타입 안전성을 잃지 않으면서 호환성 제공\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 C 호환성을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 축하합니다! Zig 전공 201 시작 단계 완성!\\n", .{});
}

// ============================================================================
// 테스트: C 호환성 검증
// ============================================================================

test "c string length" {
    const test_str: [*:0]const u8 = "test";
    try std.testing.expectEqual(@as(usize, 4), cStringLength(test_str));
}

test "c int math" {
    const a: c_int = 10;
    const b: c_int = 5;
    try std.testing.expectEqual(@as(c_int, 15), add_numbers(a, b));
    try std.testing.expectEqual(@as(c_int, 50), multiply_numbers(a, b));
}

test "c point structure" {
    var point: CPoint = .{ .x = 5, .y = 10 };
    try std.testing.expectEqual(@as(c_int, 5), point.x);
    try std.testing.expectEqual(@as(c_int, 10), point.y);

    modifyViaPointer(&point.x, 20);
    try std.testing.expectEqual(@as(c_int, 20), point.x);
}

test "c color enum" {
    const colors: [3]CColor = [_]CColor{ .Red, .Green, .Blue };
    try std.testing.expectEqual(@as(c_uint, 0), @intFromEnum(colors[0]));
    try std.testing.expectEqual(@as(c_uint, 1), @intFromEnum(colors[1]));
    try std.testing.expectEqual(@as(c_uint, 2), @intFromEnum(colors[2]));
}

test "zig string to c string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const zig_str = "Hello";
    const c_str = try zigStringToCString(allocator, zig_str);
    defer allocator.free(c_str);

    try std.testing.expectEqual(@as(usize, 5), cStringLength(c_str));
}

test "c string to zig string" {
    const c_str: [*:0]const u8 = "Test string";
    const zig_str = cStringToZigString(c_str);

    try std.testing.expectEqualSlices(u8, "Test string", zig_str);
}

test "system info creation" {
    const info = try createSystemInfo("Windows");
    try std.testing.expectEqual(@as(c_int, 1), info.version);
    try std.testing.expectEqual(@as(c_uint, 0xFF), info.features);
}

test "array processing" {
    var array: [3]c_int = [_]c_int{ 1, 2, 3 };
    const sum = processArray(&array, 3);
    try std.testing.expectEqual(@as(c_int, 6), sum);
}

test "compare function callback" {
    var a: i32 = 10;
    var b: i32 = 5;

    const result = compare_ints(&a, &b);
    try std.testing.expectEqual(@as(c_int, 1), result);
}

test "export function greeting" {
    const greeting = get_greeting();
    const greeting_str = cStringToZigString(greeting);

    try std.testing.expectEqualSlices(u8, "Hello from Zig!", greeting_str);
}
