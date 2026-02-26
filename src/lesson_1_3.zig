/// src/lesson_1_3.zig - Zig 전공 101: 1-3. 제어문 - if, while, for 그리고 특별한 switch
///
/// Assignment 1-3: 흐름 설계 과제
///
/// 철학: "모호함을 남기지 않는다"
/// 프로그램의 모든 분기와 루프는 명확하게 정의되어야 한다.

const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-3. 제어문 - if, while, for 그리고 특별한 switch\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    // ============================================================================
    // 1️⃣ if문: 선택과 할당
    // ============================================================================

    try stdout.print("1️⃣ if문: 선택과 할당\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const score: u8 = 85;

    // if를 표현식으로 사용하여 결과를 변수에 할당
    const grade = if (score >= 90)
        "A"
    else if (score >= 80)
        "B"
    else if (score >= 70)
        "C"
    else
        "F";

    try stdout.print("시험 점수: {}\n", .{score});
    try stdout.print("학점: {s}\n\n", .{grade});

    // 다른 예제: 나이에 따른 분류
    const age: u8 = 25;
    const category = if (age < 13)
        "어린이"
    else if (age < 20)
        "청소년"
    else if (age < 60)
        "성인"
    else
        "노년";

    try stdout.print("나이: {}\n", .{age});
    try stdout.print("분류: {s}\n\n", .{category});

    try stdout.print("📝 주의: if의 조건식은 반드시 bool 타입이어야 합니다!\n", .{});
    try stdout.print("   (C처럼 0을 false로 간주하지 않음)\n\n", .{});

    // ============================================================================
    // 2️⃣ while: 조건 기반 반복
    // ============================================================================

    try stdout.print("2️⃣ while: 조건 기반 반복\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    var counter: u32 = 0;
    var sum_while: u32 = 0;

    try stdout.print("1부터 100까지의 합:\n", .{});
    while (counter < 100) {
        counter += 1;
        sum_while += counter;
    }

    try stdout.print("  합계: {}\n\n", .{sum_while});

    // continue 표현식이 있는 while
    var num: u32 = 1;
    try stdout.print("3의 배수 찾기 (1~30):\n  ", .{});
    while (num <= 30) : (num += 1) {  // : (num += 1) = continue 시 실행
        if (num % 3 == 0) {
            try stdout.print("{} ", .{num});
        }
    }
    try stdout.print("\n\n", .{});

    // ============================================================================
    // 3️⃣ for: 배열/슬라이스 순회
    // ============================================================================

    try stdout.print("3️⃣ for: 배열/슬라이스 순회\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const items = [_]i32{ 10, 20, 30, 40, 50 };

    try stdout.print("배열: [10, 20, 30, 40, 50]\n\n", .{});

    // for (배열) |요소|
    try stdout.print("요소 출력:\n", .{});
    for (items) |item| {
        try stdout.print("  {}\n", .{item});
    }
    try stdout.print("\n", .{});

    // for (배열, 시작값..) |요소, 인덱스|
    try stdout.print("인덱스와 함께 출력:\n", .{});
    for (items, 0..) |item, idx| {
        try stdout.print("  Index {}: value {}\n", .{ idx, item });
    }
    try stdout.print("\n", .{});

    // Assignment 1-3: 배열 합계
    var array_sum: i32 = 0;
    for (items) |item| {
        array_sum += item;
    }

    try stdout.print("배열 요소의 합계: {}\n\n", .{array_sum});

    // ============================================================================
    // 4️⃣ switch: 전수 검사(Exhaustiveness)의 강제
    // ============================================================================

    try stdout.print("4️⃣ switch: 전수 검사(Exhaustiveness)의 강제\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    // Assignment 1-3: 홀수/짝수 판별
    try stdout.print("홀수/짝수 판별 (1~5):\n", .{});
    for (1..6) |number| {
        const parity = switch (number) {
            1, 3, 5 => "홀수",
            2, 4 => "짝수",
            else => "알 수 없음",
        };
        try stdout.print("  {}: {s}\n", .{ number, parity });
    }
    try stdout.print("\n", .{});

    // 상태 코드 예제
    const status: u8 = 2;
    const message = switch (status) {
        1 => "준비 중",
        2 => "진행 중",
        3 => "완료",
        4 => "오류",
        else => "알 수 없는 상태",
    };

    try stdout.print("상태 코드: {}\n", .{status});
    try stdout.print("메시지: {s}\n\n", .{message});

    // ============================================================================
    // 5️⃣ 블록 식 (Block Expression)
    // ============================================================================

    try stdout.print("5️⃣ 블록 식 (Block Expression)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    // 블록 내에서 복잡한 로직을 수행 후 값 반환
    const final_value = blk: {
        var result: i32 = 0;
        for (items) |item| {
            result += item;
        }
        // break :blk 값; 형태로 블록을 빠져나오면서 값 반환
        break :blk result;
    };

    try stdout.print("블록 식을 이용한 계산:\n", .{});
    try stdout.print("  배열의 합 = {}\n\n", .{final_value});

    // 복합 로직 예제
    const processed_value = blk: {
        var temp: i32 = 0;
        for (items, 0..) |item, idx| {
            if (idx % 2 == 0) {  // 짝수 인덱스만
                temp += item;
            }
        }
        break :blk temp;
    };

    try stdout.print("짝수 인덱스 요소의 합:\n", .{});
    try stdout.print("  값 = {} (items[0] + items[2] + items[4])\n\n", .{processed_value});

    // ============================================================================
    // 6️⃣ if와 while의 Optional 패턴 (미리보기)
    // ============================================================================

    try stdout.print("6️⃣ Optional 패턴 (미리보기)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const maybe_value: ?i32 = 42;

    // if를 사용하여 Optional 값을 풀기
    if (maybe_value) |value| {
        try stdout.print("값이 존재함: {}\n", .{value});
    } else {
        try stdout.print("값이 없음\n", .{});
    }

    const maybe_nothing: ?i32 = null;

    if (maybe_nothing) |value| {
        try stdout.print("값이 존재함: {}\n", .{value});
    } else {
        try stdout.print("값이 없음 (null)\n", .{});
    }

    try stdout.print("\n⚠️ Optional 문법:\n", .{});
    try stdout.print("   if (optional_value) |value| { ... } else { ... }\n", .{});
    try stdout.print("   → 이후 메모리 관리 세션에서 상세히 배웁니다\n\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-3 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\n", .{});
    try stdout.print("✅ Assignment 1-3 완료!\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    try stdout.print("📋 정리:\n", .{});
    try stdout.print("  ✓ if문: 표현식으로 사용하여 값 할당\n", .{});
    try stdout.print("  ✓ while: 조건 기반 반복 (continue 표현식)\n", .{});
    try stdout.print("  ✓ for: 배열 순회 (|value, index| 캡처)\n", .{});
    try stdout.print("  ✓ switch: 전수 검사 강제 (else 필수)\n", .{});
    try stdout.print("  ✓ 블록 식: 복잡한 초기화 로직 정리\n", .{});
    try stdout.print("  ✓ Optional: if 패턴으로 안전하게 풀기\n\n", .{});

    try stdout.print("🎯 핵심 원칙:\n", .{});
    try stdout.print("  1. 조건식은 반드시 bool 타입\n", .{});
    try stdout.print("  2. switch는 모든 경우를 처리 (else 필수)\n", .{});
    try stdout.print("  3. for는 배열을 안전하게 순회\n", .{});
    try stdout.print("  4. 제어문은 값을 반환할 수 있음\n\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 모호하지 않은 제어문을 이해했습니다!\n", .{});
    try stdout.print("🚀 다음: 1-4. 함수(Functions) - 매개변수 전달과 에러 핸들링\n", .{});
}

// ============================================================================
// 테스트: 제어문 검증
// ============================================================================

test "if as expression" {
    const score: u8 = 85;
    const grade = if (score >= 90) "A" else if (score >= 80) "B" else "C";
    try std.testing.expectEqualStrings("B", grade);
}

test "while loop sum" {
    var counter: u32 = 0;
    var sum: u32 = 0;
    while (counter < 10) {
        counter += 1;
        sum += counter;
    }
    try std.testing.expectEqual(@as(u32, 55), sum);
}

test "for loop array iteration" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    var sum: i32 = 0;
    for (items) |item| {
        sum += item;
    }
    try std.testing.expectEqual(@as(i32, 15), sum);
}

test "for loop with index" {
    const items = [_]i32{ 10, 20, 30 };
    var indexed_sum: i32 = 0;
    for (items, 0..) |item, idx| {
        indexed_sum += item + @as(i32, @intCast(idx));
    }
    // (10+0) + (20+1) + (30+2) = 10 + 21 + 32 = 63
    try std.testing.expectEqual(@as(i32, 63), indexed_sum);
}

test "switch expression" {
    const number: u8 = 3;
    const parity = switch (number) {
        1, 3, 5 => "odd",
        2, 4 => "even",
        else => "unknown",
    };
    try std.testing.expectEqualStrings("odd", parity);
}

test "block expression" {
    const items = [_]i32{ 10, 20, 30 };
    const result = blk: {
        var sum: i32 = 0;
        for (items) |item| {
            sum += item;
        }
        break :blk sum;
    };
    try std.testing.expectEqual(@as(i32, 60), result);
}

test "optional value with if" {
    const maybe_value: ?i32 = 42;
    var found: bool = false;

    if (maybe_value) |value| {
        found = (value == 42);
    }

    try std.testing.expect(found);
}

test "optional null with if" {
    const maybe_nothing: ?i32 = null;
    var is_null: bool = false;

    if (maybe_nothing) |_| {
        is_null = false;
    } else {
        is_null = true;
    }

    try std.testing.expect(is_null);
}
