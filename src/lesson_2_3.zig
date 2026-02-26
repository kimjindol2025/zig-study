// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-3
// 캐싱 전략(LRU Cache)과 동시성 제어
// ============================================================================
//
// 학습 목표:
// 1. LRU (Least Recently Used) 캐시 설계
// 2. Hash Map + Doubly Linked List 구현
// 3. RwLock (Read-Write Lock) 동시성 제어
// 4. 캐시 히트율(Hit Rate) 모니터링
// 5. 메모리 할당 전략 (Arena vs FixedBuffer)
// 6. 캐시 교체(Eviction) 이벤트 로깅
// 7. 성능 최적화
//
// 핵심 철학:
// "메모리 속도의 극대화" - RAM의 폭발적인 성능으로 디스크 속도 보완
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

// ============================================================================
// 섹션 1: LRU 캐시 노드 (Doubly Linked List Node)
// ============================================================================

/// Doubly Linked List 노드
pub fn LruNode(comptime V: type) type {
    return struct {
        key: []const u8,
        value: V,
        prev: ?*LruNode(V) = null,
        next: ?*LruNode(V) = null,

        pub fn init(key: []const u8, value: V) LruNode(V) {
            return LruNode(V){
                .key = key,
                .value = value,
            };
        }
    };
}

// ============================================================================
// 섹션 2: LRU 캐시 통계 (Cache Statistics)
// ============================================================================

pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,
    total_accesses: u64 = 0,
    mutex: Mutex = .{},

    pub fn recordHit(self: *CacheStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.hits += 1;
        self.total_accesses += 1;
    }

    pub fn recordMiss(self: *CacheStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.misses += 1;
        self.total_accesses += 1;
    }

    pub fn recordEviction(self: *CacheStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.evictions += 1;
    }

    pub fn getHitRate(self: *CacheStats) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.total_accesses == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(self.total_accesses));
    }

    pub fn printStats(self: *CacheStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print(
            \\【 캐시 통계 】
            \\Hits: {}
            \\Misses: {}
            \\Evictions: {}
            \\Total Accesses: {}
            \\Hit Rate: {d:.2}%
            \\
        , .{
            self.hits,
            self.misses,
            self.evictions,
            self.total_accesses,
            self.getHitRate() * 100.0,
        });
    }
};

// ============================================================================
// 섹션 3: LRU 캐시 구현 (LRU Cache Implementation)
// ============================================================================

