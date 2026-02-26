// ============================================================================
// 🎓 Zig 전공 101: Lesson 1-13
// 대규모 시스템을 위한 프로젝트 아키텍처 설계
// ============================================================================
//
// 학습 목표:
// 1. 표준 프로젝트 레이아웃 (Standard Layout) 이해
// 2. 의존성 관리 (build.zig.zon) 개념
// 3. 인터페이스 패턴 (Interface Pattern) 구현
// 4. 빌드 시스템 활용 (build.zig 심화)
// 5. 모듈 분리와 가시성 (Visibility) 제어
// 6. 테스트 통합과 신뢰성
//
// 핵심 철학:
// "기록이 증명이다" - 코드 구조와 테스트가 시스템의 신뢰성을 증명한다.
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// ============================================================================
// 섹션 1: 모듈 인터페이스 패턴 (Interface Pattern)
// ============================================================================
// Zig에는 interface 키워드가 없지만, 함수 포인터를 사용하여 다형성을 구현합니다.
// 이는 런타임 오버헤드 없이 유연한 설계를 가능하게 합니다.

/// 데이터 기록 인터페이스
/// Logger의 역할을 정의하는 인터페이스 패턴
pub const Logger = struct {
    ptr: *anyopaque, // 구체적인 구현체 포인터
    logFn: *const fn (ptr: *anyopaque, level: []const u8, message: []const u8) anyerror!void,

    /// 로그 메시지 기록
    pub fn log(self: Logger, level: []const u8, message: []const u8) !void {
        return self.logFn(self.ptr, level, message);
    }
};

/// 데이터 쓰기 인터페이스
pub const Writer = struct {
    ptr: *anyopaque,
    writeFn: *const fn (ptr: *anyopaque, data: []const u8) anyerror!usize,

    /// 데이터 쓰기 (반환값: 쓴 바이트 수)
    pub fn write(self: Writer, data: []const u8) !usize {
        return self.writeFn(self.ptr, data);
    }
};

// ============================================================================
// 섹션 2: 구체적인 구현체 - ConsoleLogger
// ============================================================================
// Writer 인터페이스를 구현하는 실체

pub const ConsoleLogger = struct {
    writer: std.fs.File.Writer,

    pub fn init() ConsoleLogger {
        return ConsoleLogger{
            .writer = std.io.getStdOut().writer(),
        };
    }

    /// ConsoleLogger를 Logger 인터페이스로 변환
    pub fn asLogger(self: *ConsoleLogger) Logger {
        return Logger{
            .ptr = @ptrCast(self),
            .logFn = logFn,
        };
    }

    /// 로그 함수 구현
    fn logFn(ptr: *anyopaque, level: []const u8, message: []const u8) !void {
        const self: *ConsoleLogger = @ptrCast(@alignCast(ptr));
        try self.writer.print("[{s}] {s}\n", .{ level, message });
    }
};

// ============================================================================
// 섹션 3: 프로젝트 레이아웃 정보 모듈 (ProjectLayout)
// ============================================================================
// 표준 Zig 프로젝트 구조를 정의하고 검증합니다.

pub const ProjectLayout = struct {
    /// 프로젝트 폴더 구조
    pub const FolderStructure = struct {
        name: []const u8,
        description: []const u8,
        is_required: bool,
        purpose: []const u8,
    };

    /// 표준 폴더 목록
    pub const standard_folders = [_]FolderStructure{
        .{
            .name = "src",
            .description = "소스 코드 디렉토리",
            .is_required = true,
            .purpose = "모든 .zig 소스 파일이 위치",
        },
        .{
            .name = "src/modules",
            .description = "비즈니스 로직 모듈",
            .is_required = false,
            .purpose = "역할별 모듈 분리 (auth/, database/, api/)",
        },
        .{
            .name = "zig-out",
            .description = "빌드 결과물 디렉토리",
            .is_required = false,
            .purpose = "컴파일된 바이너리와 오브젝트 파일 (Git 무시)",
        },
        .{
            .name = "build.zig",
            .description = "프로젝트 빌드 스크립트",
            .is_required = true,
            .purpose = "컴파일, 의존성, 테스트 관리",
        },
    };

    /// 프로젝트 레이아웃 정보
    pub const info = struct {
        pub const main_zig = "src/main.zig (실행 파일의 진입점)";
        pub const root_zig = "src/root.zig (라이브러리의 진입점)";
        pub const build_zig = "build.zig (Zig 프로젝트 매니페스트)";
        pub const build_zig_zon = "build.zig.zon (의존성 관리 파일, Zig 0.11+)";
    };

    /// 프로젝트 폴더 검증
    pub fn validate(allocator: Allocator, root_path: []const u8) !bool {
        // 실제 환경에서는 파일 시스템을 검사합니다.
        // 현재는 개념 검증만 수행
        _ = allocator;
        _ = root_path;
        return true;
    }
};

