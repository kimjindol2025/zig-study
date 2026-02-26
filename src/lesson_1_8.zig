/// src/lesson_1_8.zig - Zig 전공 101: 1-8. 열거형(Enums)과 태그된 공용체(Tagged Unions)
///
/// Assignment 1-8: 상태 설계와 안전한 상태 관리
///
/// 철학: "상태는 타입이어야 한다"
/// Zig의 열거형과 태그된 공용체는 불가능한 상태를 컴파일 타임에 배제한다.

const std = @import("std");

// ============================================================================
// 1️⃣ 기본 열거형 (Basic Enums)
// ============================================================================

/// 신호등의 상태를 나타내는 열거형
const TrafficLight = enum {
    Red,
    Yellow,
    Green,
};

/// 나이별 카테고리 (정수 값 지정)
const AgeGroup = enum(u8) {
    Child = 0,     // 0-12
    Teen = 13,     // 13-19
    Adult = 20,    // 20-64
    Senior = 65,   // 65+
};

/// 파일 열기 모드
const FileMode = enum {
    Read,
    Write,
    Append,
};

// ============================================================================
// 2️⃣ 열거형의 메서드
// ============================================================================

/// 신호등 상태의 진행을 나타냅니다.
fn nextTrafficLight(current: TrafficLight) TrafficLight {
    return switch (current) {
        .Red => .Yellow,
        .Yellow => .Green,
        .Green => .Red,
    };
}

/// 신호등의 대기 시간(초)을 반환합니다.
fn getWaitTime(light: TrafficLight) u32 {
    return switch (light) {
        .Red => 30,
        .Yellow => 5,
        .Green => 25,
    };
}

/// 신호등 상태를 텍스트로 반환합니다.
fn toString(light: TrafficLight) []const u8 {
    return switch (light) {
        .Red => "🔴 정지",
        .Yellow => "🟡 주의",
        .Green => "🟢 진행",
    };
}

// ============================================================================
// 3️⃣ 태그된 공용체 (Tagged Unions)
// ============================================================================

/// 프로그램의 결과를 나타냅니다.
const Result = union(enum) {
    Success: i32,           // 성공: 값
    Failure: []const u8,    // 실패: 에러 메시지
    Pending,                // 대기 중
};

/// 네트워크 응답 상태
const NetworkResponse = union(enum) {
    Loading: u32,           // 로딩 중: 진행도 %
    Success: []const u8,    // 성공: 데이터
    Error: []const u8,      // 에러: 메시지
    Timeout,                // 타임아웃
};

/// 사용자 로그인 상태
const LoginStatus = union(enum) {
    LoggedOut,
    LoggedIn: struct {
        username: []const u8,
        timestamp: u64,
    },
    Locked: u32,  // 잠금 시간 (초)
};

// ============================================================================
// 4️⃣ 태그된 공용체의 활용
// ============================================================================

/// Result의 상태를 확인합니다.
fn handleResult(result: Result) void {
    switch (result) {
        .Success => |value| {
            std.debug.print("성공: {}\n", .{value});
        },
        .Failure => |err_msg| {
            std.debug.print("실패: {s}\n", .{err_msg});
        },
        .Pending => {
            std.debug.print("대기 중...\n", .{});
        },
    }
}

/// 네트워크 응답을 처리합니다.
fn handleNetworkResponse(response: NetworkResponse) void {
    switch (response) {
        .Loading => |progress| {
            std.debug.print("로딩 중: {}%\n", .{progress});
        },
        .Success => |data| {
            std.debug.print("성공: {s}\n", .{data});
        },
        .Error => |err_msg| {
            std.debug.print("에러: {s}\n", .{err_msg});
        },
        .Timeout => {
            std.debug.print("타임아웃 발생\n", .{});
        },
    }
}

/// 로그인 상태를 확인합니다.
fn checkLoginStatus(status: LoginStatus) void {
    switch (status) {
        .LoggedOut => {
            std.debug.print("로그아웃 상태\n", .{});
        },
        .LoggedIn => |info| {
            std.debug.print("로그인: {} (시간: {})\n", .{ info.username, info.timestamp });
        },
        .Locked => |seconds| {
            std.debug.print("계정 잠금 ({}초)\n", .{seconds});
        },
    }
}

// ============================================================================
// 5️⃣ 열거형 메서드 활용
// ============================================================================

