/// src/lesson_1_9.zig - Zig 전공 101: 1-9. 할당자(Allocators) - 힙 메모리의 명시적 제어
///
/// Assignment 1-9: 메모리 할당과 자원 관리
///
/// 철학: "메모리 할당은 항상 명시적이고, 반드시 해제해야 한다"
/// Zig에는 '숨겨진 메모리 할당'이 없습니다. 모든 동적 메모리는 Allocator를 통해 관리됩니다.

const std = @import("std");

// ============================================================================
// 1️⃣ Allocator 인터페이스 이해
// ============================================================================

/// 동적 메모리로 생성되는 Person 구조체
const Person = struct {
    name: []u8,
    age: u32,

    fn create(allocator: std.mem.Allocator, name: []const u8, age: u32) !*Person {
        const self = try allocator.create(Person);
        errdefer allocator.destroy(self);

        self.name = try allocator.dupe(u8, name);
        self.age = age;

        return self;
    }

    fn destroy(self: *Person, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn print(self: *const Person) void {
        std.debug.print("Person {{ name: {s}, age: {} }}\n", .{ self.name, self.age });
    }
};

// ============================================================================
// 2️⃣ GeneralPurposeAllocator (범용 할당자)
// ============================================================================

/// 범용 할당자를 사용한 메모리 할당 (권장)
fn generalPurposeAllocatorExample() !void {
    // 범용 할당자 생성
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 구조체 할당
    const person = try Person.create(allocator, "Alice", 30);
    defer person.destroy(allocator);

    person.print();
}

// ============================================================================
// 3️⃣ FixedBufferAllocator (고정 버퍼 할당자)
// ============================================================================

/// 고정 크기의 버퍼에서 할당 (자동 해제, 회귀 불가)
fn fixedBufferAllocatorExample() !void {
    // 스택에 100바이트 버퍼 생성
    var buffer: [100]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    // 문자열 복제
    const hello = try allocator.dupe(u8, "Hello, Zig!");
    _ = hello;  // defer로 해제할 필요 없음 (fba.reset() 호출 시 자동)
}

// ============================================================================
// 4️⃣ 배열 할당 (allocator.alloc)
// ============================================================================

/// 배열을 동적으로 할당합니다.
fn allocateArray(allocator: std.mem.Allocator, size: usize) ![]i32 {
    const array = try allocator.alloc(i32, size);
    return array;
}

/// 배열을 해제합니다.
fn deallocateArray(allocator: std.mem.Allocator, array: []i32) void {
    allocator.free(array);
}

// ============================================================================
// 5️⃣ 문자열 관리
// ============================================================================

/// 문자열을 동적으로 복제합니다.
fn dupeString(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return allocator.dupe(u8, text);
}

/// 동적 문자열을 해제합니다.
fn freeString(allocator: std.mem.Allocator, text: []u8) void {
    allocator.free(text);
}

// ============================================================================
// 6️⃣ ArrayList (동적 배열)
// ============================================================================

/// ArrayList를 사용한 동적 배열 관리
fn arrayListExample(allocator: std.mem.Allocator) !void {
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(10);
    try list.append(20);
    try list.append(30);

    // list.items는 슬라이스로 접근
    // list.items.len == 3
}

// ============================================================================
// 7️⃣ StringArrayList (문자열 배열)
// ============================================================================

/// 문자열 배열을 동적으로 관리합니다.
fn stringArrayListExample(allocator: std.mem.Allocator) !void {
    var names = std.ArrayList([]const u8).init(allocator);
    defer {
        for (names.items) |name| {
            allocator.free(name);
        }
        names.deinit();
    }

    try names.append(try allocator.dupe(u8, "Alice"));
    try names.append(try allocator.dupe(u8, "Bob"));
    try names.append(try allocator.dupe(u8, "Charlie"));

    // names.items.len == 3
}

// ============================================================================
// 8️⃣ Assignment 1-9: 메모리 관리 실습
// ============================================================================

/// 학생을 나타내는 구조체 (동적 메모리 관리)
const Student = struct {
    name: []u8,
    score: u32,

    fn create(allocator: std.mem.Allocator, name: []const u8, score: u32) !*Student {
        const self = try allocator.create(Student);
        errdefer allocator.destroy(self);

        self.name = try allocator.dupe(u8, name);
        errdefer allocator.free(self.name);

        self.score = score;
        return self;
    }

    fn destroy(self: *Student, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn print(self: *const Student) void {
        std.debug.print("  - {s}: {}점\n", .{ self.name, self.score });
    }
};

/// 학급을 나타내는 구조체 (다중 학생 관리)
const ClassRoom = struct {
    name: []u8,
    students: std.ArrayList(*Student),

    fn create(allocator: std.mem.Allocator, name: []const u8) !*ClassRoom {
        const self = try allocator.create(ClassRoom);
        errdefer allocator.destroy(self);

        self.name = try allocator.dupe(u8, name);
        errdefer allocator.free(self.name);

        self.students = std.ArrayList(*Student).init(allocator);
        return self;
    }

    fn destroy(self: *ClassRoom, allocator: std.mem.Allocator) void {
        for (self.students.items) |student| {
            student.destroy(allocator);
        }
        self.students.deinit();
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn addStudent(self: *ClassRoom, student: *Student) !void {
        try self.students.append(student);
    }

    fn averageScore(self: *const ClassRoom) f32 {
        if (self.students.items.len == 0) return 0.0;

        var total: u32 = 0;
        for (self.students.items) |student| {
            total += student.score;
        }
        return @as(f32, @floatFromInt(total)) / @as(f32, @floatFromInt(self.students.items.len));
    }

    fn print(self: *const ClassRoom) void {
        std.debug.print("교실: {s}\n", .{self.name});
        std.debug.print("학생 수: {}\n", .{self.students.items.len});
        std.debug.print("평균 점수: {d:.2}\n", .{self.averageScore()});
        std.debug.print("학생 목록:\n", .{});
        for (self.students.items) |student| {
            student.print();
        }
    }
};

// ============================================================================
// 9️⃣ 메모리 누수 감지 (Testing Allocator)
// ============================================================================

/// 테스트 할당자 (메모리 누수 자동 감지)
fn testAllocatorExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 메모리를 할당했는데 해제하지 않으면?
    // gpa.deinit()에서 메모리 누수를 감지하고 보고합니다.
}

// ============================================================================
// 메인 함수: 모든 할당자 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-9. 할당자(Allocators)\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // Allocator 설정
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ============================================================================
    // 1️⃣ 구조체 할당 (allocator.create)
    // ============================================================================

    try stdout.print("1️⃣ 구조체 할당 (allocator.create)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const person = try Person.create(allocator, "Bob", 25);
    defer person.destroy(allocator);

    try stdout.print("Person 생성:\\n", .{});
    person.print();
    try stdout.print("\\n", .{});

    // ============================================================================
    // 2️⃣ 배열 할당 (allocator.alloc)
    // ============================================================================

    try stdout.print("2️⃣ 배열 할당 (allocator.alloc)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const numbers = try allocateArray(allocator, 5);
    defer deallocateArray(allocator, numbers);

    for (numbers, 0..) |*num, idx| {
        num.* = @as(i32, @intCast(idx * 10));
    }

    try stdout.print("배열 할당: {}\n", .{numbers.len});
    try stdout.print("요소: [", .{});
    for (numbers, 0..) |num, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{num});
    }
    try stdout.print("]\\n\\n", .{});

    // ============================================================================
    // 3️⃣ 문자열 복제 (allocator.dupe)
    // ============================================================================

    try stdout.print("3️⃣ 문자열 복제 (allocator.dupe)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const original = "Hello, Zig!";
    const copied = try dupeString(allocator, original);
    defer freeString(allocator, copied);

    try stdout.print("원본: {s}\\n", .{original});
    try stdout.print("복사본: {s}\\n", .{copied});
    try stdout.print("같은 내용? {}\\n", .{std.mem.eql(u8, original, copied)});
    try stdout.print("같은 주소? {}\\n\\n", .{@intFromPtr(original.ptr) == @intFromPtr(copied.ptr)});

    // ============================================================================
    // 4️⃣ ArrayList (동적 배열)
    // ============================================================================

    try stdout.print("4️⃣ ArrayList (동적 배열)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var scores = std.ArrayList(u32).init(allocator);
    defer scores.deinit();

    try scores.append(90);
    try scores.append(85);
    try scores.append(95);
    try scores.append(88);

    try stdout.print("점수 추가: 90, 85, 95, 88\\n", .{});
    try stdout.print("개수: {}\\n", .{scores.items.len});
    try stdout.print("용량: {}\\n", .{scores.capacity});
    try stdout.print("평균: {d:.2}\\n\\n", .{
        @as(f32, @floatFromInt(scores.items[0] + scores.items[1] + scores.items[2] + scores.items[3])) /
            @as(f32, @floatFromInt(scores.items.len)),
    });

    // ============================================================================
    // 5️⃣ 문자열 ArrayList
    // ============================================================================

    try stdout.print("5️⃣ 문자열 ArrayList\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var words = std.ArrayList([]const u8).init(allocator);
    defer {
        for (words.items) |word| {
            allocator.free(word);
        }
        words.deinit();
    }

    try words.append(try allocator.dupe(u8, "Zig"));
    try words.append(try allocator.dupe(u8, "Language"));
    try words.append(try allocator.dupe(u8, "Learning"));

    try stdout.print("단어 추가: ", .{});
    for (words.items, 0..) |word, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{s}", .{word});
    }
    try stdout.print("\\n\\n", .{});

    // ============================================================================
    // 6️⃣ Assignment 1-9: ClassRoom (중첩된 메모리 관리)
    // ============================================================================

    try stdout.print("6️⃣ Assignment 1-9: ClassRoom (중첩된 메모리 관리)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const classroom = try ClassRoom.create(allocator, "Zig 101");
    defer classroom.destroy(allocator);

    const s1 = try Student.create(allocator, "Alice", 95);
    try classroom.addStudent(s1);

    const s2 = try Student.create(allocator, "Bob", 87);
    try classroom.addStudent(s2);

    const s3 = try Student.create(allocator, "Charlie", 92);
    try classroom.addStudent(s3);

    try stdout.print("교실 정보:\\n", .{});
    classroom.print();
    try stdout.print("\\n", .{});

    // ============================================================================
    // 7️⃣ errdefer로 안전한 정리
    // ============================================================================

    try stdout.print("7️⃣ errdefer로 안전한 정리\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("Person.create() 함수 구조:\\n", .{});
    try stdout.print("  fn create(allocator, name, age) !*Person {{\\n", .{});
    try stdout.print("    const self = try allocator.create(Person);\\n", .{});
    try stdout.print("    errdefer allocator.destroy(self); ← 에러 시 자동 정리\\n", .{});
    try stdout.print("    self.name = try allocator.dupe(u8, name);\\n", .{});
    try stdout.print("    errdefer allocator.free(self.name); ← 이전 할당 정리\\n", .{});
    try stdout.print("    self.age = age;\\n", .{});
    try stdout.print("    return self;\\n", .{});
    try stdout.print("  }}\\n", .{});
    try stdout.print("\\n", .{});

    try stdout.print("이렇게 하면 allocate 중간에 실패해도 메모리가 누수되지 않습니다!\\n", .{});
    try stdout.print("\\n", .{});

    // ============================================================================
    // 8️⃣ FixedBufferAllocator (스택 기반)
    // ============================================================================

    try stdout.print("8️⃣ FixedBufferAllocator (스택 기반)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    const fixed_str = try dupeString(fba_allocator, "Fixed Buffer String");
    _ = fixed_str;

    try stdout.print("FixedBufferAllocator 사용:\\n", .{});
    try stdout.print("  - 메모리 누수 불가능 (버퍼가 스택에 고정)\\n", .{});
    try stdout.print("  - 할당 해제 후 메모리 회귀 불가능\\n", .{});
    try stdout.print("  - 크기가 작은 프로그램에 유용\\n", .{});
    try stdout.print("  - 임시 데이터 처리에 효과적\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-9 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-9 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ GeneralPurposeAllocator: 범용 할당자 (권장)\\n", .{});
    try stdout.print("  ✓ FixedBufferAllocator: 고정 크기 버퍼\\n", .{});
    try stdout.print("  ✓ allocator.create/destroy: 구조체 할당\\n", .{});
    try stdout.print("  ✓ allocator.alloc/free: 배열 할당\\n", .{});
    try stdout.print("  ✓ allocator.dupe: 문자열 복제\\n", .{});
    try stdout.print("  ✓ ArrayList: 동적 배열 관리\\n", .{});
    try stdout.print("  ✓ errdefer: 에러 시 자동 정리\\n", .{});
    try stdout.print("  ✓ 중첩된 메모리 관리: ClassRoom + Student\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 모든 할당은 명시적 (new/delete 없음)\\n", .{});
    try stdout.print("  2. 할당은 allocator 매개변수로 전달\\n", .{});
    try stdout.print("  3. 할당한 메모리는 반드시 해제\\n", .{});
    try stdout.print("  4. defer/errdefer로 확실한 정리\\n", .{});
    try stdout.print("  5. 메모리 누수는 프로그래머의 책임 (GC 없음)\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 할당자 시스템을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 다음: 1-10. 실무 패턴과 프로젝트 구조\\n", .{});
}

// ============================================================================
// 테스트: 할당자 검증
// ============================================================================

test "person create and destroy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const person = try Person.create(allocator, "Alice", 30);
    defer person.destroy(allocator);

    try std.testing.expectEqualStrings("Alice", person.name);
    try std.testing.expectEqual(@as(u32, 30), person.age);
}

test "array allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const arr = try allocateArray(allocator, 3);
    defer deallocateArray(allocator, arr);

    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;

    try std.testing.expectEqual(@as(i32, 10), arr[0]);
    try std.testing.expectEqual(@as(i32, 20), arr[1]);
    try std.testing.expectEqual(@as(i32, 30), arr[2]);
}

test "string duplication" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello";
    const copied = try dupeString(allocator, original);
    defer freeString(allocator, copied);

    try std.testing.expectEqualSlices(u8, original, copied);
}

test "arraylist" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(i32, 2), list.items[1]);
}

test "student create and destroy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const student = try Student.create(allocator, "Bob", 85);
    defer student.destroy(allocator);

    try std.testing.expectEqualStrings("Bob", student.name);
    try std.testing.expectEqual(@as(u32, 85), student.score);
}

test "classroom create and add students" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const classroom = try ClassRoom.create(allocator, "Class A");
    defer classroom.destroy(allocator);

    const s1 = try Student.create(allocator, "Alice", 90);
    try classroom.addStudent(s1);

    const s2 = try Student.create(allocator, "Bob", 80);
    try classroom.addStudent(s2);

    try std.testing.expectEqual(@as(usize, 2), classroom.students.items.len);
}

test "classroom average score" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const classroom = try ClassRoom.create(allocator, "Class B");
    defer classroom.destroy(allocator);

    const s1 = try Student.create(allocator, "Alice", 90);
    try classroom.addStudent(s1);

    const s2 = try Student.create(allocator, "Bob", 80);
    try classroom.addStudent(s2);

    const avg = classroom.averageScore();
    try std.testing.expectEqual(@as(f32, 85.0), avg);
}

test "fixed buffer allocator" {
    var buffer: [100]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const str = try allocator.dupe(u8, "test");
    try std.testing.expectEqualSlices(u8, "test", str);
}