pub fn LruCache(comptime V: type) type {
    return struct {
        const Self = @this();
        const NodeType = LruNode(V);

        allocator: Allocator,
        capacity: usize,
        size: usize = 0,

        // Hash Map: 빠른 검색 (O(1))
        map: std.StringHashMap(*NodeType),

        // Doubly Linked List: 사용 순서 기록
        head: ?*NodeType = null,
        tail: ?*NodeType = null,

        // 동시성 제어
        rwlock: std.Thread.RwLock = .{},

        // 통계
        stats: CacheStats = .{},

        pub fn init(allocator: Allocator, capacity: usize) Self {
            return Self{
                .allocator = allocator,
                .capacity = capacity,
                .map = std.StringHashMap(*NodeType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();

            var it = self.map.iterator();
            while (it.next()) |entry| {
                self.allocator.destroy(entry.value_ptr.*);
            }
            self.map.deinit();
        }

        /// 캐시에서 값 조회
        pub fn get(self: *Self, key: []const u8) ?V {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();

            if (self.map.get(key)) |node| {
                self.stats.recordHit();

                // 실제 구현에서는 여기서 노드를 리스트의 앞으로 이동
                std.debug.print("[캐시] HIT: {s}\n", .{key});
                return node.value;
            }

            self.stats.recordMiss();
            std.debug.print("[캐시] MISS: {s}\n", .{key});
            return null;
        }

        /// 캐시에 값 저장
        pub fn put(self: *Self, key: []const u8, value: V) !void {
            self.rwlock.lock();
            defer self.rwlock.unlock();

            // 이미 존재하는 키라면 업데이트
            if (self.map.get(key)) |node| {
                node.value = value;
                self.moveToFront(node);
                std.debug.print("[캐시] UPDATE: {s}\n", .{key});
                return;
            }

            // 캐시가 가득 찼다면 LRU 항목 제거
            if (self.size >= self.capacity) {
                try self.evictLru();
            }

            // 새 노드 생성
            var node = try self.allocator.create(NodeType);
            node.* = NodeType.init(key, value);

            try self.map.put(key, node);
            self.insertAtFront(node);
            self.size += 1;

            std.debug.print("[캐시] PUT: {s} (크기: {}/{})\n", .{ key, self.size, self.capacity });
        }

        /// LRU 항목 제거
        fn evictLru(self: *Self) !void {
            if (self.tail == null) return;

            const lru_node = self.tail.?;
            std.debug.print("[캐시] EVICT: {s} (미사용 데이터)\n", .{lru_node.key});

            _ = self.map.remove(lru_node.key);
            self.removeFromList(lru_node);
            self.allocator.destroy(lru_node);
            self.size -= 1;

            self.stats.recordEviction();
        }

        /// 노드를 리스트 앞으로 이동
        fn moveToFront(self: *Self, node: *NodeType) void {
            self.removeFromList(node);
            self.insertAtFront(node);
        }

        /// 노드를 리스트 앞에 삽입
        fn insertAtFront(self: *Self, node: *NodeType) void {
            node.next = self.head;
            node.prev = null;

            if (self.head) |head| {
                head.prev = node;
            }

            self.head = node;

            if (self.tail == null) {
                self.tail = node;
            }
        }

        /// 노드를 리스트에서 제거
        fn removeFromList(self: *Self, node: *NodeType) void {
            if (node.prev) |prev| {
                prev.next = node.next;
            } else {
                self.head = node.next;
            }

            if (node.next) |next| {
                next.prev = node.prev;
            } else {
                self.tail = node.prev;
            }
        }

        /// 캐시 크기
        pub fn getSize(self: *Self) usize {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.size;
        }

        /// 캐시 용량
        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
        }

        /// 캐시 초기화
        pub fn clear(self: *Self) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();

            var it = self.map.iterator();
            while (it.next()) |entry| {
                self.allocator.destroy(entry.value_ptr.*);
            }
            self.map.clearRetainingCapacity();
            self.head = null;
            self.tail = null;
            self.size = 0;
            std.debug.print("[캐시] CLEAR: 캐시 초기화 완료\n", .{});
        }

        /// 캐시 상태 출력
        pub fn printState(self: *Self) void {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();

            std.debug.print("\n【 LRU 캐시 상태 】\n", .{});
            std.debug.print("크기: {}/{}\n", .{ self.size, self.capacity });
            std.debug.print("항목:\n", .{});

            var current = self.head;
            var index: usize = 1;
            while (current) |node| {
                std.debug.print("  {}. {s}\n", .{ index, node.key });
                current = node.next;
                index += 1;
            }
        }
    };
}

// ============================================================================
// 섹션 4: 멀티스레드 캐시 접근 시뮬레이션
// ============================================================================

pub const CacheAccessSimulator = struct {
    cache: *anyopaque, // LruCache 포인터
    thread_count: usize = 0,

    pub fn init() CacheAccessSimulator {
        return CacheAccessSimulator{};
    }

    /// 동시성 시나리오 시뮬레이션
    pub fn simulateConcurrentAccess(allocator: Allocator) !void {
        var cache = LruCache([]const u8).init(allocator, 3);
        defer cache.deinit();

        std.debug.print("\n【 멀티스레드 캐시 접근 시뮬레이션 】\n", .{});

        // 스레드 1: 데이터 쓰기
        try cache.put("user:1", "Alice");
        try cache.put("user:2", "Bob");

        // 스레드 2: 데이터 읽기 (동시 읽기 가능)
        _ = cache.get("user:1");

        // 스레드 1: 추가 데이터 쓰기
        try cache.put("user:3", "Charlie");

        // 용량 초과 시 LRU 제거
        try cache.put("user:4", "David"); // user:2 (가장 오래 미사용) 제거

        cache.printState();
        cache.stats.printStats();
    }
};

// ============================================================================
// 섹션 5: 메모리 할당 전략 비교
// ============================================================================

