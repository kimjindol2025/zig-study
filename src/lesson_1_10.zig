/// src/lesson_1_10.zig - Zig 전공 101: 1-10. Comptime - 컴파일 타임에 실행되는 코드
///
/// Assignment 1-10: 컴파일 타임 계산과 제네릭 프로그래밍
///
/// 철학: "계산할 수 있는 것은 컴파일 타임에"
/// Zig의 comptime은 런타임 비용 제로로 유연성을 제공합니다.

const std = @import("std");

// ============================================================================
// 1️⃣ Comptime 기본 개념
// ============================================================================

/// 컴파일 타임 상수 (명시적 comptime)
const comptime_pi = comptime blk: {
    // 이 블록은 컴파일 타임에 실행됨
    break :blk 3.14159;
};

/// 컴파일 타임에 계산되는 피보나치
const comptime_fib = comptime blk: {
    var n: u32 = 0;
    var a: u32 = 1;
    var b: u32 = 1;
    while (n < 10) : (n += 1) {
        const temp = a + b;
        a = b;
        b = temp;
    }
    break :blk a;
};

// ============================================================================
// 2️⃣ Comptime 함수 (제네릭)
// ============================================================================

/// 두 수의 합을 반환합니다. (제네릭)
fn add(a: anytype, b: anytype) @TypeOf(a + b) {
    return a + b;
}

/// 배열의 길이를 반환합니다. (제네릭)
fn arrayLength(array: anytype) usize {
    return array.len;
}

/// 배열의 첫 번째 요소를 반환합니다. (제네릭)
fn first(array: anytype) anytype {
    return array[0];
}

/// 두 값의 더 큰 것을 반환합니다. (제네릭)
fn max(a: anytype, b: anytype) @TypeOf(a) {
    return if (a > b) a else b;
}

// ============================================================================
// 3️⃣ Comptime 제어문
// ============================================================================

/// 컴파일 타임에 배열을 생성합니다.
const powers_of_two = comptime blk: {
    var result: [8]u32 = undefined;
    for (0..8) |i| {
        result[i] = 1 << @as(u5, @intCast(i));
    }
    break :blk result;
};

/// 컴파일 타임에 문자열을 생성합니다.
const greeting = comptime blk: {
    const prefix = "Hello, ";
    const name = "Zig";
    const suffix = "!";
    break :blk prefix ++ name ++ suffix;
};

// ============================================================================
// 4️⃣ Comptime 조건문 (빌드 시 다른 코드 생성)
// ============================================================================

/// 플랫폼별로 다른 상수를 정의합니다.
const BUFFER_SIZE = comptime blk: {
    const builtin = @import("builtin");
    break :blk if (builtin.mode == .Debug)
        1024
    else
        65536;
};

// ============================================================================
// 5️⃣ 제네릭 구조체
// ============================================================================

/// 제네릭 스택 (타입을 매개변수로 받음)
fn Stack(comptime T: type) type {
    return struct {
        items: []T,
        count: usize,

        const Self = @This();

        fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{
                .items = try allocator.alloc(T, capacity),
                .count = 0,
            };
        }

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }

        fn push(self: *Self, value: T) !void {
            if (self.count >= self.items.len) {
                return error.StackFull;
            }
            self.items[self.count] = value;
            self.count += 1;
        }

        fn pop(self: *Self) ?T {
            if (self.count == 0) return null;
            self.count -= 1;
            return self.items[self.count];
        }

        fn isEmpty(self: Self) bool {
            return self.count == 0;
        }

        fn isFull(self: Self) bool {
            return self.count >= self.items.len;
        }

        fn size(self: Self) usize {
            return self.count;
        }
    };
}

// ============================================================================
// 6️⃣ 제네릭 컨테이너
// ============================================================================

/// 제네릭 쌍 (Pair)
fn Pair(comptime T: type, comptime U: type) type {
    return struct {
        first: T,
        second: U,
    };
}

/// 제네릭 옵션 (Option)
fn Option(comptime T: type) type {
    return union(enum) {
        Some: T,
        None,
    };
}

// ============================================================================
// 7️⃣ Assignment 1-10: 제네릭 계산기
// ============================================================================

