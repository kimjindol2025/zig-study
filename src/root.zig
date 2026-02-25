/// src/root.zig - 라이브러리 루트
///
/// 이 파일은 zig-study를 라이브러리로 사용할 때의 진입점입니다.

const std = @import("std");

pub const hello = "Hello from zig-study library!";

/// 간단한 덧셈 함수
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "library: add function" {
    const result = add(2, 3);
    try std.testing.expectEqual(@as(i32, 5), result);
}

test "library: hello message" {
    try std.testing.expectEqualStrings("Hello from zig-study library!", hello);
}