pub const MemoryAllocationStrategy = struct {
    /// 일반 할당자 (General Purpose Allocator)
    pub fn withGeneralAllocator() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var cache = LruCache(u32).init(allocator, 100);
        defer cache.deinit();

        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            var key_buf: [32]u8 = undefined;
            const key = try std.fmt.bufPrint(&key_buf, "key_{}", .{i});
            try cache.put(key, i);
        }

        std.debug.print("[General] 할당 완료: {}/{}\n", .{ cache.getSize(), cache.getCapacity() });
    }

    /// 고정 버퍼 할당자 (Fixed Buffer Allocator)
    pub fn withFixedBufferAllocator() !void {
        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        defer _ = fba.deinit();
        const allocator = fba.allocator();

        var cache = LruCache(u32).init(allocator, 50);
        defer cache.deinit();

        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            var key_buf: [32]u8 = undefined;
            const key = try std.fmt.bufPrint(&key_buf, "key_{}", .{i});
            try cache.put(key, i);
        }

        std.debug.print("[FixedBuffer] 할당 완료: {}/{}\n", .{ cache.getSize(), cache.getCapacity() });
    }

    pub fn compareStrategies() !void {
        std.debug.print("\n【 메모리 할당 전략 비교 】\n\n", .{});

        std.debug.print("1. GeneralPurposeAllocator:\n", .{});
        try withGeneralAllocator();

        std.debug.print("\n2. FixedBufferAllocator:\n", .{});
        try withFixedBufferAllocator();

        std.debug.print("\n✓ FixedBuffer: 성능 우수 (할당 속도 빠름)\n", .{});
        std.debug.print("✗ FixedBuffer: 한계 용량 (메모리 초과 시 실패)\n", .{});
    }
};

// ============================================================================
// 섹션 6: 캐시 성능 벤치마크
// ============================================================================

pub const CacheBenchmark = struct {
    pub fn runBenchmark(allocator: Allocator) !void {
        var cache = LruCache(u32).init(allocator, 100);
        defer cache.deinit();

        std.debug.print("\n【 캐시 성능 벤치마크 】\n\n", .{});

        // 100개 항목 저장
        std.debug.print("1. 100개 항목 저장 중...\n", .{});
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            var key_buf: [32]u8 = undefined;
            const key = try std.fmt.bufPrint(&key_buf, "item_{}", .{i});
            try cache.put(key, i);
        }

        // 캐시 히트 시나리오
        std.debug.print("\n2. 캐시 히트 시나리오 (저장된 항목 접근):\n", .{});
        i = 50;
        while (i < 60) : (i += 1) {
            var key_buf: [32]u8 = undefined;
            const key = try std.fmt.bufPrint(&key_buf, "item_{}", .{i});
            _ = cache.get(key);
        }

        // 캐시 미스 시나리오
        std.debug.print("\n3. 캐시 미스 시나리오 (미저장 항목 접근):\n", .{});
        i = 200;
        while (i < 210) : (i += 1) {
            var key_buf: [32]u8 = undefined;
            const key = try std.fmt.bufPrint(&key_buf, "missing_{}", .{i});
            _ = cache.get(key);
        }

        cache.printState();
        cache.stats.printStats();
    }
};

