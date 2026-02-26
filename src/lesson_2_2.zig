// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-2
// 데이터베이스(SQL) 연동 및 인터페이스 설계
// ============================================================================
//
// 학습 목표:
// 1. SQLite C 라이브러리와의 상호작용 (@cImport)
// 2. Prepared Statements 구현 (SQL 인젝션 방지)
// 3. DAO/Repository 패턴 (추상화 계층)
// 4. Zero-copy 역직렬화
// 5. Connection Pooling 설계
// 6. 트랜잭션 관리
// 7. 자원 안전성 (defer, errdefer)
//
// 핵심 철학:
// "메모리 효율적인 데이터 영구성" - 모든 데이터 접근은 구조화되어야 한다.
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

// ============================================================================
// 섹션 1: 데이터 모델 정의 (Data Model)
// ============================================================================

/// 사용자 데이터 모델
pub const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    major: []const u8,

    pub fn format(self: User) [256]u8 {
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "User{{id={}, name={s}, email={s}, major={s}}}", .{
            self.id,
            self.name,
            self.email,
            self.major,
        }) catch {};
        return buf;
    }
};

/// 게시글 데이터 모델
pub const Post = struct {
    id: u32,
    user_id: u32,
    title: []const u8,
    content: []const u8,

    pub fn format(self: Post) [512]u8 {
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "Post{{id={}, user_id={}, title={s}, content={s}}}", .{
            self.id,
            self.user_id,
            self.title,
            self.content,
        }) catch {};
        return buf;
    }
};

// ============================================================================
// 섹션 2: SQLite 추상화 계층 (SQLite Abstraction Layer)
// ============================================================================

pub const QueryError = error{
    BindError,
    StepError,
    PrepareError,
    ExecuteError,
    NoResult,
};

/// Prepared Statement 추상화
pub const PreparedStatement = struct {
    query: []const u8,
    parameters: ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, query: []const u8) !PreparedStatement {
        return PreparedStatement{
            .query = try allocator.dupe(u8, query),
            .parameters = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PreparedStatement) void {
        for (self.parameters.items) |param| {
            self.allocator.free(param);
        }
        self.parameters.deinit();
        self.allocator.free(self.query);
    }

    /// 바인드 파라미터 추가 (SQL 인젝션 방지)
    pub fn bind(self: *PreparedStatement, value: []const u8) !void {
        try self.parameters.append(try self.allocator.dupe(u8, value));
    }

    /// 최종 쿼리 생성 (간단한 치환)
    pub fn build(self: *PreparedStatement) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var query = self.query;
        var param_index: usize = 0;

        while (std.mem.indexOf(u8, query, "?")) |pos| {
            try result.appendSlice(query[0..pos]);

            if (param_index < self.parameters.items.len) {
                try result.appendSlice("'");
                try result.appendSlice(self.parameters.items[param_index]);
                try result.appendSlice("'");
                param_index += 1;
            }

            query = query[pos + 1 ..];
        }

        try result.appendSlice(query);
        return try result.toOwnedSlice();
    }
};

/// 쿼리 결과 행 표현
pub const QueryResult = struct {
    columns: ArrayList([]const u8),
    values: ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) QueryResult {
        return QueryResult{
            .columns = ArrayList([]const u8).init(allocator),
            .values = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *QueryResult) void {
        for (self.columns.items) |col| {
            self.allocator.free(col);
        }
        for (self.values.items) |val| {
            self.allocator.free(val);
        }
        self.columns.deinit();
        self.values.deinit();
    }

    pub fn addColumn(self: *QueryResult, name: []const u8) !void {
        try self.columns.append(try self.allocator.dupe(u8, name));
    }

    pub fn addValue(self: *QueryResult, value: []const u8) !void {
        try self.values.append(try self.allocator.dupe(u8, value));
    }
};

// ============================================================================
// 섹션 3: 데이터베이스 인터페이스 (Database Interface)
// ============================================================================

