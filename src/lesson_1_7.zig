/// src/lesson_1_7.zig - Zig 전공 101: 1-7. 배열(Arrays)과 슬라이스(Slices) - 메모리 안전의 파수꾼
///
/// Assignment 1-7: 배열과 슬라이스 조작
///
/// 철학: "배열의 범위는 컴파일 타임에 알려진다"
/// Zig는 배열 경계를 넘는 접근을 컴파일 타임에 감지하고,
/// 런타임에서도 범위 검사를 수행하여 메모리 안전성을 보장한다.

const std = @import("std");

// ============================================================================
// 1️⃣ 정적 배열 (Static Arrays) [N]T
// ============================================================================

/// 정수 배열 (크기 고정)
fn staticArrayExample() void {
    const fixed: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    // fixed.len = 5 (컴파일 타임에 결정)
    // fixed[0] = 10, fixed[1] = 20, ...
}

/// 정적 배열의 크기를 얻습니다.
fn getArrayLength(array: anytype) usize {
    return array.len;
}

/// 정적 배열의 첫 번째 요소를 반환합니다.
fn getFirstElement(array: [5]i32) i32 {
    return array[0];
}

// ============================================================================
// 2️⃣ 배열 슬라이스 (Array Slices) []T
// ============================================================================

/// 배열을 슬라이스로 변환합니다. (포인터 + 길이)
fn arrayToSlice(array: *[5]i32) []i32 {
    return array[0..];  // 전체 배열을 슬라이스로
}

/// 배열의 부분을 슬라이스로 가져옵니다.
fn sliceRange(array: *[10]i32) []i32 {
    return array[2..7];  // 인덱스 2부터 7(미포함)까지 = [2,3,4,5,6]
}

/// 슬라이스의 길이를 반환합니다.
fn getSliceLength(slice: []const i32) usize {
    return slice.len;
}

/// 슬라이스의 요소를 순회합니다.
fn iterateSlice(slice: []const i32, idx: usize) ?i32 {
    if (idx < slice.len) {
        return slice[idx];
    } else {
        return null;
    }
}

// ============================================================================
// 3️⃣ Many-item 포인터 ([*]T)
// ============================================================================

/// Many-item 포인터 (배열의 시작점, 길이 없음)
fn manyItemPointerExample(array: [5]i32) void {
    var ptr: [*]const i32 = &array;
    // ptr[0], ptr[1], ptr[2], ... 접근 가능
    // 하지만 길이를 모르므로 경계 검사 불가능
    // (슬라이스가 더 안전함)
}

// ============================================================================
// 4️⃣ 문자열 리터럴과 슬라이스
// ============================================================================

/// 문자열 리터럴 (컴파일 타임 상수)
fn stringLiteralExample() void {
    const greeting: []const u8 = "Hello, Zig!";
    // greeting.len = 12
    // greeting[0] = 'H', greeting[1] = 'e', ...
}

/// 문자열의 부분을 슬라이스로 가져옵니다.
fn sliceString(text: []const u8, start: usize, end: usize) []const u8 {
    return text[start..end];
}

/// 문자열을 공백으로 분할합니다. (간단한 예제)
fn findWordBoundary(text: []const u8) ?usize {
    for (text, 0..) |char, idx| {
        if (char == ' ') {
            return idx;
        }
    }
    return null;
}

// ============================================================================
// 5️⃣ 슬라이스 연산과 범위 검사
// ============================================================================

/// 슬라이스의 범위를 안전하게 검사합니다.
fn safeSliceAccess(slice: []const i32, index: usize) ?i32 {
    if (index < slice.len) {
        return slice[index];
    } else {
        return null;  // 범위를 벗어남
    }
}

/// 두 슬라이스가 같은지 비교합니다.
fn compareSlices(a: []const i32, b: []const i32) bool {
    if (a.len != b.len) return false;

    for (a, b) |val_a, val_b| {
        if (val_a != val_b) return false;
    }
    return true;
}

/// 슬라이스의 요소들의 합을 계산합니다.
fn sumSlice(slice: []const i32) i32 {
    var sum: i32 = 0;
    for (slice) |value| {
        sum += value;
    }
    return sum;
}

// ============================================================================
// 6️⃣ 동적 배열 관리 (ArrayList)
// ============================================================================

/// ArrayList를 사용한 동적 배열
fn dynamicArrayExample(allocator: std.mem.Allocator) !void {
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    // 요소 추가
    try list.append(100);
    try list.append(200);
    try list.append(300);

    // list.items = 슬라이스로 접근
    // list.items.len = 3
}