/// 파일 모드를 설명하는 구조체
const FileModeDescription = struct {
    mode: FileMode,

    fn canRead(self: FileModeDescription) bool {
        return self.mode == .Read;
    }

    fn canWrite(self: FileModeDescription) bool {
        return switch (self.mode) {
            .Write, .Append => true,
            .Read => false,
        };
    }

    fn description(self: FileModeDescription) []const u8 {
        return switch (self.mode) {
            .Read => "읽기 전용",
            .Write => "쓰기 (기존 파일 덮어쓰기)",
            .Append => "추가 쓰기",
        };
    }
};

// ============================================================================
// 6️⃣ Assignment 1-8: 상태 머신 (State Machine)
// ============================================================================

/// 주문 시스템의 상태
const OrderStatus = enum {
    Pending,      // 대기
    Processing,   // 처리 중
    Shipped,      // 배송 중
    Delivered,    // 배송 완료
    Cancelled,    // 취소됨
};

/// 주문을 나타내는 구조체
const Order = struct {
    id: u32,
    status: OrderStatus,
    item: []const u8,
    quantity: u32,

    fn init(id: u32, item: []const u8, quantity: u32) Order {
        return .{
            .id = id,
            .status = .Pending,
            .item = item,
            .quantity = quantity,
        };
    }

    /// 상태를 다음 단계로 진행합니다.
    fn advance(self: *Order) !void {
        self.status = switch (self.status) {
            .Pending => .Processing,
            .Processing => .Shipped,
            .Shipped => .Delivered,
            .Delivered => return error.AlreadyDelivered,
            .Cancelled => return error.CancelledOrder,
        };
    }

    /// 주문을 취소합니다.
    fn cancel(self: *Order) !void {
        if (self.status == .Delivered) {
            return error.CannotCancelDelivered;
        }
        self.status = .Cancelled;
    }

    /// 상태를 텍스트로 반환합니다.
    fn statusString(self: Order) []const u8 {
        return switch (self.status) {
            .Pending => "⏳ 대기",
            .Processing => "🔄 처리 중",
            .Shipped => "📦 배송 중",
            .Delivered => "✅ 배송 완료",
            .Cancelled => "❌ 취소됨",
        };
    }

    /// 주문 정보를 출력합니다.
    fn print(self: Order) void {
        std.debug.print("[주문 #{}] {s} (수량: {}) - {}\\n", .{
            self.id,
            self.item,
            self.quantity,
            self.statusString(),
        });
    }
};

// ============================================================================
// 7️⃣ 태그 없는 공용체 vs 태그된 공용체
// ============================================================================

/// 태그 없는 공용체 (위험함!)
const UnsafeUnion = union {
    int_val: i32,
    float_val: f32,
};

/// 태그된 공용체 (안전함!)
const SafeUnion = union(enum) {
    IntValue: i32,
    FloatValue: f32,
};

