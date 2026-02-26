/// src/lesson_1_6.zig - Zig 전공 101: 1-6. 포인터(Pointers)와 메모리 관리의 기초
///
/// Assignment 1-6: 포인터와 메모리 할당
///
/// 철학: "메모리는 자원이고, 명시적으로 관리해야 한다"
/// Zig는 C의 포인터 위험성을 제거하면서도 저수준 제어를 유지한다.

const std = @import("std");

// ============================================================================
// 1️⃣ 기본 포인터 개념
// ============================================================================

/// 정수를 받아 그 값을 반환합니다. (일반 함수)
fn getInteger() i32 {
    return 42;
}

/// 정수의 포인터를 받아 가리키는 값을 반환합니다.
fn dereference(ptr: *i32) i32 {
    return ptr.*;
}

/// 포인터의 주소를 출력합니다. (데모용)
fn printAddress(ptr: *const i32) void {
    // Zig에서는 포인터 주소 자체를 직접 출력할 수 없지만,
    // 포인터가 유효함을 알 수 있습니다.
}

// ============================================================================
// 2️⃣ 스택 메모리와 포인터
// ============================================================================

/// 스택 메모리의 주소를 사용합니다. (스택 변수에 대한 포인터)
fn stackPointerExample() !void {
    var x: i32 = 100;
    const ptr: *i32 = &x;  // & = 주소 연산자 (address-of)

    // ptr.* = 역참조 (dereference)
    // ptr.* == 100
}

/// 슬라이스(배열의 동적 부분)를 사용합니다.
fn sliceExample() !void {
    var array: [5]i32 = [_]i32{ 1, 2, 3, 4, 5 };
    const slice: []i32 = &array;  // 배열 전체가 슬라이스 (포인터 + 길이)

    // slice[0] = 1
    // slice.len = 5
}

// ============================================================================
// 3️⃣ 동적 메모리 할당 (힙)
// ============================================================================