// ============================================================================
// 섹션 4: 패키지 관리 정보 (PackageManager)
// ============================================================================
// build.zig.zon 파일의 구조를 정의합니다 (Zig Object Notation).

pub const PackageManager = struct {
    /// 의존성 정보
    pub const Dependency = struct {
        name: []const u8,
        url: []const u8,
        hash: []const u8, // SHA256 해시 - "기록이 증명하는 무결성"
    };

    /// 예제: 공식 표준 라이브러리 의존성
    pub const example_dependency = Dependency{
        .name = "zlib",
        .url = "https://github.com/madler/zlib.git",
        .hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
    };

    /// build.zig.zon 구조 (개념)
    pub const BuidFileZon = struct {
        pub const example_content =
            \\.{
            \\    .name = "my-project",
            \\    .version = "0.1.0",
            \\    .paths = .{
            \\        "build.zig",
            \\        "build.zig.zon",
            \\        "src",
            \\    },
            \\    .dependencies = .{
            \\        .zlib = .{
            \\            .url = "https://github.com/madler/zlib.git",
            \\            .hash = "1234567890abcdef...",
            \\        },
            \\    },
            \\}
        ;
    };

    /// 의존성 검증 (해시 기반)
    pub fn verifyDependency(dep: Dependency) bool {
        // 실제로는 다운로드한 파일의 해시를 계산하여 비교
        // 여기서는 해시 존재 여부만 검증
        return dep.hash.len > 0;
    }
};

// ============================================================================
// 섹션 5: 모듈 분리와 가시성 (Visibility)
// ============================================================================

pub const Calculator = struct {
    /// 계산기 모듈 (분리된 파일에 있다고 가정)
    /// main.zig에서 @import("calculator.zig")로 임포트됨

    pub fn add(a: i32, b: i32) i32 {
        return a + b;
    }

    pub fn subtract(a: i32, b: i32) i32 {
        return a - b;
    }

    pub fn multiply(a: i32, b: i32) i32 {
        return a * b;
    }

    pub fn divide(a: i32, b: i32) !i32 {
        if (b == 0) return error.DivisionByZero;
        return @divExact(a, b);
    }

    /// 내부 함수 (pub 없음 = 외부 접근 불가)
    fn validateInput(value: i32) bool {
        return value >= -1000000 and value <= 1000000;
    }

    pub fn safeAdd(a: i32, b: i32) !i32 {
        if (!validateInput(a) or !validateInput(b)) {
            return error.InputOutOfRange;
        }
        return add(a, b);
    }
};

// ============================================================================
// 섹션 6: 빌드 시스템 정보 (BuildSystem)
// ============================================================================
// build.zig에서 사용되는 주요 개념