// ============================================================================
// 메인 함수: 모든 열거형과 태그된 공용체 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-8. 열거형과 태그된 공용체\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // ============================================================================
    // 1️⃣ 기본 열거형
    // ============================================================================

    try stdout.print("1️⃣ 기본 열거형 (Enums)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const light: TrafficLight = .Red;
    try stdout.print("신호등 상태: {}\\n", .{@intFromEnum(light)});
    try stdout.print("신호등 표시: {s}\\n", .{toString(light)});
    try stdout.print("대기 시간: {}초\\n", .{getWaitTime(light)});

    const next_light = nextTrafficLight(light);
    try stdout.print("다음 신호등: {s}\\n\\n", .{toString(next_light)});

    // ============================================================================
    // 2️⃣ 열거형 순회
    // ============================================================================

    try stdout.print("2️⃣ 신호등 상태 순환\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var current = TrafficLight.Red;
    try stdout.print("신호등 변화: ", .{});
    for (0..8) |_| {
        try stdout.print("{s} → ", .{toString(current)});
        current = nextTrafficLight(current);
    }
    try stdout.print("{s}\\n\\n", .{toString(current)});

    // ============================================================================
    // 3️⃣ 정수 값을 가진 열거형
    // ============================================================================

    try stdout.print("3️⃣ 정수 값을 가진 열거형\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const child: AgeGroup = .Child;
    const adult: AgeGroup = .Adult;

    try stdout.print("Child 값: {}\\n", .{@intFromEnum(child)});
    try stdout.print("Adult 값: {}\\n\\n", .{@intFromEnum(adult)});

    // ============================================================================
    // 4️⃣ 태그된 공용체 - Result
    // ============================================================================

    try stdout.print("4️⃣ 태그된 공용체 (Tagged Unions) - Result\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const result1: Result = .{ .Success = 42 };
    const result2: Result = .{ .Failure = "연산 오류 발생" };
    const result3: Result = .Pending;

    try stdout.print("Result 1: ", .{});
    handleResult(result1);
    try stdout.print("Result 2: ", .{});
    handleResult(result2);
    try stdout.print("Result 3: ", .{});
    handleResult(result3);
    try stdout.print("\\n", .{});

    // ============================================================================
    // 5️⃣ 태그된 공용체 - NetworkResponse
    // ============================================================================

    try stdout.print("5️⃣ 태그된 공용체 - NetworkResponse\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const network1: NetworkResponse = .{ .Loading = 45 };
    const network2: NetworkResponse = .{ .Success = "{\"status\": \"ok\"}" };
    const network3: NetworkResponse = .Timeout;

    try stdout.print("상태 1: ", .{});
    handleNetworkResponse(network1);
    try stdout.print("상태 2: ", .{});
    handleNetworkResponse(network2);
    try stdout.print("상태 3: ", .{});
    handleNetworkResponse(network3);
    try stdout.print("\\n", .{});

    // ============================================================================
    // 6️⃣ 태그된 공용체 - LoginStatus
    // ============================================================================

    try stdout.print("6️⃣ 태그된 공용체 - LoginStatus (중첩된 구조체)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const login1: LoginStatus = .LoggedOut;
    const login2: LoginStatus = .{
        .LoggedIn = .{
            .username = "alice",
            .timestamp = 1677000000,
        },
    };
    const login3: LoginStatus = .{ .Locked = 300 };

    try stdout.print("로그인 상태 1: ", .{});
    checkLoginStatus(login1);
    try stdout.print("로그인 상태 2: ", .{});
    checkLoginStatus(login2);
    try stdout.print("로그인 상태 3: ", .{});
    checkLoginStatus(login3);
    try stdout.print("\\n", .{});

    // ============================================================================
    // 7️⃣ 파일 모드와 메서드
    // ============================================================================

    try stdout.print("7️⃣ 열거형 메서드 - FileMode\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const read_mode = FileModeDescription{ .mode = .Read };
    const write_mode = FileModeDescription{ .mode = .Write };

    try stdout.print("모드 1: {s}\\n", .{read_mode.description()});
    try stdout.print("  - 읽기 가능? {}\\n", .{read_mode.canRead()});
    try stdout.print("  - 쓰기 가능? {}\\n", .{read_mode.canWrite()});

    try stdout.print("모드 2: {s}\\n", .{write_mode.description()});
    try stdout.print("  - 읽기 가능? {}\\n", .{write_mode.canRead()});
    try stdout.print("  - 쓰기 가능? {}\\n\\n", .{write_mode.canWrite()});

    // ============================================================================
    // 8️⃣ Assignment 1-8: 주문 상태 머신
    // ============================================================================

    try stdout.print("8️⃣ Assignment 1-8: 주문 상태 머신\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var order = Order.init(1001, "Zig 교과서", 2);

    try stdout.print("📝 주문 상태 전이:\\n", .{});
    order.print();

    try order.advance();
    order.print();

    try order.advance();
    order.print();

    try order.advance();
    order.print();

    try order.advance();
    order.print();

    try stdout.print("\\n", .{});

    // 배송 후 취소 시도 (에러)
    var order2 = Order.init(1002, "Zig 고급 과정", 1);
    try order2.advance();
    try order2.advance();
    try order2.advance();

    try stdout.print("배송 완료 상태에서 취소 시도: ", .{});
    if (order2.cancel()) {
        try stdout.print("성공\\n", .{});
    } else |err| {
        try stdout.print("에러 - {}\n", .{err});
    }

    try stdout.print("\\n", .{});

    // ============================================================================
    // 9️⃣ 태그 없는 공용체 vs 태그된 공용체
    // ============================================================================

    try stdout.print("9️⃣ 안전성: 태그 없는 공용체 vs 태그된 공용체\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("태그 없는 공용체 (위험!):\\n", .{});
    try stdout.print("  var unsafe: UnsafeUnion = .{{ .int_val = 42 }};\\n", .{});
    try stdout.print("  unsafe.float_val를 읽으면? → 정의되지 않은 행동 (UB)!\\n\\n", .{});

    try stdout.print("태그된 공용체 (안전!):\\n", .{});
    try stdout.print("  var safe: SafeUnion = .{{ .IntValue = 42 }};\\n", .{});
    try stdout.print("  switch (safe) {{\\n", .{});
    try stdout.print("    .IntValue => |v| {{ ... }}\\n", .{});
    try stdout.print("    .FloatValue => |v| {{ ... }}\\n", .{});
    try stdout.print("  }}  ← 모든 경우를 다루어야 함!\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-8 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-8 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ 기본 열거형: enum {{ Red, Yellow, Green }}\\n", .{});
    try stdout.print("  ✓ 정수 값 열거형: enum(u8) {{ Child = 0, Adult = 20 }}\\n", .{});
    try stdout.print("  ✓ 열거형 메서드: switch를 통한 상태별 처리\\n", .{});
    try stdout.print("  ✓ 태그된 공용체: union(enum) {{ Success: i32, Failure: []const u8 }}\\n", .{});
    try stdout.print("  ✓ 패턴 매칭: switch (result) {{ .Success => |v| {{ ... }} }}\\n", .{});
    try stdout.print("  ✓ 상태 머신: 상태 전이의 안전한 설계\\n", .{});
    try stdout.print("  ✓ 중첩 구조체: union 내에 struct 포함\\n", .{});
    try stdout.print("  ✓ 컴파일 타임 안전성: 모든 경우를 다루도록 강제\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 열거형은 상태의 집합을 타입으로 표현\\n", .{});
    try stdout.print("  2. 태그된 공용체는 상태별 데이터를 안전하게 관리\\n", .{});
    try stdout.print("  3. 불가능한 상태는 컴파일 타임에 배제\\n", .{});
    try stdout.print("  4. 모든 경우를 switch에서 다루어야 함 (exhaustiveness check)\\n", .{});
    try stdout.print("  5. 태그 없는 공용체는 피하고 태그된 공용체를 사용\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 상태 설계 정석을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 다음: 1-9. 제네릭 프로그래밍과 comptime의 기초\\n", .{});
}

// ============================================================================
// 테스트: 열거형과 태그된 공용체 검증
// ============================================================================

test "traffic light next state" {
    const current = TrafficLight.Red;
    const next = nextTrafficLight(current);
    try std.testing.expectEqual(TrafficLight.Yellow, next);
}

test "traffic light wait time" {
    try std.testing.expectEqual(@as(u32, 30), getWaitTime(.Red));
    try std.testing.expectEqual(@as(u32, 5), getWaitTime(.Yellow));
    try std.testing.expectEqual(@as(u32, 25), getWaitTime(.Green));
}

test "age group values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AgeGroup.Child));
    try std.testing.expectEqual(@as(u8, 20), @intFromEnum(AgeGroup.Adult));
}

test "result success case" {
    const result: Result = .{ .Success = 42 };
    try std.testing.expectEqual(@as(i32, 42), result.Success);
}

test "result failure case" {
    const result: Result = .{ .Failure = "error" };
    try std.testing.expect(std.mem.eql(u8, result.Failure, "error"));
}

test "order init" {
    const order = Order.init(1, "Book", 2);
    try std.testing.expectEqual(@as(u32, 1), order.id);
    try std.testing.expectEqual(OrderStatus.Pending, order.status);
}

test "order advance state" {
    var order = Order.init(1, "Book", 1);
    try order.advance();
    try std.testing.expectEqual(OrderStatus.Processing, order.status);

    try order.advance();
    try std.testing.expectEqual(OrderStatus.Shipped, order.status);
}

test "order cancel before delivery" {
    var order = Order.init(1, "Book", 1);
    try order.cancel();
    try std.testing.expectEqual(OrderStatus.Cancelled, order.status);
}

test "order cannot cancel after delivery" {
    var order = Order.init(1, "Book", 1);
    try order.advance();
    try order.advance();
    try order.advance();
    try order.advance();

    const result = order.cancel();
    try std.testing.expectError(error.CannotCancelDelivered, result);
}

test "file mode read only" {
    const mode = FileModeDescription{ .mode = .Read };
    try std.testing.expect(mode.canRead());
    try std.testing.expect(!mode.canWrite());
}

test "file mode write" {
    const mode = FileModeDescription{ .mode = .Write };
    try std.testing.expect(!mode.canRead());
    try std.testing.expect(mode.canWrite());
}

test "safe union access" {
    const val: SafeUnion = .{ .IntValue = 42 };
    try std.testing.expectEqual(@as(i32, 42), val.IntValue);
}