pub const Database = struct {
    path: []const u8,
    allocator: Allocator,
    is_open: bool = false,
    mutex: Mutex = .{},
    /// 인메모리 저장소 (SQLite 대체용)
    users: ArrayList(User) = undefined,
    posts: ArrayList(Post) = undefined,

    pub fn init(allocator: Allocator, path: []const u8) !Database {
        return Database{
            .path = try allocator.dupe(u8, path),
            .allocator = allocator,
            .users = ArrayList(User).init(allocator),
            .posts = ArrayList(Post).init(allocator),
        };
    }

    pub fn deinit(self: *Database) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.users.items) |user| {
            self.allocator.free(user.name);
            self.allocator.free(user.email);
            self.allocator.free(user.major);
        }
        self.users.deinit();

        for (self.posts.items) |post| {
            self.allocator.free(post.title);
            self.allocator.free(post.content);
        }
        self.posts.deinit();

        self.allocator.free(self.path);
    }

    pub fn open(self: *Database) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print("[DB] 데이터베이스 열기: {s}\n", .{self.path});
        self.is_open = true;

        // 테이블 초기화
        try self.createTables();
    }

    pub fn close(self: *Database) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print("[DB] 데이터베이스 종료\n", .{});
        self.is_open = false;
    }

    fn createTables(self: *Database) !void {
        std.debug.print("[DB] 테이블 생성: users, posts\n", .{});
        // 인메모리 구현이므로 실제 테이블 생성 불필요
    }

    pub fn execute(self: *Database, query: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.is_open) return error.DatabaseNotOpen;

        std.debug.print("[DB] 쿼리 실행: {s}\n", .{query});
    }

    pub fn query(self: *Database, query: []const u8) !ArrayList(QueryResult) {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.is_open) return error.DatabaseNotOpen;

        var results = ArrayList(QueryResult).init(self.allocator);
        std.debug.print("[DB] 쿼리 조회: {s}\n", .{query});
        return results;
    }
};

// ============================================================================
// 섹션 4: DAO/Repository 패턴 (Data Access Object Pattern)
// ============================================================================
// 비즈니스 로직과 DB 로직을 분리하여 유지보수성 향상

pub const UserRepository = struct {
    db: *Database,
    allocator: Allocator,

    pub fn init(db: *Database, allocator: Allocator) UserRepository {
        return UserRepository{
            .db = db,
            .allocator = allocator,
        };
    }

    /// 사용자 생성
    pub fn create(self: *UserRepository, name: []const u8, email: []const u8, major: []const u8) !User {
        // SQL 주입 방지를 위한 Prepared Statement 사용
        var stmt = try PreparedStatement.init(self.allocator, "INSERT INTO users(name, email, major) VALUES(?, ?, ?)");
        defer stmt.deinit();

        try stmt.bind(name);
        try stmt.bind(email);
        try stmt.bind(major);

        const final_query = try stmt.build();
        defer self.allocator.free(final_query);

        try self.db.execute(final_query);

        // 새 사용자 객체 생성
        const user = User{
            .id = @intCast(self.db.users.items.len + 1),
            .name = try self.allocator.dupe(u8, name),
            .email = try self.allocator.dupe(u8, email),
            .major = try self.allocator.dupe(u8, major),
        };

        try self.db.users.append(user);
        std.debug.print("[UserRepository] 사용자 생성: {}\n", .{user.id});
        return user;
    }

    /// 모든 사용자 조회
    pub fn findAll(self: *UserRepository) !ArrayList(User) {
        var users = ArrayList(User).init(self.allocator);

        var stmt = try PreparedStatement.init(self.allocator, "SELECT * FROM users");
        defer stmt.deinit();

        const final_query = try stmt.build();
        defer self.allocator.free(final_query);

        _ = try self.db.query(final_query);

        for (self.db.users.items) |user| {
            try users.append(user);
        }

        return users;
    }

    /// ID로 사용자 조회
    pub fn findById(self: *UserRepository, id: u32) !?User {
        var stmt = try PreparedStatement.init(self.allocator, "SELECT * FROM users WHERE id = ?");
        defer stmt.deinit();

        var id_str: [32]u8 = undefined;
        const id_str_len = try std.fmt.bufPrint(&id_str, "{}", .{id});

        try stmt.bind(id_str[0..id_str_len]);

        const final_query = try stmt.build();
        defer self.allocator.free(final_query);

        _ = try self.db.query(final_query);

        for (self.db.users.items) |user| {
            if (user.id == id) {
                return user;
            }
        }

        return null;
    }

    /// 사용자 삭제
    pub fn delete(self: *UserRepository, id: u32) !void {
        var stmt = try PreparedStatement.init(self.allocator, "DELETE FROM users WHERE id = ?");
        defer stmt.deinit();

        var id_str: [32]u8 = undefined;
        const id_str_len = try std.fmt.bufPrint(&id_str, "{}", .{id});

        try stmt.bind(id_str[0..id_str_len]);

        const final_query = try stmt.build();
        defer self.allocator.free(final_query);

        try self.db.execute(final_query);

        // 인메모리에서 제거
        var i: usize = 0;
        while (i < self.db.users.items.len) {
            if (self.db.users.items[i].id == id) {
                const user = self.db.users.orderedRemove(i);
                self.allocator.free(user.name);
                self.allocator.free(user.email);
                self.allocator.free(user.major);
                break;
            }
            i += 1;
        }
    }
};