// ============================================================================
// 7️⃣ Assignment 1-7: 배열과 슬라이싱 실습
// ============================================================================

/// 점수 데이터를 관리하는 ScoreManager 구조체
const ScoreManager = struct {
    scores: [10]u32,
    count: usize,

    fn init() ScoreManager {
        return .{
            .scores = [_]u32{0} ** 10,
            .count = 0,
        };
    }

    /// 점수를 추가합니다.
    fn addScore(self: *ScoreManager, score: u32) !void {
        if (self.count >= 10) {
            return error.ScoreListFull;
        }
        self.scores[self.count] = score;
        self.count += 1;
    }

    /// 추가된 점수들의 슬라이스를 반환합니다.
    fn getScores(self: *ScoreManager) []const u32 {
        return self.scores[0..self.count];
    }

    /// 평균 점수를 계산합니다.
    fn getAverage(self: *ScoreManager) f32 {
        if (self.count == 0) return 0.0;

        var sum: u32 = 0;
        for (self.getScores()) |score| {
            sum += score;
        }
        return @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(self.count));
    }

    /// 최고 점수를 반환합니다.
    fn getMax(self: *ScoreManager) ?u32 {
        if (self.count == 0) return null;

        var max: u32 = 0;
        for (self.getScores()) |score| {
            if (score > max) max = score;
        }
        return max;
    }

    /// 최저 점수를 반환합니다.
    fn getMin(self: *ScoreManager) ?u32 {
        if (self.count == 0) return null;

        var min: u32 = 255;
        for (self.getScores()) |score| {
            if (score < min) min = score;
        }
        return min;
    }
};

// ============================================================================
// 8️⃣ 안전한 범위 검사와 슬라이싱
// ============================================================================

/// 배열의 일부를 안전하게 슬라이싱합니다.
fn safeSliceArray(array: [10]i32, start: usize, end: usize) ![]const i32 {
    if (start > end or end > array.len) {
        return error.InvalidSliceRange;
    }
    return array[start..end];
}

/// 문자열에서 단어를 추출합니다.
fn extractWord(text: []const u8, word_index: usize) ![]const u8 {
    var current_word: usize = 0;
    var start: usize = 0;

    for (text, 0..) |char, idx| {
        if (char == ' ') {
            if (current_word == word_index) {
                return text[start..idx];
            }
            current_word += 1;
            start = idx + 1;
        }
    }

    // 마지막 단어
    if (current_word == word_index) {
        return text[start..];
    }

    return error.WordNotFound;
}