/// 두 수에 대해 다양한 연산을 수행하는 계산기
fn Calculator(comptime T: type) type {
    return struct {
        fn add(a: T, b: T) T {
            return a + b;
        }

        fn subtract(a: T, b: T) T {
            return a - b;
        }

        fn multiply(a: T, b: T) T {
            return a * b;
        }

        fn divide(a: T, b: T) !T {
            if (b == 0) {
                return error.DivisionByZero;
            }
            return a / b;
        }

        fn abs(a: T) T {
            return if (a < 0) -a else a;
        }

        fn max(a: T, b: T) T {
            return if (a > b) a else b;
        }

        fn min(a: T, b: T) T {
            return if (a < b) a else b;
        }
    };
}

/// 제네릭 시퀀스 생성기
fn sequence(comptime T: type, start: T, count: usize, allocator: std.mem.Allocator) ![]T {
    const result = try allocator.alloc(T, count);
    for (0..count) |i| {
        result[i] = start + @as(T, @intCast(i));
    }
    return result;
}

// ============================================================================
// 메인 함수: 모든 comptime 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-10. Comptime\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // ============================================================================
    // 1️⃣ Comptime 상수
    // ============================================================================

    try stdout.print("1️⃣ Comptime 상수\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("const comptime_pi = comptime {{ ... }}\\n", .{});
    try stdout.print("  값: {}\\n", .{comptime_pi});

    try stdout.print("const comptime_fib = comptime {{ ... }}\\n", .{});
    try stdout.print("  값: {} (10번째 피보나치)\\n\\n", .{comptime_fib});

    // ============================================================================
    // 2️⃣ 컴파일 타임 생성 배열
    // ============================================================================

    try stdout.print("2️⃣ 컴파일 타임 생성 배열\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("powers_of_two: [", .{});
    for (powers_of_two, 0..) |val, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{val});
    }
    try stdout.print("]\\n", .{});

    try stdout.print("greeting: \"{s}\"\\n\\n", .{greeting});

    // ============================================================================
    // 3️⃣ 제네릭 함수 (anytype)
    // ============================================================================

    try stdout.print("3️⃣ 제네릭 함수 (anytype)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("add(5, 10) = {}\\n", .{add(5, 10)});
    try stdout.print("add(3.14, 2.86) = {d:.2}\\n", .{add(3.14, 2.86)});

    const arr: [5]i32 = [_]i32{ 1, 2, 3, 4, 5 };
    try stdout.print("arrayLength([1,2,3,4,5]) = {}\\n", .{arrayLength(arr)});
    try stdout.print("first([1,2,3,4,5]) = {}\\n", .{first(arr)});

    try stdout.print("max(42, 17) = {}\\n\\n", .{max(42, 17)});

    // ============================================================================
    // 4️⃣ 제네릭 스택
    // ============================================================================

    try stdout.print("4️⃣ 제네릭 스택 (Stack)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // i32 스택
    var int_stack = try Stack(i32).init(allocator, 10);
    defer int_stack.deinit(allocator);

    try int_stack.push(10);
    try int_stack.push(20);
    try int_stack.push(30);

    try stdout.print("i32 Stack:\\n", .{});
    try stdout.print("  push(10), push(20), push(30)\\n", .{});
    try stdout.print("  크기: {}\\n", .{int_stack.size()});
    try stdout.print("  pop() = {}\\n", .{int_stack.pop()});
    try stdout.print("  pop() = {}\\n", .{int_stack.pop()});
    try stdout.print("  크기: {}\\n\\n", .{int_stack.size()});

    // u8 스택
    var byte_stack = try Stack(u8).init(allocator, 10);
    defer byte_stack.deinit(allocator);

    try byte_stack.push('Z');
    try byte_stack.push('i');
    try byte_stack.push('g');

    try stdout.print("u8 Stack:\\n", .{});
    try stdout.print("  push('Z'), push('i'), push('g')\\n", .{});
    try stdout.print("  크기: {}\\n", .{byte_stack.size()});
    try stdout.print("  pop() = '{}' (ASCII: {})\\n", .{ byte_stack.pop(), byte_stack.pop() });
    try stdout.print("\\n", .{});

    // ============================================================================
    // 5️⃣ 제네릭 쌍과 옵션
    // ============================================================================

    try stdout.print("5️⃣ 제네릭 컨테이너 (Pair, Option)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const pair_type = Pair(i32, []const u8);
    const my_pair: pair_type = .{ .first = 42, .second = "answer" };

    try stdout.print("Pair(i32, []const u8):\\n", .{});
    try stdout.print("  first: {}\\n", .{my_pair.first});
    try stdout.print("  second: {s}\\n\\n", .{my_pair.second});

    const option_some: Option(i32) = .{ .Some = 100 };
    const option_none: Option(i32) = .None;

    try stdout.print("Option(i32):\\n", .{});
    switch (option_some) {
        .Some => |val| try stdout.print("  Some: {}\\n", .{val}),
        .None => try stdout.print("  None\\n", .{}),
    }
    switch (option_none) {
        .Some => |val| try stdout.print("  Some: {}\\n", .{val}),
        .None => try stdout.print("  None\\n", .{}),
    }
    try stdout.print("\\n", .{});

    // ============================================================================
    // 6️⃣ Assignment 1-10: 제네릭 계산기
    // ============================================================================

    try stdout.print("6️⃣ Assignment 1-10: 제네릭 계산기\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const IntCalc = Calculator(i32);
    const FloatCalc = Calculator(f32);

    try stdout.print("Calculator(i32):\\n", .{});
    try stdout.print("  add(20, 30) = {}\\n", .{IntCalc.add(20, 30)});
    try stdout.print("  multiply(6, 7) = {}\\n", .{IntCalc.multiply(6, 7)});
    try stdout.print("  max(100, 50) = {}\\n", .{IntCalc.max(100, 50)});

    const div_result = IntCalc.divide(20, 5) catch 0;
    try stdout.print("  divide(20, 5) = {}\\n\\n", .{div_result});

    try stdout.print("Calculator(f32):\\n", .{});
    try stdout.print("  add(3.5, 2.5) = {d:.2}\\n", .{FloatCalc.add(3.5, 2.5)});
    try stdout.print("  multiply(2.5, 4.0) = {d:.2}\\n", .{FloatCalc.multiply(2.5, 4.0)});
    try stdout.print("  max(10.5, 5.2) = {d:.2}\\n\\n", .{FloatCalc.max(10.5, 5.2)});

    // ============================================================================
    // 7️⃣ 제네릭 시퀀스 생성
    // ============================================================================

    try stdout.print("7️⃣ 제네릭 시퀀스 생성\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const int_seq = try sequence(i32, 10, 5, allocator);
    defer allocator.free(int_seq);

    try stdout.print("sequence(i32, 10, 5): [", .{});
    for (int_seq, 0..) |val, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{val});
    }
    try stdout.print("]\\n", .{});

    const u8_seq = try sequence(u8, 65, 3, allocator);
    defer allocator.free(u8_seq);

    try stdout.print("sequence(u8, 65, 3): [", .{});
    for (u8_seq, 0..) |val, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("'{c}'", .{val});
    }
    try stdout.print("]\\n\\n", .{});

    // ============================================================================
    // 8️⃣ Comptime 이점
    // ============================================================================

    try stdout.print("8️⃣ Comptime의 이점\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("✓ 런타임 오버헤드 제로\\n", .{});
    try stdout.print("  - 컴파일 타임에 모든 계산 완료\\n", .{});
    try stdout.print("  - 최종 바이너리에는 상수만 남음\\n\\n", .{});

    try stdout.print("✓ 타입 안전성\\n", .{});
    try stdout.print("  - anytype도 컴파일 타임에 타입 결정\\n", .{});
    try stdout.print("  - 런타임에 타입 검사 불필요\\n\\n", .{});

    try stdout.print("✓ 제네릭 프로그래밍\\n", .{});
    try stdout.print("  - Stack(i32), Stack(f32), Stack([]const u8) 각각 생성\\n", .{});
    try stdout.print("  - 반복적인 코드 없음\\n\\n", .{});

    try stdout.print("✓ 메타프로그래밍\\n", .{});
    try stdout.print("  - 컴파일러가 코드를 생성하는 코드\\n", .{});
    try stdout.print("  - 복잡한 로직도 구조적으로 표현 가능\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-10 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-10 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ comptime 상수: 컴파일 타임에 계산\\n", .{});
    try stdout.print("  ✓ comptime 블록: 복잡한 계산 구조\\n", .{});
    try stdout.print("  ✓ anytype: 제네릭 함수 매개변수\\n", .{});
    try stdout.print("  ✓ @TypeOf(): 타입 연산\\n", .{});
    try stdout.print("  ✓ 제네릭 함수: add, max, first, arrayLength\\n", .{});
    try stdout.print("  ✓ 제네릭 구조체: Stack(T), Pair(T, U), Option(T)\\n", .{});
    try stdout.print("  ✓ 제네릭 계산기: Calculator(T)\\n", .{});
    try stdout.print("  ✓ 메타프로그래밍: 코드를 생성하는 코드\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. comptime은 \"컴파일 타임에 실행\"을 의미\\n", .{});
    try stdout.print("  2. anytype은 \"나중에 결정될 타입\"\\n", .{});
    try stdout.print("  3. 제네릭 = 컴파일 타임 다형성\\n", .{});
    try stdout.print("  4. 런타임 오버헤드 제로\\n", .{});
    try stdout.print("  5. 타입 안전성 100%\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 Comptime 마법을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 축하합니다! Zig 전공 101 기초 과정 완성!\\n", .{});
}

// ============================================================================
// 테스트: Comptime과 제네릭 검증
// ============================================================================

test "generic add function" {
    try std.testing.expectEqual(@as(i32, 15), add(5, 10));
    try std.testing.expectEqual(@as(f32, 5.5), add(2.5, 3.0));
}

test "generic array length" {
    const arr: [5]i32 = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(usize, 5), arrayLength(arr));
}

test "generic first element" {
    const arr: [3]i32 = [_]i32{ 42, 0, 0 };
    try std.testing.expectEqual(@as(i32, 42), first(arr));
}

test "generic max function" {
    try std.testing.expectEqual(@as(i32, 42), max(42, 17));
    try std.testing.expectEqual(@as(f32, 10.5), max(5.2, 10.5));
}

test "stack push and pop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = try Stack(i32).init(allocator, 10);
    defer stack.deinit(allocator);

    try stack.push(10);
    try stack.push(20);

    try std.testing.expectEqual(@as(?i32, 20), stack.pop());
    try std.testing.expectEqual(@as(?i32, 10), stack.pop());
    try std.testing.expectEqual(@as(?i32, null), stack.pop());
}

test "stack size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = try Stack(i32).init(allocator, 5);
    defer stack.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), stack.size());
    try stack.push(1);
    try std.testing.expectEqual(@as(usize, 1), stack.size());
}

