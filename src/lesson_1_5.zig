/// src/lesson_1_5.zig - Zig 전공 101: 1-5. 구조체(Structs)와 메서드
///
/// Assignment 1-5: 객체 설계 과제
///
/// 철학: "데이터와 기능을 함께 설계한다"
/// 구조체는 단순한 데이터 컨테이너가 아니라, 관련 로직을 포함한 설계의 뼈대다.

const std = @import("std");

// ============================================================================
// 1️⃣ 기본 구조체 정의와 초기화
// ============================================================================

/// 사용자 정보를 나타내는 구조체입니다.
const User = struct {
    id: u32,
    name: []const u8,
    is_active: bool = true,  // 기본값 설정 가능

    /// 사용자 정보를 출력합니다.
    pub fn printInfo(self: User) void {
        std.debug.print("User(ID: {}, Name: {s}, Active: {})\n", .{ self.id, self.name, self.is_active });
    }
};

// ============================================================================
// 2️⃣ 메서드를 포함한 구조체
// ============================================================================

/// 직사각형을 나타내는 구조체입니다.
const Rectangle = struct {
    width: f32,
    height: f32,

    /// 직사각형의 면적을 계산합니다.
    /// self: Rectangle으로 값을 받으므로 read-only입니다.
    pub fn area(self: Rectangle) f32 {
        return self.width * self.height;
    }

    /// 직사각형의 둘레를 계산합니다.
    pub fn perimeter(self: Rectangle) f32 {
        return 2.0 * (self.width + self.height);
    }

    /// 직사각형의 크기를 변경합니다.
    /// self: *Rectangle으로 포인터를 받으므로 내부 값을 수정할 수 있습니다.
    pub fn scale(self: *Rectangle, factor: f32) void {
        self.width *= factor;
        self.height *= factor;
    }

    /// 직사각형의 정보를 출력합니다.
    pub fn printInfo(self: Rectangle) void {
        std.debug.print("Rectangle({d:.1}x{d:.1}) - Area: {d:.1}, Perimeter: {d:.1}\n",
            .{ self.width, self.height, self.area(), self.perimeter() });
    }
};

// ============================================================================
// 3️⃣ 정적 메서드 (Static Method) - init 생성자 패턴
// ============================================================================

/// 좌표를 나타내는 구조체입니다.
const Point = struct {
    x: i32,
    y: i32,

    /// Point를 생성하는 정적 메서드입니다.
    /// self를 받지 않으므로 Point.init()으로 호출합니다.
    pub fn init(x: i32, y: i32) Point {
        return Point{ .x = x, .y = y };
    }

    /// 두 점 사이의 맨해튼 거리를 계산합니다.
    pub fn manhattanDistance(self: Point, other: Point) i32 {
        const dx = if (self.x > other.x) self.x - other.x else other.x - self.x;
        const dy = if (self.y > other.y) self.y - other.y else other.y - self.y;
        return dx + dy;
    }

    /// 점의 정보를 출력합니다.
    pub fn printInfo(self: Point) void {
        std.debug.print("Point({}, {})\n", .{ self.x, self.y });
    }
};

// ============================================================================
// 4️⃣ Assignment 1-5: Student 구조체 설계
// ============================================================================

/// Assignment 1-5: 학생 정보를 나타내는 구조체입니다.
const Student = struct {
    name: []const u8,
    score: u32,

    /// Student를 생성하는 정적 메서드입니다.
    pub fn init(name: []const u8, score: u32) Student {
        return Student{
            .name = name,
            .score = score,
        };
    }

    /// 학생이 합격했는지 판단합니다. (60점 이상 = true)
    pub fn isPassed(self: Student) bool {
        return self.score >= 60;
    }

    /// 학생의 학점을 반환합니다.
    pub fn getGrade(self: Student) []const u8 {
        return if (self.score >= 90)
            "A"
        else if (self.score >= 80)
            "B"
        else if (self.score >= 70)
            "C"
        else if (self.score >= 60)
            "D"
        else
            "F";
    }

    /// 학생 정보를 출력합니다.
    pub fn printInfo(self: Student) void {
        const status = if (self.isPassed()) "합격" else "불합격";
        std.debug.print("학생: {s}, 점수: {}, 학점: {s}, 상태: {s}\n",
            .{ self.name, self.score, self.getGrade(), status });
    }
};

// ============================================================================
// 5️⃣ 고급: 메모리 레이아웃 제어
// ============================================================================

/// 일반 struct: 컴파일러가 성능 최적화를 위해 필드 순서를 바꿀 수 있습니다.
const RegularStruct = struct {
    a: u8,
    b: u32,
    c: u8,
};