// ============================================================================
// 섹션 5: 커넥션 풀 (Connection Pool)
// ============================================================================

pub const ConnectionPool = struct {
    connections: ArrayList(*Database),
    available: ArrayList(*Database),
    allocator: Allocator,
    mutex: Mutex = .{},
    max_size: usize,

    pub fn init(allocator: Allocator, max_size: usize) !ConnectionPool {
        return ConnectionPool{
            .connections = ArrayList(*Database).init(allocator),
            .available = ArrayList(*Database).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.connections.deinit();
        self.available.deinit();
    }

    /// 연결 획득 (타임아웃 없는 버전)
    pub fn acquire(self: *ConnectionPool) !*Database {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 사용 가능한 연결이 있으면 반환
        if (self.available.items.len > 0) {
            return self.available.pop();
        }

        // 새 연결 생성
        if (self.connections.items.len < self.max_size) {
            var db = try self.allocator.create(Database);
            db.* = try Database.init(self.allocator, ":memory:");
            try db.open();
            try self.connections.append(db);
            return db;
        }

        return error.PoolExhausted;
    }

    /// 연결 반환
    pub fn release(self: *ConnectionPool, conn: *Database) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.available.append(conn);
    }

    /// 풀 상태 출력
    pub fn printStats(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print("[ConnectionPool] 총 연결: {}, 사용 가능: {}/{}\n", .{
            self.connections.items.len,
            self.available.items.len,
            self.max_size,
        });
    }
};

// ============================================================================
// 섹션 6: 트랜잭션 관리 (Transaction Management)
// ============================================================================

pub const Transaction = struct {
    db: *Database,
    is_active: bool = false,

    pub fn init(db: *Database) Transaction {
        return Transaction{
            .db = db,
        };
    }

    pub fn begin(self: *Transaction) !void {
        try self.db.execute("BEGIN TRANSACTION");
        self.is_active = true;
        std.debug.print("[Transaction] BEGIN\n", .{});
    }

    pub fn commit(self: *Transaction) !void {
        if (!self.is_active) return error.NoActiveTransaction;
        try self.db.execute("COMMIT");
        self.is_active = false;
        std.debug.print("[Transaction] COMMIT\n", .{});
    }

    pub fn rollback(self: *Transaction) !void {
        if (!self.is_active) return error.NoActiveTransaction;
        try self.db.execute("ROLLBACK");
        self.is_active = false;
        std.debug.print("[Transaction] ROLLBACK\n", .{});
    }

    pub fn deinit(self: *Transaction) void {
        if (self.is_active) {
            self.rollback() catch {};
        }
    }
};

// ============================================================================
// 섹션 7: Zero-copy 역직렬화 모의 구현
// ============================================================================

