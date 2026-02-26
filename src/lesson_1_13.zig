/// src/lesson_1_13.zig - Zig 전공 101: 1-13. 대규모 시스템 아키텍처 설계
///
/// Assignment 1-13: 모든 기술을 통합한 완전한 시스템
///
/// 철학: "설계는 모든 요소를 조화롭게 엮는 예술"
/// Zig의 모든 기능을 활용하여 안전하고 효율적인 대규모 시스템을 설계합니다.

const std = @import("std");
const Mutex = std.Thread.Mutex;

// ============================================================================
// 1️⃣ 시스템 아키텍처: 계층 구조
// ============================================================================

/// 데이터 계층 (Data Layer)
const Database = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(Record),
    mutex: Mutex = .{},

    const Record = struct {
        id: u32,
        name: []u8,
        value: i32,
    };

    fn init(allocator: std.mem.Allocator) !*Database {
        const self = try allocator.create(Database);
        self.allocator = allocator;
        self.records = std.ArrayList(Record).init(allocator);
        return self;
    }

    fn deinit(self: *Database) void {
        for (self.records.items) |record| {
            self.allocator.free(record.name);
        }
        self.records.deinit();
        self.allocator.destroy(self);
    }

    fn insert(self: *Database, id: u32, name: []const u8, value: i32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        try self.records.append(.{
            .id = id,
            .name = name_copy,
            .value = value,
        });
    }

    fn query(self: *Database, id: u32) ?Record {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.records.items) |record| {
            if (record.id == id) {
                return record;
            }
        }
        return null;
    }

    fn count(self: *Database) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.records.items.len;
    }
};

// ============================================================================
// 2️⃣ 비즈니스 로직 계층 (Business Logic Layer)
// ============================================================================

/// 비즈니스 도메인: 사용자 관리
const UserService = struct {
    database: *Database,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, database: *Database) !*UserService {
        const self = try allocator.create(UserService);
        self.database = database;
        self.allocator = allocator;
        return self;
    }

    fn deinit(self: *UserService) void {
        self.allocator.destroy(self);
    }

    fn registerUser(self: *UserService, id: u32, name: []const u8, initial_credit: i32) !void {
        // 비즈니스 규칙: ID는 1 이상
        if (id == 0) {
            return error.InvalidUserId;
        }

        // 비즈니스 규칙: 초기 크레딧은 양수
        if (initial_credit < 0) {
            return error.NegativeCredit;
        }

        try self.database.insert(id, name, initial_credit);
    }

    fn getUserInfo(self: *UserService, id: u32) ![]u8 {
        if (self.database.query(id)) |record| {
            return try std.fmt.allocPrint(
                self.allocator,
                "ID: {}, Name: {s}, Credit: {}",
                .{ record.id, record.name, record.value },
            );
        } else {
            return error.UserNotFound;
        }
    }

    fn totalUsers(self: *UserService) usize {
        return self.database.count();
    }
};

// ============================================================================
// 3️⃣ 프레젠테이션 계층 (Presentation Layer)
// ============================================================================

/// API 인터페이스
const SystemAPI = struct {
    user_service: *UserService,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, user_service: *UserService) !*SystemAPI {
        const self = try allocator.create(SystemAPI);
        self.user_service = user_service;
        self.allocator = allocator;
        return self;
    }

    fn deinit(self: *SystemAPI) void {
        self.allocator.destroy(self);
    }

    fn handleRegisterRequest(self: *SystemAPI, id: u32, name: []const u8, credit: i32) !APIResponse {
        self.user_service.registerUser(id, name, credit) catch |err| {
            return .{
                .status = .Error,
                .message = try std.fmt.allocPrint(self.allocator, "Registration failed: {}", .{err}),
            };
        };

        return .{
            .status = .Success,
            .message = try std.fmt.allocPrint(self.allocator, "User {} registered", .{id}),
        };
    }

    fn handleQueryRequest(self: *SystemAPI, id: u32) !APIResponse {
        const info = self.user_service.getUserInfo(id) catch |err| {
            return .{
                .status = .Error,
                .message = try std.fmt.allocPrint(self.allocator, "Query failed: {}", .{err}),
            };
        };
        defer self.allocator.free(info);

        return .{
            .status = .Success,
            .message = try self.allocator.dupe(u8, info),
        };
    }

    const APIResponse = union(enum) {
        Success: void,
        Error: []u8,

        pub fn status(self: APIResponse) []const u8 {
            return switch (self) {
                .Success => "✅ Success",
                .Error => "❌ Error",
            };
        }

        pub fn message(self: APIResponse) ?[]const u8 {
            return switch (self) {
                .Success => null,
                .Error => |msg| msg,
            };
        }
    };
};