test "calculator integer operations" {
    const IntCalc = Calculator(i32);
    try std.testing.expectEqual(@as(i32, 50), IntCalc.add(20, 30));
    try std.testing.expectEqual(@as(i32, 42), IntCalc.multiply(6, 7));
    try std.testing.expectEqual(@as(i32, 100), IntCalc.max(100, 50));
}

test "calculator division" {
    const IntCalc = Calculator(i32);
    const result = IntCalc.divide(20, 5) catch 0;
    try std.testing.expectEqual(@as(i32, 4), result);
}

test "pair generic type" {
    const pair_type = Pair(i32, []const u8);
    const my_pair: pair_type = .{ .first = 42, .second = "test" };

    try std.testing.expectEqual(@as(i32, 42), my_pair.first);
    try std.testing.expectEqualStrings("test", my_pair.second);
}

test "option some and none" {
    const some: Option(i32) = .{ .Some = 100 };
    const none: Option(i32) = .None;

    try std.testing.expectEqual(@as(i32, 100), some.Some);
    try std.testing.expect(none == .None);
}

test "sequence generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const seq = try sequence(i32, 10, 5, allocator);
    defer allocator.free(seq);

    try std.testing.expectEqual(@as(i32, 10), seq[0]);
    try std.testing.expectEqual(@as(i32, 14), seq[4]);
}

test "comptime powers of two" {
    try std.testing.expectEqual(@as(u32, 1), powers_of_two[0]);
    try std.testing.expectEqual(@as(u32, 2), powers_of_two[1]);
    try std.testing.expectEqual(@as(u32, 4), powers_of_two[2]);
    try std.testing.expectEqual(@as(u32, 256), powers_of_two[8]);
}

test "comptime greeting" {
    try std.testing.expectEqualStrings("Hello, Zig!", greeting);
}

test "comptime constants" {
    try std.testing.expectEqual(@as(u32, 89), comptime_fib);
}