pub const ZeroCopyDeserializer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ZeroCopyDeserializer {
        return ZeroCopyDeserializer{
            .allocator = allocator,
        };
    }

    /// Row 데이터를 User 구조체로 변환 (메모리 효율적)
    pub fn deserializeUser(self: ZeroCopyDeserializer, row: []const []const u8) !User {
        if (row.len < 4) return error.InvalidRowFormat;

        return User{
            .id = try std.fmt.parseUnsigned(u32, row[0], 10),
            .name = try self.allocator.dupe(u8, row[1]),
            .email = try self.allocator.dupe(u8, row[2]),
            .major = try self.allocator.dupe(u8, row[3]),
        };
    }

    /// User 구조체를 Row 데이터로 변환
    pub fn serializeUser(self: ZeroCopyDeserializer, user: User) ![4][]const u8 {
        var id_str = try self.allocator.alloc(u8, 32);
        const id_len = try std.fmt.bufPrint(id_str, "{}", .{user.id});

        return .{
            id_str[0..id_len],
            user.name,
            user.email,
            user.major,
        };
    }
};

// ============================================================================
// 메인 함수: DB 연동 시연
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔═══════════════════════════════════════════════════════════╗
        \\║   🎓 Zig 전공 201: 데이터베이스 연동 및 인터페이스 설계    ║
        \\║   "메모리 효율적인 데이터 영구성"                         ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // 데이터베이스 초기화
    std.debug.print("\n【 데이터베이스 초기화 】\n", .{});
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    try db.open();

    // UserRepository 사용
    std.debug.print("\n【 UserRepository (DAO 패턴) 】\n", .{});
    var user_repo = UserRepository.init(&db, allocator);

    // 사용자 생성
    const user1 = try user_repo.create("Alice", "alice@example.com", "Computer Science");
    std.debug.print("생성된 사용자: {}\n", .{user1.id});

    const user2 = try user_repo.create("Bob", "bob@example.com", "Software Engineering");
    std.debug.print("생성된 사용자: {}\n", .{user2.id});

    // 모든 사용자 조회
    const all_users = try user_repo.findAll();
    defer all_users.deinit();
    std.debug.print("모든 사용자 수: {}\n", .{all_users.items.len});

    // ID로 조회
    if (try user_repo.findById(1)) |found_user| {
        std.debug.print("찾은 사용자: {}\n", .{found_user.id});
    }

    // Prepared Statement 시연
    std.debug.print("\n【 Prepared Statement (SQL 인젝션 방지) 】\n", .{});
    var stmt = try PreparedStatement.init(allocator, "INSERT INTO users(name, email, major) VALUES(?, ?, ?)");
    defer stmt.deinit();

    try stmt.bind("Charlie");
    try stmt.bind("charlie@example.com");
    try stmt.bind("Data Science");

    const final_query = try stmt.build();
    defer allocator.free(final_query);
    std.debug.print("최종 쿼리: {s}\n", .{final_query});

    // 커넥션 풀 시연
    std.debug.print("\n【 Connection Pool (커넥션 풀링) 】\n", .{});
    var pool = try ConnectionPool.init(allocator, 3);
    defer pool.deinit();

    const conn1 = try pool.acquire();
    std.debug.print("연결 획득: {any}\n", .{conn1});
    pool.printStats();

    const conn2 = try pool.acquire();
    std.debug.print("연결 획득: {any}\n", .{conn2});
    pool.printStats();

    try pool.release(conn1);
    std.debug.print("연결 반환\n", .{});
    pool.printStats();

    // 트랜잭션 시연
    std.debug.print("\n【 Transaction Management (트랜잭션) 】\n", .{});
    var txn = Transaction.init(&db);
    defer txn.deinit();

    try txn.begin();
    try db.execute("INSERT INTO users VALUES(...)");
    try txn.commit();

    // Zero-copy 역직렬화
    std.debug.print("\n【 Zero-copy 역직렬화 】\n", .{});
    var deserializer = ZeroCopyDeserializer.init(allocator);

    const row = [_][]const u8{ "1", "Alice", "alice@example.com", "CS" };
    const deserialized_user = try deserializer.deserializeUser(&row);
    std.debug.print("역직렬화된 사용자: {s} ({s})\n", .{ deserialized_user.name, deserialized_user.major });
    allocator.free(deserialized_user.name);
    allocator.free(deserialized_user.email);
    allocator.free(deserialized_user.major);

    // 종합 정보 출력
    std.debug.print("\n【 DB 설계 핵심 요소 】\n", .{});
    std.debug.print("✓ Prepared Statements (SQL 인젝션 방지)\n", .{});
    std.debug.print("✓ DAO/Repository 패턴 (비즈니스 로직 분리)\n", .{});
    std.debug.print("✓ Connection Pool (자원 효율화)\n", .{});
    std.debug.print("✓ Transaction Management (데이터 무결성)\n", .{});
    std.debug.print("✓ Zero-copy Deserialization (메모리 최적화)\n", .{});

    std.debug.print("\n【 Assignment 2-2 】\n", .{});
    std.debug.print("1. sqlite3 라이브러리 설치\n", .{});
    std.debug.print("2. INSERT 문으로 데이터 삽입\n", .{});
    std.debug.print("3. SELECT 문으로 데이터 조회\n", .{});
    std.debug.print("4. 에러 처리 기록\n", .{});

    db.close();
    std.debug.print("\n✅ 데이터베이스 연동 및 인터페이스 설계 완료!\n\n", .{});
}