/// packed struct: 필드 순서를 엄격히 지킵니다. (비트 단위)
/// 하드웨어 제어나 네트워크 프로토콜 등에서 필요합니다.
const PackedStruct = packed struct {
    a: u8,
    b: u32,
    c: u8,
};

/// extern struct: C언어의 구조체 레이아웃과 호환됩니다.
/// C 라이브러리와 통신할 때 사용합니다.
const ExternStruct = extern struct {
    x: i32,
    y: i32,
};

// ============================================================================
// 6️⃣ 익명 구조체 (Anonymous Struct)
// ============================================================================

/// 익명 구조체는 임시 데이터를 묶을 때 유용합니다.
fn printAnonymousStruct() void {
    // std.debug.print에서 사용하는 .{ ... } 형태가 익명 구조체입니다.
    const data = .{
        .name = "익명 구조체",
        .value = 42,
        .active = true,
    };

    std.debug.print("익명 구조체: name={s}, value={}, active={}\n",
        .{ data.name, data.value, data.active });
}

// ============================================================================
// 메인 함수: 모든 구조체 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-5. 구조체와 메서드\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    // ============================================================================
    // 1️⃣ 기본 구조체 정의와 초기화
    // ============================================================================

    try stdout.print("1️⃣ 기본 구조체 정의와 초기화\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const user1 = User{
        .id = 1,
        .name = "Zig-Scholar",
    };

    const user2 = User{
        .id = 2,
        .name = "Python-Master",
        .is_active = false,
    };

    try stdout.print("구조체 생성:\n", .{});
    user1.printInfo();
    user2.printInfo();
    try stdout.print("\n", .{});

    // ============================================================================
    // 2️⃣ 메서드를 포함한 구조체
    // ============================================================================

    try stdout.print("2️⃣ 메서드를 포함한 구조체\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    var rect = Rectangle{ .width = 10.0, .height = 5.0 };

    try stdout.print("직사각형: 가로 {d:.1}, 세로 {d:.1}\n", .{ rect.width, rect.height });
    try stdout.print("  면적: {d:.1}\n", .{rect.area()});
    try stdout.print("  둘레: {d:.1}\n\n", .{rect.perimeter()});

    // 포인터를 사용하여 구조체 내부 값 수정
    try stdout.print("scale(2.0) 적용 후:\n", .{});
    rect.scale(2.0);
    rect.printInfo();
    try stdout.print("\n", .{});

    // ============================================================================
    // 3️⃣ 정적 메서드 (Static Method) - init 생성자 패턴
    // ============================================================================

    try stdout.print("3️⃣ 정적 메서드 (Static Method) - init 생성자\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    const p1 = Point.init(10, 20);
    const p2 = Point.init(15, 25);

    try stdout.print("점 생성:\n", .{});
    p1.printInfo();
    p2.printInfo();

    const distance = p1.manhattanDistance(p2);
    try stdout.print("맨해튼 거리: {}\n\n", .{distance});

    // ============================================================================
    // 4️⃣ Assignment 1-5: Student 구조체
    // ============================================================================

    try stdout.print("4️⃣ Assignment 1-5: Student 구조체\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try stdout.print("📝 구조체 정의:\n", .{});
    try stdout.print("const Student = struct {{\n", .{});
    try stdout.print("    name: []const u8,\n", .{});
    try stdout.print("    score: u32,\n", .{});
    try stdout.print("    \n", .{});
    try stdout.print("    pub fn init(name, score) Student { ... }\n", .{});
    try stdout.print("    pub fn isPassed(self) bool { ... }  // 60점 이상\n", .{});
    try stdout.print("}};\n\n", .{});

    // 학생 객체 생성
    const student1 = Student.init("김철학", 85);
    const student2 = Student.init("이지그", 55);
    const student3 = Student.init("박러스트", 92);

    try stdout.print("📋 학생 정보:\n", .{});
    student1.printInfo();
    student2.printInfo();
    student3.printInfo();
    try stdout.print("\n", .{});

    // isPassed() 메서드 테스트
    try stdout.print("💯 합격 여부:\n", .{});
    try stdout.print("  {s}: {}\n", .{ student1.name, student1.isPassed() });
    try stdout.print("  {s}: {}\n", .{ student2.name, student2.isPassed() });
    try stdout.print("  {s}: {}\n", .{ student3.name, student3.isPassed() });
    try stdout.print("\n", .{});

    // ============================================================================
    // 5️⃣ 메모리 레이아웃 (크기 비교)
    // ============================================================================

    try stdout.print("5️⃣ 메모리 레이아웃 (구조체 크기)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    try stdout.print("일반 struct 크기: {} bytes\n", .{@sizeOf(RegularStruct)});
    try stdout.print("packed struct 크기: {} bytes\n", .{@sizeOf(PackedStruct)});
    try stdout.print("extern struct 크기: {} bytes\n\n", .{@sizeOf(ExternStruct)});

    try stdout.print("⚠️  일반 struct는 컴파일러가 성능 최적화를 위해 필드 순서를 바꿀 수 있습니다.\n", .{});
    try stdout.print("   packed struct는 필드 순서를 엄격히 지킵니다.\n", .{});
    try stdout.print("   extern struct는 C 언어와 호환됩니다.\n\n", .{});

    // ============================================================================
    // 6️⃣ 익명 구조체
    // ============================================================================

    try stdout.print("6️⃣ 익명 구조체 (Anonymous Struct)\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\n\n", .{});

    printAnonymousStruct();
    try stdout.print("\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-5 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\n", .{});
    try stdout.print("✅ Assignment 1-5 완료!\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\n\n", .{});

    try stdout.print("📋 정리:\n", .{});
    try stdout.print("  ✓ 구조체 정의: 필드와 기본값\n", .{});
    try stdout.print("  ✓ 메서드: self 또는 *self로 자기 자신 참조\n", .{});
    try stdout.print("  ✓ 정적 메서드: self 없이 init 생성자 패턴\n", .{});
    try stdout.print("  ✓ Assignment: Student 구조체 + isPassed()\n", .{});
    try stdout.print("  ✓ 메모리 레이아웃: struct vs packed vs extern\n", .{});
    try stdout.print("  ✓ 익명 구조체: 임시 데이터 묶기\n\n", .{});

    try stdout.print("🎯 핵심 원칙:\n", .{});
    try stdout.print("  1. 구조체는 데이터 + 기능의 묶음\n", .{});
    try stdout.print("  2. self 매개변수로 메서드 구현\n", .{});
    try stdout.print("  3. *self로 내부 값 수정 가능\n", .{});
    try stdout.print("  4. 정적 메서드(init)로 객체 생성\n", .{});
    try stdout.print("  5. 메모리 레이아웃은 설계에 영향을 줌\n\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 구조체와 메서드를 이해했습니다!\n", .{});
    try stdout.print("🚀 다음: 1-6. 포인터와 메모리 관리의 기초\n", .{});
}

// ============================================================================
// 테스트: 구조체와 메서드 검증
// ============================================================================

test "user creation and printInfo" {
    const user = User{
        .id = 1,
        .name = "Test User",
    };
    try std.testing.expectEqual(@as(u32, 1), user.id);
    try std.testing.expectEqualStrings("Test User", user.name);
    try std.testing.expect(user.is_active);
}

test "rectangle area and perimeter" {
    const rect = Rectangle{ .width = 10.0, .height = 5.0 };
    try std.testing.expectEqual(@as(f32, 50.0), rect.area());
    try std.testing.expectEqual(@as(f32, 30.0), rect.perimeter());
}

test "rectangle scale" {
    var rect = Rectangle{ .width = 10.0, .height = 5.0 };
    rect.scale(2.0);
    try std.testing.expectEqual(@as(f32, 20.0), rect.width);
    try std.testing.expectEqual(@as(f32, 10.0), rect.height);
}

test "point init and distance" {
    const p1 = Point.init(0, 0);
    const p2 = Point.init(3, 4);
    try std.testing.expectEqual(@as(i32, 0), p1.x);
    try std.testing.expectEqual(@as(i32, 0), p1.y);
    try std.testing.expectEqual(@as(i32, 7), p1.manhattanDistance(p2));
}

test "student init and isPassed" {
    const student1 = Student.init("Alice", 85);
    const student2 = Student.init("Bob", 55);

    try std.testing.expect(student1.isPassed());
    try std.testing.expect(!student2.isPassed());
}

test "student getGrade" {
    const grades = .{
        .{ "Alice", 95, "A" },
        .{ "Bob", 85, "B" },
        .{ "Charlie", 75, "C" },
        .{ "Diana", 65, "D" },
        .{ "Eve", 50, "F" },
    };

    inline for (grades) |g| {
        const student = Student.init(g[0], g[1]);
        try std.testing.expectEqualStrings(g[2], student.getGrade());
    }
}

test "struct sizes" {
    // 이 테스트는 구조체 크기를 확인합니다.
    const regular_size = @sizeOf(RegularStruct);
    const packed_size = @sizeOf(PackedStruct);
    const extern_size = @sizeOf(ExternStruct);

    try std.testing.expect(regular_size >= 6);  // 최소 a(1) + b(4) + c(1)
    try std.testing.expect(packed_size == 6);   // 정확히 1+4+1
    try std.testing.expect(extern_size == 8);   // x(4) + y(4)
}