/// 구조체 정의: Person (메모리 관리 예제용)
const Person = struct {
    name: []const u8,
    age: u8,

    fn init(allocator: std.mem.Allocator, name: []const u8, age: u8) !*Person {
        const self = try allocator.create(Person);
        self.name = try allocator.dupe(u8, name);
        self.age = age;
        return self;
    }

    fn deinit(self: *Person, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn printInfo(self: *const Person) void {
        std.debug.print("이름: {s}, 나이: {}\\n", .{ self.name, self.age });
    }
};

/// Allocator를 사용한 동적 할당
fn dynamicAllocationExample(allocator: std.mem.Allocator) !void {
    // 단일 정수 할당
    const num = try allocator.create(i32);
    defer allocator.destroy(num);

    num.* = 99;
    // num.* == 99
}

// ============================================================================
// 4️⃣ 배열과 동적 배열
// ============================================================================

/// 정적 배열 (컴파일 타임에 크기 결정)
fn staticArrayExample() void {
    const fixed: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    // fixed[0] = 10
    // fixed.len = 5
}

/// 동적 배열 (런타임에 크기 결정)
fn dynamicArrayExample(allocator: std.mem.Allocator) !void {
    var numbers = std.ArrayList(i32).init(allocator);
    defer numbers.deinit();

    try numbers.append(1);
    try numbers.append(2);
    try numbers.append(3);

    // numbers.items = [1, 2, 3]
    // numbers.items.len = 3
}

// ============================================================================
// 5️⃣ 문자열 처리 (Zig의 특별한 포인터 사용)
// ============================================================================

/// 문자열 리터럴 (컴파일 타임 상수)
fn stringLiteralExample() void {
    const text: []const u8 = "Hello, Zig!";
    // text.len = 12
    // text는 포인터 + 길이 (슬라이스)
}

/// 동적 문자열 (힙 할당)
fn dynamicStringExample(allocator: std.mem.Allocator) !void {
    const greeting = try allocator.dupe(u8, "Greetings!");
    defer allocator.free(greeting);

    // greeting.len = 10
}

// ============================================================================
// 6️⃣ 포인터의 포인터 (다중 포인터)
// ============================================================================

/// 포인터를 수정하는 함수 (double pointer)
fn modifyPointer(ptr_to_ptr: **i32, allocator: std.mem.Allocator) !void {
    // ptr_to_ptr가 가리키는 포인터를 바꿀 수 있다.
    ptr_to_ptr.* = try allocator.create(i32);
    ptr_to_ptr.*.* = 777;
}

// ============================================================================
// 7️⃣ 메모리 안전성: Optional 포인터
// ============================================================================

/// Optional 포인터 (null이 될 수 있음)
const OptionalPerson = ?*Person;

fn processOptionalPointer(maybe_person: OptionalPerson) void {
    if (maybe_person) |person| {
        std.debug.print("사람 발견: {s}\\n", .{person.name});
    } else {
        std.debug.print("사람을 찾을 수 없습니다\\n", .{});
    }
}

// ============================================================================
// 8️⃣ Assignment 1-6: 포인터와 메모리 관리 실습
// ============================================================================

/// Student 구조체: 메모리 할당 및 해제 연습
const Student = struct {
    name: []const u8,
    score: u32,

    fn create(allocator: std.mem.Allocator, name: []const u8, score: u32) !*Student {
        const self = try allocator.create(Student);
        self.name = try allocator.dupe(u8, name);
        self.score = score;
        return self;
    }

    fn destroy(self: *Student, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn printSummary(self: *const Student) void {
        std.debug.print("학생: {s}, 점수: {}\\n", .{ self.name, self.score });
    }

    fn getGrade(self: *const Student) u8 {
        return if (self.score >= 90) 'A' else if (self.score >= 80) 'B' else if (self.score >= 70) 'C' else 'F';
    }
};

// ============================================================================
// 메인 함수: 모든 포인터 및 메모리 관리 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-6. 포인터와 메모리 관리\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    // ============================================================================
    // 1️⃣ 기본 포인터 개념
    // ============================================================================

    try stdout.print("1️⃣ 기본 포인터 개념\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var num: i32 = 42;
    const ptr: *i32 = &num;

    try stdout.print("변수: var num: i32 = 42;\\n", .{});
    try stdout.print("포인터: const ptr: *i32 = &num;\\n", .{});
    try stdout.print("값 (직접): num = {}\\n", .{num});
    try stdout.print("값 (포인터 역참조): ptr.* = {}\\n", .{ptr.*});
    try stdout.print("포인터 함수: dereference(ptr) = {}\\n\\n", .{dereference(ptr)});

    // ============================================================================
    // 2️⃣ 배열과 슬라이스
    // ============================================================================

    try stdout.print("2️⃣ 배열과 슬라이스\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var array: [5]i32 = [_]i32{ 10, 20, 30, 40, 50 };
    const slice: []i32 = &array;

    try stdout.print("정적 배열: var array: [5]i32 = [_]i32{{ 10, 20, 30, 40, 50 }};\\n", .{});
    try stdout.print("배열 크기: {}\\n", .{array.len});
    try stdout.print("첫 번째 원소: array[0] = {}\\n", .{array[0]});
    try stdout.print("배열을 슬라이스로 변환: const slice: []i32 = &array;\\n", .{});
    try stdout.print("슬라이스 길이: slice.len = {}\\n", .{slice.len});
    try stdout.print("슬라이스로 접근: slice[2] = {}\\n\\n", .{slice[2]});

    // ============================================================================
    // 3️⃣ Allocator를 사용한 동적 할당
    // ============================================================================

    try stdout.print("3️⃣ 동적 메모리 할당 (힙)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 단일 정수 할당
    const heap_num = try allocator.create(i32);
    defer allocator.destroy(heap_num);
    heap_num.* = 123;

    try stdout.print("힙 할당 정수: allocator.create(i32)\\n", .{});
    try stdout.print("할당된 값: heap_num.* = {}\\n", .{heap_num.*});
    try stdout.print("메모리 해제: allocator.destroy(heap_num)\\n\\n", .{});

    // ============================================================================
    // 4️⃣ ArrayList (동적 배열)
    // ============================================================================

    try stdout.print("4️⃣ 동적 배열 (ArrayList)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var numbers = std.ArrayList(i32).init(allocator);
    defer numbers.deinit();

    try numbers.append(100);
    try numbers.append(200);
    try numbers.append(300);

    try stdout.print("var numbers = std.ArrayList(i32).init(allocator);\\n", .{});
    try stdout.print("추가: numbers.append(100), append(200), append(300)\\n", .{});
    try stdout.print("크기: numbers.items.len = {}\\n", .{numbers.items.len});
    try stdout.print("요소 출력: [", .{});
    for (numbers.items, 0..) |item, idx| {
        if (idx > 0) try stdout.print(", ", .{});
        try stdout.print("{}", .{item});
    }
    try stdout.print("]\\n", .{});
    try stdout.print("메모리 해제: numbers.deinit()\\n\\n", .{});

    // ============================================================================
    // 5️⃣ 문자열 처리
    // ============================================================================

    try stdout.print("5️⃣ 문자열 처리\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const literal_string: []const u8 = "Literal String";
    try stdout.print("문자열 리터럴: \"Literal String\" (스택 상수)\\n", .{});
    try stdout.print("길이: {}, 내용: {s}\\n", .{ literal_string.len, literal_string });

    const heap_string = try allocator.dupe(u8, "Heap String");
    defer allocator.free(heap_string);

    try stdout.print("동적 문자열: allocator.dupe(u8, \"Heap String\")\\n", .{});
    try stdout.print("길이: {}, 내용: {s}\\n\\n", .{ heap_string.len, heap_string });

    // ============================================================================
    // 6️⃣ Assignment 1-6: Student 포인터 관리
    // ============================================================================

    try stdout.print("6️⃣ Assignment 1-6: Student 구조체 동적 할당\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("📝 Student 구조체 정의:\\n", .{});
    try stdout.print("const Student = struct {{\\n", .{});
    try stdout.print("    name: []const u8,\\n", .{});
    try stdout.print("    score: u32,\\n", .{});
    try stdout.print("    fn create(...) !*Student {{ ... }}\\n", .{});
    try stdout.print("    fn destroy(...) void {{ ... }}\\n", .{});
    try stdout.print("}}\\n\\n", .{});

    // Student 1 생성
    const student1 = try Student.create(allocator, "Alice", 95);
    defer student1.destroy(allocator);

    try stdout.print("학생 1 생성:\\n", .{});
    student1.printSummary();
    try stdout.print("학점: {c}\\n\\n", .{student1.getGrade()});

    // Student 2 생성
    const student2 = try Student.create(allocator, "Bob", 78);
    defer student2.destroy(allocator);

    try stdout.print("학생 2 생성:\\n", .{});
    student2.printSummary();
    try stdout.print("학점: {c}\\n\\n", .{student2.getGrade()});

    // ============================================================================
    // 7️⃣ Person 구조체 (이름 동적 할당)
    // ============================================================================

    try stdout.print("7️⃣ Person 구조체 (String 동적 할당)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const person = try Person.init(allocator, "Charlie", 30);
    defer person.deinit(allocator);

    try stdout.print("Person 생성 (동적 메모리):\\n", .{});
    person.printInfo();
    try stdout.print("(이름은 heap에 할당, 자동으로 해제됨)\\n\\n", .{});

    // ============================================================================
    // 8️⃣ 포인터 안전성: Optional 포인터
    // ============================================================================

    try stdout.print("8️⃣ 포인터 안전성\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("Optional 포인터: ?*Person\\n", .{});
    try stdout.print("null 체크를 통한 안전한 접근:\\n\\n", .{});

    const maybe_person: ?*Person = person;
    processOptionalPointer(maybe_person);

    const no_person: ?*Person = null;
    processOptionalPointer(no_person);

    try stdout.print("\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-6 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-6 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ 포인터의 기본 개념 (선언, 주소 연산자 &, 역참조 *)\\n", .{});
    try stdout.print("  ✓ 배열과 슬라이스 (포인터 + 길이)\\n", .{});
    try stdout.print("  ✓ Allocator를 사용한 동적 할당 및 해제\\n", .{});
    try stdout.print("  ✓ ArrayList로 동적 배열 관리\\n", .{});
    try stdout.print("  ✓ 문자열의 두 가지 형태 (리터럴 vs 동적)\\n", .{});
    try stdout.print("  ✓ defer를 통한 자동 메모리 정리\\n", .{});
    try stdout.print("  ✓ Optional 포인터로 안전한 null 처리\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 포인터는 메모리 주소를 나타냄 (*Type)\\n", .{});
    try stdout.print("  2. & = 주소 연산자, * = 역참조 연산자\\n", .{});
    try stdout.print("  3. 동적 할당은 항상 해제 필수 (defer 권장)\\n", .{});
    try stdout.print("  4. 슬라이스 = 포인터 + 길이 (배열보다 유연함)\\n", .{});
    try stdout.print("  5. Optional 포인터로 null 안전성 보장\\n", .{});
    try stdout.print("  6. Allocator = 메모리 관리의 명시적 인터페이스\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 포인터와 메모리 관리를 마스터했습니다!\\n", .{});
    try stdout.print("🚀 다음: 1-7. 고급 메모리 패턴과 우발적 사용\\n", .{});
}

// ============================================================================
// 테스트: 포인터와 메모리 관리 검증
// ============================================================================

test "pointer dereferencing" {
    var x: i32 = 42;
    const ptr: *i32 = &x;
    try std.testing.expectEqual(@as(i32, 42), ptr.*);
}

test "pointer modification" {
    var x: i32 = 10;
    const ptr: *i32 = &x;
    ptr.* = 20;
    try std.testing.expectEqual(@as(i32, 20), x);
}

test "array slice" {
    var array: [5]i32 = [_]i32{ 1, 2, 3, 4, 5 };
    const slice: []i32 = &array;
    try std.testing.expectEqual(@as(usize, 5), slice.len);
    try std.testing.expectEqual(@as(i32, 3), slice[2]);
}

test "arraylist append and len" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(10);
    try list.append(20);
    try list.append(30);

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(i32, 20), list.items[1]);
}

test "string literal" {
    const text: []const u8 = "Hello";
    try std.testing.expectEqual(@as(usize, 5), text.len);
}

test "student creation and grade" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const student = try Student.create(allocator, "Alice", 95);
    defer student.destroy(allocator);

    try std.testing.expectEqual(@as(u32, 95), student.score);
    try std.testing.expectEqual(@as(u8, 'A'), student.getGrade());
}

test "student lower grade" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const student = try Student.create(allocator, "Bob", 75);
    defer student.destroy(allocator);

    try std.testing.expectEqual(@as(u8, 'C'), student.getGrade());
}

test "optional pointer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const person = try Person.init(allocator, "David", 25);
    defer person.deinit(allocator);

    const maybe_person: ?*Person = person;
    try std.testing.expect(maybe_person != null);
}

test "optional pointer null" {
    const no_person: ?*Person = null;
    try std.testing.expect(no_person == null);
}