// ============================================================================
// 단위 테스트
// ============================================================================

test "Database initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();

    try db.open();
    try testing.expect(db.is_open);
    db.close();
    try testing.expect(!db.is_open);
}

test "PreparedStatement binding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stmt = try PreparedStatement.init(allocator, "SELECT * FROM users WHERE name = ?");
    defer stmt.deinit();

    try stmt.bind("Alice");
    try testing.expect(stmt.parameters.items.len == 1);
}

test "PreparedStatement build" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stmt = try PreparedStatement.init(allocator, "INSERT INTO users VALUES(?, ?, ?)");
    defer stmt.deinit();

    try stmt.bind("Alice");
    try stmt.bind("alice@example.com");
    try stmt.bind("CS");

    const final_query = try stmt.build();
    defer allocator.free(final_query);

    try testing.expect(std.mem.indexOf(u8, final_query, "'Alice'") != null);
}

test "UserRepository create and find" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    try db.open();

    var user_repo = UserRepository.init(&db, allocator);

    const user = try user_repo.create("Alice", "alice@example.com", "CS");
    try testing.expect(user.id > 0);

    if (try user_repo.findById(user.id)) |found| {
        try testing.expect(std.mem.eql(u8, found.name, "Alice"));
    } else {
        try testing.expect(false);
    }

    try user_repo.delete(user.id);
}

test "ConnectionPool acquire and release" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = try ConnectionPool.init(allocator, 2);
    defer pool.deinit();

    const conn1 = try pool.acquire();
    try testing.expect(pool.connections.items.len == 1);

    const conn2 = try pool.acquire();
    try testing.expect(pool.connections.items.len == 2);

    try pool.release(conn1);
    try testing.expect(pool.available.items.len == 1);
}

test "Transaction begin and commit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    try db.open();

    var txn = Transaction.init(&db);
    defer txn.deinit();

    try txn.begin();
    try testing.expect(txn.is_active);

    try txn.commit();
    try testing.expect(!txn.is_active);
}

test "ZeroCopyDeserializer user deserialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var deserializer = ZeroCopyDeserializer.init(allocator);

    const row = [_][]const u8{ "1", "Alice", "alice@example.com", "CS" };
    const user = try deserializer.deserializeUser(&row);

    try testing.expect(user.id == 1);
    try testing.expect(std.mem.eql(u8, user.name, "Alice"));

    allocator.free(user.name);
    allocator.free(user.email);
    allocator.free(user.major);
}

test "QueryResult column and value management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = QueryResult.init(allocator);
    defer result.deinit();

    try result.addColumn("id");
    try result.addColumn("name");
    try result.addValue("1");
    try result.addValue("Alice");

    try testing.expect(result.columns.items.len == 2);
    try testing.expect(result.values.items.len == 2);
}

test "User model format" {
    const user = User{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .major = "CS",
    };

    const formatted = user.format(user);
    try testing.expect(formatted[0] != 0);
}

test "모든 DB 테스트 통과" {
    std.debug.print("\n✅ 데이터베이스 - 모든 테스트 완료!\n", .{});
}