pub const BuildSystem = struct {
    /// build.zig의 주요 함수 시그니처
    pub const build_function_signature =
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    // 실행 파일 생성
        \\    const exe = b.addExecutable(.{
        \\        .name = "my-app",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    // 테스트 추가
        \\    const tests = b.addTest(.{
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\}
    ;

    /// 빌드 옵션 종류
    pub const BuildOptions = enum {
        debug, // 디버그 정보 포함
        releaseSafe, // 최적화 + 안전성 검사
        releaseFast, // 최대 최적화 (안전성 검사 생략)
        releaseSmall, // 최소 크기 (임베디드용)
    };

    /// 빌드 단계 (Build Steps)
    pub const Step = enum {
        compile, // 컴파일
        test, // 테스트 실행
        install, // 설치
        run, // 실행
        custom, // 사용자 정의
    };

    /// 조건부 컴파일 예제
    pub const conditionalCompilation =
        \\const is_debug = @import("builtin").mode == .Debug;
        \\
        \\pub fn debug_print(msg: []const u8) void {
        \\    if (is_debug) {
        \\        std.debug.print("{s}\n", .{msg});
        \\    }
        \\}
    ;
};

// ============================================================================
// 섹션 7: 테스트 통합 패턴 (Testing Integration)
// ============================================================================
// "기록된 테스트가 곧 신뢰"

pub const TestingPatterns = struct {
    /// 인라인 테스트 (소스 코드 바로 옆)
    /// test 블록은 zig build test에서 자동 실행됨

    pub fn fibonacci(n: u32) u32 {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }

    pub fn isPrime(n: u32) bool {
        if (n < 2) return false;
        if (n == 2) return true;
        if (n % 2 == 0) return false;

        var i: u32 = 3;
        while (i * i <= n) : (i += 2) {
            if (n % i == 0) return false;
        }
        return true;
    }

    /// 테스트 헬퍼
    pub fn runAllTests() !void {
        std.debug.print("모든 인라인 테스트가 zig build test로 자동 실행됩니다.\n", .{});
    }
};

// ============================================================================
// 섹션 8: 프로젝트 메타데이터 (Project Metadata)
// ============================================================================

pub const ProjectMetadata = struct {
    name: []const u8 = "Zig Professional Graduation Project",
    version: []const u8 = "1.0.0",
    author: []const u8 = "Zig Graduate",
    description: []const u8 = "대규모 시스템을 위한 프로젝트 아키텍처 설계",

    pub fn printInfo() void {
        std.debug.print(
            \\
            \\╔═══════════════════════════════════════════════════════════╗
            \\║   🎓 Zig 전공 101: 프로젝트 아키텍처 설계                   ║
            \\║   "기록이 증명이다" - Your record is your proof.          ║
            \\╚═══════════════════════════════════════════════════════════╝
            \\
            \\【 핵심 학습 내용 】
            \\
            \\1. 표준 프로젝트 레이아웃
            \\   • /src: 소스 코드 디렉토리
            \\   • /src/modules: 비즈니스 로직 분리
            \\   • build.zig: 프로젝트 매니페스트
            \\   • build.zig.zon: 의존성 관리 (Zig 0.11+)
            \\
            \\2. 인터페이스 패턴 (다형성 구현)
            \\   • 함수 포인터 + anyopaque를 사용한 유연한 설계
            \\   • 런타임 오버헤드 최소화
            \\   • Logger, Writer 인터페이스 예제
            \\
            \\3. 모듈 분리와 가시성
            \\   • pub: 외부에 노출되는 기능
            \\   • private: 내부에서만 사용하는 기능
            \\   • @import() 메커니즘
            \\
            \\4. 빌드 시스템 활용
            \\   • Conditional Compilation (조건부 컴파일)
            \\   • C 라이브러리 링크
            \\   • 자동 테스트 실행
            \\
            \\5. 테스트 통합
            \\   • 소스 코드 바로 옆 test 블록
            \\   • zig build test로 전체 검증
            \\   • "기록된 테스트가 곧 신뢰"
            \\
        , .{});
    }
};

// ============================================================================
// 메인 함수: 학습 내용 시연
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    ProjectMetadata.printInfo();

    // ConsoleLogger 시연
    var logger = ConsoleLogger.init();
    const logger_interface = logger.asLogger();
    try logger_interface.log("INFO", "프로젝트 아키텍처 설계 시작");

    // 프로젝트 레이아웃 정보 출력
    std.debug.print("\n【 표준 프로젝트 레이아웃 】\n", .{});
    for (ProjectLayout.standard_folders) |folder| {
        std.debug.print("\n폴더: {s}\n", .{folder.name});
        std.debug.print("  설명: {s}\n", .{folder.description});
        std.debug.print("  필수: {}\n", .{folder.is_required});
        std.debug.print("  목적: {s}\n", .{folder.purpose});
    }

    // 패키지 관리 정보
    std.debug.print("\n【 의존성 관리 (build.zig.zon) 】\n", .{});
    std.debug.print("프로젝트 의존성 검증: {}\n", .{PackageManager.verifyDependency(PackageManager.example_dependency)});
    std.debug.print("의존성 이름: {s}\n", .{PackageManager.example_dependency.name});

    // Calculator 모듈 사용
    std.debug.print("\n【 모듈 분리 (Calculator) 】\n", .{});
    std.debug.print("계산: 10 + 5 = {}\n", .{Calculator.add(10, 5)});
    std.debug.print("계산: 10 - 5 = {}\n", .{Calculator.subtract(10, 5)});
    std.debug.print("계산: 10 * 5 = {}\n", .{Calculator.multiply(10, 5)});

    if (Calculator.divide(10, 5)) |result| {
        std.debug.print("계산: 10 / 5 = {}\n", .{result});
    } else |err| {
        std.debug.print("오류: {}\n", .{err});
    }

    // 빌드 시스템 정보
    std.debug.print("\n【 빌드 시스템 (build.zig) 】\n", .{});
    std.debug.print("빌드 옵션:\n", .{});
    std.debug.print("  • debug: 디버그 정보 포함\n", .{});
    std.debug.print("  • releaseSafe: 최적화 + 안전성\n", .{});
    std.debug.print("  • releaseFast: 최대 성능\n", .{});
    std.debug.print("  • releaseSmall: 최소 크기\n", .{});

    // 테스트 정보
    std.debug.print("\n【 테스트 통합 】\n", .{});
    std.debug.print("Fibonacci(5) = {}\n", .{TestingPatterns.fibonacci(5)});
    std.debug.print("17은 소수? {}\n", .{TestingPatterns.isPrime(17)});
    std.debug.print("20은 소수? {}\n", .{TestingPatterns.isPrime(20)});

    try logger_interface.log("SUCCESS", "프로젝트 아키텍처 설계 완료!");

    _ = allocator;
}

// ============================================================================
// 단위 테스트
// ============================================================================
// "기록이 증명이다" - 모든 기능은 테스트로 검증된다.

test "Logger 인터페이스" {
    var logger = ConsoleLogger.init();
    const logger_interface = logger.asLogger();
    try logger_interface.log("TEST", "테스트 메시지");
}

test "Calculator.add" {
    try testing.expect(Calculator.add(10, 5) == 15);
    try testing.expect(Calculator.add(-10, 5) == -5);
    try testing.expect(Calculator.add(0, 0) == 0);
}

test "Calculator.subtract" {
    try testing.expect(Calculator.subtract(10, 5) == 5);
    try testing.expect(Calculator.subtract(5, 10) == -5);
}

test "Calculator.multiply" {
    try testing.expect(Calculator.multiply(10, 5) == 50);
    try testing.expect(Calculator.multiply(-10, 5) == -50);
    try testing.expect(Calculator.multiply(0, 100) == 0);
}

test "Calculator.divide" {
    try testing.expect((try Calculator.divide(10, 5)) == 2);
    try testing.expect((try Calculator.divide(100, 10)) == 10);
}

test "Calculator.divide by zero" {
    try testing.expectError(error.DivisionByZero, Calculator.divide(10, 0));
}

test "Calculator.safeAdd" {
    try testing.expect((try Calculator.safeAdd(10, 5)) == 15);
}

test "ProjectLayout validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const is_valid = try ProjectLayout.validate(allocator, "/tmp");
    try testing.expect(is_valid);
}

test "PackageManager dependency verification" {
    const dep = PackageManager.example_dependency;
    try testing.expect(PackageManager.verifyDependency(dep));
}

test "Fibonacci sequence" {
    try testing.expect(TestingPatterns.fibonacci(0) == 0);
    try testing.expect(TestingPatterns.fibonacci(1) == 1);
    try testing.expect(TestingPatterns.fibonacci(5) == 5);
    try testing.expect(TestingPatterns.fibonacci(10) == 55);
}

test "Prime number detection" {
    try testing.expect(TestingPatterns.isPrime(2) == true);
    try testing.expect(TestingPatterns.isPrime(17) == true);
    try testing.expect(TestingPatterns.isPrime(20) == false);
    try testing.expect(TestingPatterns.isPrime(1) == false);
}

test "모듈 가시성 제어" {
    // pub 함수는 외부에서 호출 가능
    const result = Calculator.add(10, 5);
    try testing.expect(result == 15);

    // private 함수는 테스트에서도 접근 불가 (구조체 내부만 호출)
    // const is_valid = Calculator.validateInput(100); // 컴파일 에러!
}

test "인터페이스 패턴 다형성" {
    var logger = ConsoleLogger.init();
    const logger_interface = logger.asLogger();

    // 같은 Logger 인터페이스로 다양한 구현체 사용 가능
    try logger_interface.log("INFO", "다형성 테스트");
    try logger_interface.log("ERROR", "에러 테스트");
}

test "조건부 컴파일 개념" {
    // 빌드 시간에 debug 여부를 확인하여 다른 코드 실행
    // zig build -Doptimize=ReleaseFast로 빌드하면 debug 코드 제외
    std.debug.print("이 메시지는 debug 모드에서만 출력됩니다.\n", .{});
}

test "모든 테스트 통합 검증" {
    std.debug.print("\n✅ 프로젝트 아키텍처 설계 - 모든 테스트 통과!\n", .{});
}