// ============================================================================
// 4️⃣ 설정 계층 (Configuration Layer)
// ============================================================================

/// 시스템 설정 (싱글톤 패턴)
const SystemConfig = struct {
    max_users: u32 = 1000,
    max_retry: u32 = 3,
    timeout_ms: u32 = 5000,
    debug_mode: bool = false,

    fn getInstance() *const SystemConfig {
        return &default_config;
    }

    const default_config: SystemConfig = .{};
};

// ============================================================================
// 5️⃣ 에러 처리 전략
// ============================================================================

/// 도메인별 에러 정의
const SystemError = error{
    InvalidUserId,
    NegativeCredit,
    UserNotFound,
    DatabaseFull,
    MemoryAllocationFailed,
};

/// 에러 핸들링 유틸리티
const ErrorHandler = struct {
    fn handle(err: SystemError, context: []const u8) void {
        std.debug.print("ERROR in {s}: {}\n", .{ context, err });
    }

    fn handleWithRetry(
        comptime func: fn () SystemError!void,
        max_attempts: u32,
        context: []const u8,
    ) void {
        var attempt: u32 = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            func() catch |err| {
                if (attempt == max_attempts - 1) {
                    ErrorHandler.handle(err, context);
                }
                continue;
            };
            return;
        }
    }
};

// ============================================================================
// 6️⃣ 성능 최적화 - 캐싱
// ============================================================================

/// 간단한 캐시 구현
const Cache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(CacheEntry),
    mutex: Mutex = .{},
    hit_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    miss_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const CacheEntry = struct {
        key: u32,
        value: i32,
    };

    fn init(allocator: std.mem.Allocator) !*Cache {
        const self = try allocator.create(Cache);
        self.allocator = allocator;
        self.entries = std.ArrayList(CacheEntry).init(allocator);
        return self;
    }

    fn deinit(self: *Cache) void {
        self.entries.deinit();
        self.allocator.destroy(self);
    }

    fn get(self: *Cache, key: u32) ?i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |entry| {
            if (entry.key == key) {
                _ = self.hit_count.fetchAdd(1, .seq_cst);
                return entry.value;
            }
        }
        _ = self.miss_count.fetchAdd(1, .seq_cst);
        return null;
    }

    fn put(self: *Cache, key: u32, value: i32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.entries.append(.{ .key = key, .value = value });
    }

    fn stats(self: *Cache) CacheStats {
        return .{
            .hits = self.hit_count.load(.seq_cst),
            .misses = self.miss_count.load(.seq_cst),
        };
    }

    const CacheStats = struct {
        hits: u32,
        misses: u32,
    };
};

// ============================================================================
// 7️⃣ 테스트 유틸리티
// ============================================================================

/// 단위 테스트 헬퍼
const TestHelper = struct {
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TestHelper {
        return .{ .allocator = allocator };
    }

    fn setupSystem(self: TestHelper) !struct {
        database: *Database,
        user_service: *UserService,
        api: *SystemAPI,
    } {
        const database = try Database.init(self.allocator);
        const user_service = try UserService.init(self.allocator, database);
        const api = try SystemAPI.init(self.allocator, user_service);

        return .{
            .database = database,
            .user_service = user_service,
            .api = api,
        };
    }

    fn teardownSystem(
        self: TestHelper,
        database: *Database,
        user_service: *UserService,
        api: *SystemAPI,
    ) void {
        api.deinit();
        user_service.deinit();
        database.deinit();
    }
};