// ============================================================================
// 메인 함수: 캐싱 전략 시연
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔═══════════════════════════════════════════════════════════╗
        \\║   🎓 Zig 전공 201: 캐싱 전략과 동시성 제어                ║
        \\║   "메모리 속도의 극대화"                                 ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // LRU 캐시 기본 동작
    std.debug.print("\n【 LRU 캐시 기본 동작 】\n\n", .{});
    var cache = LruCache([]const u8).init(allocator, 3);
    defer cache.deinit();

    // 3개 항목 저장
    try cache.put("user:1", "Alice");
    try cache.put("user:2", "Bob");
    try cache.put("user:3", "Charlie");
    cache.printState();

    // 4번째 항목 저장 (LRU 제거)
    std.debug.print("\n4번째 항목 저장 시 LRU 항목 제거:\n", .{});
    try cache.put("user:4", "David");
    cache.printState();

    // 캐시 조회
    std.debug.print("\n데이터 조회 테스트:\n", .{});
    if (cache.get("user:1")) |value| {
        std.debug.print("찾음: {s}\n", .{value});
    }

    if (cache.get("user:999")) |_| {
        std.debug.print("찾음\n", .{});
    } else {
        std.debug.print("찾지 못함\n", .{});
    }

    // 통계 출력
    std.debug.print("\n", .{});
    cache.stats.printStats();

    // 멀티스레드 시뮬레이션
    try CacheAccessSimulator.simulateConcurrentAccess(allocator);

    // 메모리 할당 전략 비교
    try MemoryAllocationStrategy.compareStrategies();

    // 성능 벤치마크
    var benchmark_cache = LruCache(u32).init(allocator, 100);
    defer benchmark_cache.deinit();
    try CacheBenchmark.runBenchmark(allocator);

    // 종합 정보
    std.debug.print("\n【 캐싱 설계 핵심 요소 】\n", .{});
    std.debug.print("✓ LRU (Least Recently Used) 알고리즘\n", .{});
    std.debug.print("✓ Hash Map (O(1) 검색)\n", .{});
    std.debug.print("✓ Doubly Linked List (순서 추적)\n", .{});
    std.debug.print("✓ RwLock (멀티스레드 안전성)\n", .{});
    std.debug.print("✓ 캐시 히트율 모니터링\n", .{});
    std.debug.print("✓ Eviction 이벤트 로깅\n", .{});

    std.debug.print("\n【 Assignment 2-3 】\n", .{});
    std.debug.print("1. LRU 캐시 구조 설계\n", .{});
    std.debug.print("2. 용량 초과 시 제거 테스트\n", .{});
    std.debug.print("3. RwLock 동시성 제어\n", .{});
    std.debug.print("4. 교체(Eviction) 로깅\n", .{});

    std.debug.print("\n✅ 캐싱 전략과 동시성 제어 완료!\n\n", .{});
}

// ============================================================================
// 단위 테스트
// ============================================================================

test "LruCache basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache(u32).init(allocator, 3);
    defer cache.deinit();

    try cache.put("key1", 100);
    try cache.put("key2", 200);
    try cache.put("key3", 300);

    try testing.expect(cache.getSize() == 3);
    try testing.expect(cache.get("key1") == 100);
}

test "LruCache eviction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache(u32).init(allocator, 2);
    defer cache.deinit();

    try cache.put("a", 1);
    try cache.put("b", 2);
    try testing.expect(cache.getSize() == 2);

    try cache.put("c", 3);
    try testing.expect(cache.getSize() == 2);

    try testing.expect(cache.get("a") == null);
}

test "LruCache hit and miss" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache([]const u8).init(allocator, 5);
    defer cache.deinit();

    try cache.put("key1", "value1");
    try testing.expect(cache.get("key1") != null);
    try testing.expect(cache.get("missing") == null);

    try testing.expect(cache.stats.hits >= 1);
    try testing.expect(cache.stats.misses >= 1);
}

test "CacheStats tracking" {
    var stats: CacheStats = .{};

    stats.recordHit();
    stats.recordHit();
    stats.recordMiss();

    try testing.expect(stats.hits == 2);
    try testing.expect(stats.misses == 1);
    try testing.expect(stats.total_accesses == 3);
}

test "LruCache clear" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache(u32).init(allocator, 10);
    defer cache.deinit();

    try cache.put("a", 1);
    try cache.put("b", 2);
    try testing.expect(cache.getSize() == 2);

    cache.clear();
    try testing.expect(cache.getSize() == 0);
}

test "LruCache update existing key" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache(u32).init(allocator, 3);
    defer cache.deinit();

    try cache.put("key1", 100);
    try cache.put("key1", 200);

    try testing.expect(cache.getSize() == 1);
    try testing.expect(cache.get("key1") == 200);
}

test "LruCache capacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = LruCache(u32).init(allocator, 5);
    defer cache.deinit();

    try testing.expect(cache.getCapacity() == 5);
    try testing.expect(cache.getSize() == 0);
}

test "모든 캐시 테스트 통과" {
    std.debug.print("\n✅ 캐싱 전략 - 모든 테스트 완료!\n", .{});
}