// ============================================================================
// 메인 함수: 모든 배열과 슬라이스 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-7. 배열과 슬라이스\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // ============================================================================
    // 1️⃣ 정적 배열 (Static Arrays)
    // ============================================================================

    try stdout.print("1️⃣ 정적 배열 (Static Arrays) [N]T\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const scores: [5]u32 = [_]u32{ 90, 85, 92, 88, 95 };

    try stdout.print("const scores: [5]u32 = [_]u32{{ 90, 85, 92, 88, 95 }};\\n", .{});
    try stdout.print("배열 크기: {}\\n", .{scores.len});
    try stdout.print("첫 번째 점수: {}\\n", .{scores[0]});
    try stdout.print("마지막 점수: {}\\n", .{scores[scores.len - 1]});

    try stdout.print("모든 점수: [", .{});
    for (scores, 0..) |score, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{score});
    }
    try stdout.print("]\\n\\n", .{});

    // ============================================================================
    // 2️⃣ 배열 슬라이싱 (Array Slicing)
    // ============================================================================

    try stdout.print("2️⃣ 배열 슬라이싱 (Array Slicing) []T\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var data: [10]i32 = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const full_slice: []i32 = &data;

    try stdout.print("var data: [10]i32 = [_]i32{{ 1, 2, ..., 10 }};\\n", .{});
    try stdout.print("전체 슬라이스: data[0..] → 길이 {}\\n", .{full_slice.len});

    const partial_slice: []i32 = data[2..7];
    try stdout.print("부분 슬라이스: data[2..7] → [", .{});
    for (partial_slice, 0..) |val, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{val});
    }
    try stdout.print("] (길이: {})\\n\\n", .{partial_slice.len});

    // ============================================================================
    // 3️⃣ 문자열 슬라이싱
    // ============================================================================

    try stdout.print("3️⃣ 문자열 슬라이싱\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const text: []const u8 = "Hello, Zig!";
    try stdout.print("문자열: \"{s}\"\\n", .{text});
    try stdout.print("길이: {}\\n", .{text.len});

    const hello: []const u8 = text[0..5];
    const zig: []const u8 = text[7..10];

    try stdout.print("첫 5글자: \"{s}\" (text[0..5])\\n", .{hello});
    try stdout.print("\"Zig\": \"{s}\" (text[7..10])\\n\\n", .{zig});

    // ============================================================================
    // 4️⃣ 슬라이스 순회 (Iteration)
    // ============================================================================

    try stdout.print("4️⃣ 슬라이스 순회 (Iteration)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const numbers: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    const nums_slice: []const i32 = &numbers;

    try stdout.print("for (nums_slice) |value| 패턴:\\n", .{});
    for (nums_slice) |value| {
        try stdout.print("  {}, ", .{value});
    }
    try stdout.print("\\n\\n", .{});

    try stdout.print("for (nums_slice, 0..) |value, idx| 패턴:\\n", .{});
    for (nums_slice, 0..) |value, idx| {
        try stdout.print("  [{}] = {}, ", .{ idx, value });
    }
    try stdout.print("\\n\\n", .{});

    // ============================================================================
    // 5️⃣ 범위 검사 (Bounds Checking)
    // ============================================================================

    try stdout.print("5️⃣ 범위 검사 (Bounds Checking)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const test_slice: []const i32 = &[_]i32{ 100, 200, 300 };

    try stdout.print("유효한 접근: test_slice[0] = {}\\n", .{test_slice[0]});
    try stdout.print("유효한 접근: test_slice[2] = {}\\n", .{test_slice[2]});

    // test_slice[3]은 런타임 에러!
    try stdout.print("범위를 벗어난 접근 (test_slice[3])은 런타임 에러 발생\\n", .{});
    try stdout.print("(실제로 실행하면 panic이 발생합니다)\\n\\n", .{});

    // ============================================================================
    // 6️⃣ Assignment 1-7: ScoreManager
    // ============================================================================

    try stdout.print("6️⃣ Assignment 1-7: ScoreManager 실습\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("📝 ScoreManager 구조체:\\n", .{});
    try stdout.print("  - scores: [10]u32 (최대 10개의 점수)\\n", .{});
    try stdout.print("  - count: usize (현재 점수 개수)\\n", .{});
    try stdout.print("  - addScore(): 점수 추가\\n", .{});
    try stdout.print("  - getScores(): 슬라이스로 반환\\n", .{});
    try stdout.print("  - getAverage(): 평균 계산\\n", .{});
    try stdout.print("  - getMax()/getMin(): 최고/최저 점수\\n\\n", .{});

    var manager = ScoreManager.init();

    try manager.addScore(90);
    try manager.addScore(85);
    try manager.addScore(92);
    try manager.addScore(88);
    try manager.addScore(95);

    try stdout.print("점수 추가: 90, 85, 92, 88, 95\\n", .{});
    try stdout.print("개수: {}\\n", .{manager.count});

    const mgr_scores = manager.getScores();
    try stdout.print("슬라이스로 반환: [", .{});
    for (mgr_scores, 0..) |score, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{score});
    }
    try stdout.print("]\\n", .{});

    const avg = manager.getAverage();
    try stdout.print("평균: {d:.2}\\n", .{avg});

    if (manager.getMax()) |max| {
        try stdout.print("최고 점수: {}\\n", .{max});
    }

    if (manager.getMin()) |min| {
        try stdout.print("최저 점수: {}\\n", .{min});
    }

    try stdout.print("\\n", .{});

    // ============================================================================
    // 7️⃣ 슬라이스 비교
    // ============================================================================

    try stdout.print("7️⃣ 슬라이스 비교\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const arr1: [3]i32 = [_]i32{ 1, 2, 3 };
    const arr2: [3]i32 = [_]i32{ 1, 2, 3 };
    const arr3: [3]i32 = [_]i32{ 1, 2, 4 };

    const slice1: []const i32 = &arr1;
    const slice2: []const i32 = &arr2;
    const slice3: []const i32 = &arr3;

    try stdout.print("slice1 == slice2? {}", .{std.mem.eql(i32, slice1, slice2)});
    try stdout.print(" (모든 요소가 같음)\\n", .{});
    try stdout.print("slice1 == slice3? {}", .{std.mem.eql(i32, slice1, slice3)});
    try stdout.print(" (마지막 요소가 다름)\\n\\n", .{});

    // ============================================================================
    // 8️⃣ 슬라이스의 합계
    // ============================================================================

    try stdout.print("8️⃣ 슬라이스의 합계 계산\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const nums: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    const nums_sum_slice: []const i32 = &nums;

    var total: i32 = 0;
    for (nums_sum_slice) |value| {
        total += value;
    }

    try stdout.print("합계: {} + {} + {} + {} + {} = {}\\n\\n", .{
        nums[0], nums[1], nums[2], nums[3], nums[4], total,
    });

    // ============================================================================
    // 🎯 Assignment 1-7 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-7 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ 정적 배열 ([N]T): 크기가 고정되고 스택에 저장\\n", .{});
    try stdout.print("  ✓ 배열 슬라이스 ([]T): 포인터 + 길이 (가장 안전함)\\n", .{});
    try stdout.print("  ✓ Many-item 포인터 ([*]T): 배열의 시작점만 (길이 없음)\\n", .{});
    try stdout.print("  ✓ 슬라이싱 (array[start..end]): 범위 지정\\n", .{});
    try stdout.print("  ✓ 문자열 슬라이싱: 부분 추출\\n", .{});
    try stdout.print("  ✓ for 루프: 슬라이스 순회\\n", .{});
    try stdout.print("  ✓ 범위 검사: 인덱스가 .len을 벗어나면 panic\\n", .{});
    try stdout.print("  ✓ 슬라이스 비교: std.mem.eql()\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 배열 [N]T: 컴파일 타임에 크기 결정, 스택 저장\\n", .{});
    try stdout.print("  2. 슬라이스 []T: 런타임에 길이, 안전한 접근\\n", .{});
    try stdout.print("  3. 범위 검사: 런타임에 자동으로 경계 확인\\n", .{});
    try stdout.print("  4. 슬라이싱: array[start..end] 문법\\n", .{});
    try stdout.print("  5. for 패턴: for (slice) |val| 또는 for (slice, 0..) |val, idx|\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 배열과 슬라이스 안전성을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 다음: 1-8. 고급 메모리 패턴과 자기 참조 구조체\\n", .{});
}

// ============================================================================
// 테스트: 배열과 슬라이스 검증
// ============================================================================

test "static array basics" {
    const arr: [3]i32 = [_]i32{ 1, 2, 3 };
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqual(@as(i32, 2), arr[1]);
}

test "array to slice" {
    var arr: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    const slice: []i32 = &arr;
    try std.testing.expectEqual(@as(usize, 5), slice.len);
    try std.testing.expectEqual(@as(i32, 30), slice[2]);
}

test "slice range" {
    var arr: [10]i32 = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const partial: []i32 = arr[3..8];
    try std.testing.expectEqual(@as(usize, 5), partial.len);
    try std.testing.expectEqual(@as(i32, 3), partial[0]);
    try std.testing.expectEqual(@as(i32, 7), partial[4]);
}

test "string slicing" {
    const text: []const u8 = "Hello";
    try std.testing.expectEqual(@as(usize, 5), text.len);
    try std.testing.expectEqual(@as(u8, 'H'), text[0]);
    try std.testing.expectEqual(@as(u8, 'o'), text[4]);
}

test "score manager init" {
    var manager = ScoreManager.init();
    try std.testing.expectEqual(@as(usize, 0), manager.count);
}

test "score manager add and retrieve" {
    var manager = ScoreManager.init();
    try manager.addScore(90);
    try manager.addScore(85);

    try std.testing.expectEqual(@as(usize, 2), manager.count);

    const scores = manager.getScores();
    try std.testing.expectEqual(@as(u32, 90), scores[0]);
    try std.testing.expectEqual(@as(u32, 85), scores[1]);
}

test "score manager average" {
    var manager = ScoreManager.init();
    try manager.addScore(100);
    try manager.addScore(80);

    const avg = manager.getAverage();
    try std.testing.expectEqual(@as(f32, 90.0), avg);
}

test "score manager max and min" {
    var manager = ScoreManager.init();
    try manager.addScore(50);
    try manager.addScore(90);
    try manager.addScore(70);

    try std.testing.expectEqual(@as(?u32, 90), manager.getMax());
    try std.testing.expectEqual(@as(?u32, 50), manager.getMin());
}

test "slice comparison" {
    const arr1: [3]i32 = [_]i32{ 1, 2, 3 };
    const arr2: [3]i32 = [_]i32{ 1, 2, 3 };
    const arr3: [3]i32 = [_]i32{ 1, 2, 4 };

    try std.testing.expect(std.mem.eql(i32, &arr1, &arr2));
    try std.testing.expect(!std.mem.eql(i32, &arr1, &arr3));
}