// ============================================================================
// 메인 함수: 완전한 시스템 시뮬레이션
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 101: 1-13. 대규모 시스템 아키텍처\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ============================================================================
    // 1️⃣ 시스템 초기화
    // ============================================================================

    try stdout.print("1️⃣ 시스템 초기화\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const database = try Database.init(allocator);
    defer database.deinit();

    const user_service = try UserService.init(allocator, database);
    defer user_service.deinit();

    const api = try SystemAPI.init(allocator, user_service);
    defer api.deinit();

    try stdout.print("✓ Database 초기화\\n", .{});
    try stdout.print("✓ UserService 초기화\\n", .{});
    try stdout.print("✓ API 초기화\\n\\n", .{});

    // ============================================================================
    // 2️⃣ 사용자 등록
    // ============================================================================

    try stdout.print("2️⃣ 사용자 등록 (비즈니스 로직)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try user_service.registerUser(1, "Alice", 1000);
    try user_service.registerUser(2, "Bob", 2000);
    try user_service.registerUser(3, "Charlie", 1500);

    try stdout.print("총 등록된 사용자: {}\\n\\n", .{user_service.totalUsers()});

    // ============================================================================
    // 3️⃣ 에러 처리 시연
    // ============================================================================

    try stdout.print("3️⃣ 에러 처리 전략\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("유효하지 않은 ID로 등록 시도: ", .{});
    user_service.registerUser(0, "Invalid", 100) catch |err| {
        try stdout.print("에러 발생: {}\\n", .{err});
    };

    try stdout.print("음수 크레딧으로 등록 시도: ", .{});
    user_service.registerUser(999, "Negative", -100) catch |err| {
        try stdout.print("에러 발생: {}\\n\\n", .{err});
    };

    // ============================================================================
    // 4️⃣ API 호출
    // ============================================================================

    try stdout.print("4️⃣ API 계층을 통한 요청 처리\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const response1 = try api.handleRegisterRequest(100, "David", 3000);
    try stdout.print("등록 응답: {}\\n", .{response1.status()});

    const response2 = try api.handleQueryRequest(1);
    try stdout.print("조회 응답: {}\\n", .{response2.status()});
    if (response2.message()) |msg| {
        try stdout.print("  정보: {s}\\n", .{msg});
        allocator.free(msg);
    }
    try stdout.print("\\n", .{});

    // ============================================================================
    // 5️⃣ 캐싱 성능 최적화
    // ============================================================================

    try stdout.print("5️⃣ 캐싱 레이어 (성능 최적화)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    const cache = try Cache.init(allocator);
    defer cache.deinit();

    try cache.put(1, 1000);
    try cache.put(2, 2000);

    _ = cache.get(1); // Hit
    _ = cache.get(1); // Hit
    _ = cache.get(999); // Miss

    const stats = cache.stats();
    try stdout.print("캐시 통계: 히트={}, 미스={}\\n", .{ stats.hits, stats.misses });
    try stdout.print("히트율: {d:.1}%\\n\\n", .{
        @as(f32, @floatFromInt(stats.hits)) / @as(f32, @floatFromInt(stats.hits + stats.misses)) * 100,
    });

    // ============================================================================
    // 6️⃣ 시스템 구조도
    // ============================================================================

    try stdout.print("6️⃣ 시스템 아키텍처\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("┌─────────────────────────────────────┐\\n", .{});
    try stdout.print("│   Presentation Layer (API)          │\\n", .{});
    try stdout.print("│   - SystemAPI                       │\\n", .{});
    try stdout.print("│   - Request/Response 처리            │\\n", .{});
    try stdout.print("└─────────────────────────────────────┘\\n", .{});
    try stdout.print("            ↓\\n", .{});
    try stdout.print("┌─────────────────────────────────────┐\\n", .{});
    try stdout.print("│   Business Logic Layer              │\\n", .{});
    try stdout.print("│   - UserService                     │\\n", .{});
    try stdout.print("│   - 비즈니스 규칙 검증               │\\n", .{});
    try stdout.print("└─────────────────────────────────────┘\\n", .{});
    try stdout.print("            ↓\\n", .{});
    try stdout.print("┌─────────────────────────────────────┐\\n", .{});
    try stdout.print("│   Data Layer                        │\\n", .{});
    try stdout.print("│   - Database (Mutex 보호)            │\\n", .{});
    try stdout.print("│   - Record 관리                      │\\n", .{});
    try stdout.print("└─────────────────────────────────────┘\\n\\n", .{});

    // ============================================================================
    // 7️⃣ 설계 원칙
    // ============================================================================

    try stdout.print("7️⃣ 대규모 시스템 설계 원칙\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("1. 계층 분리 (Layering):\\n", .{});
    try stdout.print("   - 프레젠테이션, 비즈니스 로직, 데이터\\n", .{});
    try stdout.print("   - 변경 영향 최소화\\n\\n", .{});

    try stdout.print("2. 단일 책임 (Single Responsibility):\\n", .{});
    try stdout.print("   - 각 모듈은 하나의 역할만 담당\\n", .{});
    try stdout.print("   - 테스트 용이성\\n\\n", .{});

    try stdout.print("3. 의존성 주입 (Dependency Injection):\\n", .{});
    try stdout.print("   - 외부에서 주입받은 의존성 사용\\n", .{});
    try stdout.print("   - 느슨한 결합\\n\\n", .{});

    try stdout.print("4. 에러 처리 전략:\\n", .{});
    try stdout.print("   - 명확한 에러 정의\\n", .{});
    try stdout.print("   - 일관된 처리\\n\\n", .{});

    try stdout.print("5. 스레드 안전성:\\n", .{});
    try stdout.print("   - 공유 자원은 뮤텍스로 보호\\n", .{});
    try stdout.print("   - 데이터 경쟁 방지\\n\\n", .{});

    try stdout.print("6. 성능 최적화:\\n", .{});
    try stdout.print("   - 캐싱 레이어\\n", .{});
    try stdout.print("   - 비동기 처리\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-13 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-13 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ 계층 구조 (3-Tier Architecture)\\n", .{});
    try stdout.print("  ✓ 데이터 계층 (Database + Mutex)\\n", .{});
    try stdout.print("  ✓ 비즈니스 로직 (UserService)\\n", .{});
    try stdout.print("  ✓ 프레젠테이션 (API)\\n", .{});
    try stdout.print("  ✓ 에러 처리 전략\\n", .{});
    try stdout.print("  ✓ 성능 최적화 (캐싱)\\n", .{});
    try stdout.print("  ✓ 테스트 유틸리티\\n", .{});
    try stdout.print("  ✓ 설정 관리\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 설계는 구조를 결정한다\\n", .{});
    try stdout.print("  2. 계층 분리는 유지보수성을 높인다\\n", .{});
    try stdout.print("  3. 에러 처리는 전략이다\\n", .{});
    try stdout.print("  4. 동기화는 성능과 안전의 균형\\n", .{});
    try stdout.print("  5. 테스트 가능성은 설계의 증명\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig 전공 101을 완성했습니다!\\n", .{});
    try stdout.print("🚀 축하합니다! 당신은 이제 Zig 엔지니어입니다!\\n", .{});
}

// ============================================================================
// 테스트: 통합 시스템 검증
// ============================================================================

test "database insert and query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    try database.insert(1, "Test", 100);

    if (database.query(1)) |record| {
        try std.testing.expectEqual(@as(u32, 1), record.id);
        try std.testing.expectEqual(@as(i32, 100), record.value);
    } else {
        return error.QueryFailed;
    }
}

test "user service registration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    const user_service = try UserService.init(gpa.allocator(), database);
    defer user_service.deinit();

    try user_service.registerUser(1, "Alice", 1000);
    try std.testing.expectEqual(@as(usize, 1), user_service.totalUsers());
}

test "user service invalid id error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    const user_service = try UserService.init(gpa.allocator(), database);
    defer user_service.deinit();

    try std.testing.expectError(error.InvalidUserId, user_service.registerUser(0, "Invalid", 100));
}

test "user service negative credit error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    const user_service = try UserService.init(gpa.allocator(), database);
    defer user_service.deinit();

    try std.testing.expectError(error.NegativeCredit, user_service.registerUser(1, "Negative", -100));
}

test "cache get and put" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cache = try Cache.init(gpa.allocator());
    defer cache.deinit();

    try cache.put(1, 100);
    try std.testing.expectEqual(@as(?i32, 100), cache.get(1));
}

test "cache statistics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cache = try Cache.init(gpa.allocator());
    defer cache.deinit();

    try cache.put(1, 100);
    _ = cache.get(1); // Hit
    _ = cache.get(2); // Miss

    const stats = cache.stats();
    try std.testing.expectEqual(@as(u32, 1), stats.hits);
    try std.testing.expectEqual(@as(u32, 1), stats.misses);
}

test "system config singleton" {
    const config = SystemConfig.getInstance();
    try std.testing.expectEqual(@as(u32, 1000), config.max_users);
    try std.testing.expectEqual(@as(u32, 3), config.max_retry);
}

test "database count" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    try database.insert(1, "A", 10);
    try database.insert(2, "B", 20);
    try database.insert(3, "C", 30);

    try std.testing.expectEqual(@as(usize, 3), database.count());
}

test "multiple user registration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const database = try Database.init(gpa.allocator());
    defer database.deinit();

    const user_service = try UserService.init(gpa.allocator(), database);
    defer user_service.deinit();

    for (1..6) |i| {
        try user_service.registerUser(@as(u32, @intCast(i)), "User", 100);
    }

    try std.testing.expectEqual(@as(usize, 5), user_service.totalUsers());
}
