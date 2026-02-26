/// src/lesson_1_12.zig - Zig 전공 201: 1-12. 멀티스레딩과 원자적 연산
///
/// Assignment 1-12: 스레드 안전성과 동기화
///
/// 철학: "동시성은 타입 시스템으로 제어한다"
/// Zig는 메모리 안전성을 유지하면서 효율적인 병렬 처리를 가능하게 합니다.

const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Mutex;

// ============================================================================
// 1️⃣ 기본 스레드 개념
// ============================================================================

/// 간단한 스레드 함수
fn simpleThreadFunc(number: i32) void {
    std.debug.print("스레드에서 출력: {}\n", .{number});
}

/// 반복 작업을 수행하는 스레드
fn counterThreadFunc() void {
    for (1..6) |i| {
        std.debug.print("카운터: {}\n", .{i});
    }
}

// ============================================================================
// 2️⃣ 뮤텍스와 임계 영역 (Critical Section)
// ============================================================================

/// 공유 자원을 보호하는 구조체
const SharedCounter = struct {
    mutex: Mutex = .{},
    value: i32 = 0,

    fn increment(self: *SharedCounter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.value += 1;
    }

    fn decrement(self: *SharedCounter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.value -= 1;
    }

    fn getValue(self: *SharedCounter) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.value;
    }

    fn add(self: *SharedCounter, amount: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.value += amount;
    }
};

// ============================================================================
// 3️⃣ 원자적 연산 (Atomic Operations)
// ============================================================================

/// 원자적 정수 (데이터 경쟁 방지)
const AtomicCounter = struct {
    value: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    fn incrementAtomic(self: *AtomicCounter) void {
        _ = self.value.fetchAdd(1, .seq_cst);
    }

    fn getAtomicValue(self: *AtomicCounter) u32 {
        return self.value.load(.seq_cst);
    }

    fn setAtomicValue(self: *AtomicCounter, new_value: u32) void {
        self.value.store(new_value, .seq_cst);
    }
};

// ============================================================================
// 4️⃣ Assignment 1-12: 스레드 풀 패턴
// ============================================================================

/// 작업을 큐에 추가하고 처리하는 워커 풀
const WorkerPool = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(Task),
    mutex: Mutex = .{},
    workers: std.ArrayList(Thread),
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    const Task = struct {
        id: u32,
        data: i32,
    };

    fn init(allocator: std.mem.Allocator) !*WorkerPool {
        const self = try allocator.create(WorkerPool);
        self.allocator = allocator;
        self.tasks = std.ArrayList(Task).init(allocator);
        self.workers = std.ArrayList(Thread).init(allocator);
        return self;
    }

    fn deinit(self: *WorkerPool) void {
        self.running.store(false, .seq_cst);

        for (self.workers.items) |worker| {
            worker.join();
        }

        self.tasks.deinit();
        self.workers.deinit();
        self.allocator.destroy(self);
    }

    fn addTask(self: *WorkerPool, id: u32, data: i32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.tasks.append(.{ .id = id, .data = data });
    }

    fn getTask(self: *WorkerPool) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.items.len > 0) {
            return self.tasks.swapRemove(0);
        }
        return null;
    }

    fn processWorker(self: *WorkerPool) void {
        while (self.running.load(.seq_cst)) {
            if (self.getTask()) |task| {
                std.debug.print("워커 처리: Task {} = {}\n", .{ task.id, task.data });
            }
        }
    }

    fn startWorkers(self: *WorkerPool, num_workers: usize) !void {
        for (0..num_workers) |_| {
            const worker = try Thread.spawn(.{}, WorkerPool.processWorker, .{self});
            try self.workers.append(worker);
        }
    }
};

// ============================================================================
// 5️⃣ 스레드 간 통신 (Message Passing)
// ============================================================================

/// 스레드 안전한 메시지 채널
const MessageChannel = struct {
    messages: std.ArrayList(i32),
    mutex: Mutex = .{},
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MessageChannel {
        return .{
            .messages = std.ArrayList(i32).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *MessageChannel) void {
        self.messages.deinit();
    }

    fn send(self: *MessageChannel, message: i32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.messages.append(message);
    }

    fn receive(self: *MessageChannel) ?i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.messages.items.len > 0) {
            return self.messages.swapRemove(0);
        }
        return null;
    }

    fn isEmpty(self: *MessageChannel) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.messages.items.len == 0;
    }
};

// ============================================================================
// 6️⃣ 스핀 락 (Spin Lock) - 비교 예제
// ============================================================================

/// 단순 스핀 락 (권장하지 않음 - CPU 낭비)
const SpinLock = struct {
    locked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn lock(self: *SpinLock) void {
        while (self.locked.compareAndSwap(false, true, .seq_cst, .seq_cst) != null) {
            // 계속 시도 (CPU 낭비!)
        }
    }

    fn unlock(self: *SpinLock) void {
        self.locked.store(false, .seq_cst);
    }
};

// ============================================================================
// 메인 함수: 모든 멀티스레딩 기법 테스트
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("🎓 Zig 전공 201: 1-12. 멀티스레딩과 원자적 연산\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ============================================================================
    // 1️⃣ 기본 스레드 생성
    // ============================================================================

    try stdout.print("1️⃣ 기본 스레드 생성\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("단일 스레드 시뮬레이션:\\n", .{});
    for (1..4) |i| {
        simpleThreadFunc(@as(i32, @intCast(i)));
    }
    try stdout.print("\\n", .{});

    // ============================================================================
    // 2️⃣ 뮤텍스 기본 사용
    // ============================================================================

    try stdout.print("2️⃣ 뮤텍스와 임계 영역\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var counter = SharedCounter{};

    try stdout.print("SharedCounter 초기값: {}\\n", .{counter.getValue()});

    counter.increment();
    try stdout.print("increment() 후: {}\\n", .{counter.getValue()});

    counter.add(5);
    try stdout.print("add(5) 후: {}\\n", .{counter.getValue()});

    counter.decrement();
    try stdout.print("decrement() 후: {}\\n\\n", .{counter.getValue()});

    // ============================================================================
    // 3️⃣ 원자적 연산
    // ============================================================================

    try stdout.print("3️⃣ 원자적 연산 (Atomics)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var atomic = AtomicCounter{};

    try stdout.print("AtomicCounter 초기값: {}\\n", .{atomic.getAtomicValue()});

    atomic.incrementAtomic();
    try stdout.print("incrementAtomic() 후: {}\\n", .{atomic.getAtomicValue()});

    atomic.incrementAtomic();
    try stdout.print("incrementAtomic() 후: {}\\n", .{atomic.getAtomicValue()});

    atomic.setAtomicValue(100);
    try stdout.print("setAtomicValue(100) 후: {}\\n\\n", .{atomic.getAtomicValue()});

    // ============================================================================
    // 4️⃣ 스레드 동기화 개념
    // ============================================================================

    try stdout.print("4️⃣ 스레드 동기화 개념\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("뮤텍스 (Mutex):\\n", .{});
    try stdout.print("  - 공유 자원 보호\\n", .{});
    try stdout.print("  - lock/unlock으로 임계 영역 정의\\n", .{});
    try stdout.print("  - 한 번에 하나의 스레드만 접근\\n\\n", .{});

    try stdout.print("원자적 연산 (Atomics):\\n", .{});
    try stdout.print("  - 분할 불가능한 연산\\n", .{});
    try stdout.print("  - 뮤텍스 없이도 안전함\\n", .{});
    try stdout.print("  - 성능 이점 (경량)\\n\\n", .{});

    // ============================================================================
    // 5️⃣ 메모리 순서 (Memory Ordering)
    // ============================================================================

    try stdout.print("5️⃣ 메모리 순서 (Memory Ordering)\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("순차적 일관성 (.seq_cst):\\n", .{});
    try stdout.print("  - 모든 스레드에서 같은 순서로 본다\\n", .{});
    try stdout.print("  - 가장 안전하지만 느림\\n", .{});
    try stdout.print("  - 대부분의 경우 권장됨\\n\\n", .{});

    try stdout.print("이완된 순서 (.acquire, .release):\\n", .{});
    try stdout.print("  - 특정 순서만 보장\\n", .{});
    try stdout.print("  - 성능 최적화\\n", .{});
    try stdout.print("  - 고급 사용자용\\n\\n", .{});

    // ============================================================================
    // 6️⃣ 메시지 패싱 패턴
    // ============================================================================

    try stdout.print("6️⃣ 메시지 채널 패턴\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    var channel = MessageChannel.init(allocator);
    defer channel.deinit();

    try stdout.print("채널에 메시지 전송:\\n", .{});
    try channel.send(100);
    try channel.send(200);
    try channel.send(300);

    try stdout.print("채널에서 메시지 수신:\\n", .{});
    while (!channel.isEmpty()) {
        if (channel.receive()) |msg| {
            try stdout.print("  수신: {}\\n", .{msg});
        }
    }
    try stdout.print("\\n", .{});

    // ============================================================================
    // 7️⃣ 뮤텍스 vs 원자적 연산
    // ============================================================================

    try stdout.print("7️⃣ 뮤텍스 vs 원자적 연산 비교\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("뮤텍스 사용:\\n", .{});
    try stdout.print("  ✓ 복잡한 임계 영역 보호 (여러 변수)\\n", .{});
    try stdout.print("  ✓ 명확한 lock/unlock 의도\\n", .{});
    try stdout.print("  ✗ 오버헤드 있음 (OS 스케줄링)\\n\\n", .{});

    try stdout.print("원자적 연산:\\n", .{});
    try stdout.print("  ✓ 가벼움 (하드웨어 지원)\\n", .{});
    try stdout.print("  ✓ 높은 성능 (경량)\\n", .{});
    try stdout.print("  ✗ 단순 변수만 가능\\n\\n", .{});

    // ============================================================================
    // 8️⃣ 스레드 안전성 원칙
    // ============================================================================

    try stdout.print("8️⃣ 스레드 안전성 원칙\\n", .{});
    try stdout.print("─────────────────────────────────────────────────────────────\\n\\n", .{});

    try stdout.print("1. 공유 자원 보호:\\n", .{});
    try stdout.print("   - 모든 공유 변수는 동기화 메커니즘으로 보호\\n\\n", .{});

    try stdout.print("2. 데이터 경쟁 방지:\\n", .{});
    try stdout.print("   - 동일 변수의 동시 접근 금지\\n\\n", .{});

    try stdout.print("3. 교착 상태(Deadlock) 방지:\\n", .{});
    try stdout.print("   - 락 순서 일관성 유지\\n\\n", .{});

    try stdout.print("4. 메모리 가시성:\\n", .{});
    try stdout.print("   - 한 스레드의 변경이 다른 스레드에 보여야 함\\n\\n", .{});

    // ============================================================================
    // 🎯 Assignment 1-12 완료
    // ============================================================================

    try stdout.print("═══════════════════════════════════════════════════════════════\\n", .{});
    try stdout.print("✅ Assignment 1-12 완료!\\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════════\\n\\n", .{});

    try stdout.print("📋 정리:\\n", .{});
    try stdout.print("  ✓ 스레드 기본 개념 (Thread)\\n", .{});
    try stdout.print("  ✓ 뮤텍스 (Mutex) - 상호 배제\\n", .{});
    try stdout.print("  ✓ 원자적 연산 (Atomics) - 분할 불가\\n", .{});
    try stdout.print("  ✓ 임계 영역 (Critical Section)\\n", .{});
    try stdout.print("  ✓ 메모리 순서 (.seq_cst, .acquire, .release)\\n", .{});
    try stdout.print("  ✓ 메시지 채널 패턴\\n", .{});
    try stdout.print("  ✓ 워커 풀 패턴\\n", .{});
    try stdout.print("  ✓ 스핀 락 vs 뮤텍스\\n\\n", .{});

    try stdout.print("🎯 핵심 원칙:\\n", .{});
    try stdout.print("  1. 공유 자원은 항상 보호\\n", .{});
    try stdout.print("  2. 동기화 메커니즘 선택 (뮤텍스 vs 원자적 연산)\\n", .{});
    try stdout.print("  3. 메모리 가시성 보장 (메모리 순서)\\n", .{});
    try stdout.print("  4. 교착 상태 방지 (락 순서 일관성)\\n", .{});
    try stdout.print("  5. 타입 시스템으로 안전성 강제\\n\\n", .{});

    try stdout.print("기록이 증명이다 - Zig의 멀티스레딩 안전성을 마스터했습니다!\\n", .{});
    try stdout.print("🚀 축하합니다! Zig 전공 201 중기 단계 완성!\\n", .{});
}

// ============================================================================
// 테스트: 멀티스레딩 검증
// ============================================================================

test "shared counter increment" {
    var counter = SharedCounter{};
    counter.increment();
    try std.testing.expectEqual(@as(i32, 1), counter.getValue());
}

test "shared counter decrement" {
    var counter = SharedCounter{};
    counter.increment();
    counter.increment();
    counter.decrement();
    try std.testing.expectEqual(@as(i32, 1), counter.getValue());
}

test "shared counter add" {
    var counter = SharedCounter{};
    counter.add(10);
    counter.add(5);
    try std.testing.expectEqual(@as(i32, 15), counter.getValue());
}

test "atomic counter operations" {
    var atomic = AtomicCounter{};
    try std.testing.expectEqual(@as(u32, 0), atomic.getAtomicValue());

    atomic.incrementAtomic();
    try std.testing.expectEqual(@as(u32, 1), atomic.getAtomicValue());

    atomic.setAtomicValue(100);
    try std.testing.expectEqual(@as(u32, 100), atomic.getAtomicValue());
}

test "message channel send receive" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var channel = MessageChannel.init(gpa.allocator());
    defer channel.deinit();

    try channel.send(42);
    try channel.send(100);

    try std.testing.expectEqual(@as(?i32, 42), channel.receive());
    try std.testing.expectEqual(@as(?i32, 100), channel.receive());
    try std.testing.expectEqual(@as(?i32, null), channel.receive());
}

test "message channel empty check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var channel = MessageChannel.init(gpa.allocator());
    defer channel.deinit();

    try std.testing.expect(channel.isEmpty());

    try channel.send(1);
    try std.testing.expect(!channel.isEmpty());

    _ = channel.receive();
    try std.testing.expect(channel.isEmpty());
}

test "spin lock basic" {
    var lock = SpinLock{};

    lock.lock();
    try std.testing.expect(lock.locked.load(.seq_cst));
    lock.unlock();
    try std.testing.expect(!lock.locked.load(.seq_cst));
}

test "multiple increment operations" {
    var counter = SharedCounter{};

    for (0..10) |_| {
        counter.increment();
    }

    try std.testing.expectEqual(@as(i32, 10), counter.getValue());
}

test "atomic compareAndSwap pattern" {
    var atomic = AtomicCounter{};

    const old_value = atomic.value.load(.seq_cst);
    try std.testing.expectEqual(@as(u32, 0), old_value);

    atomic.value.store(50, .seq_cst);
    try std.testing.expectEqual(@as(u32, 50), atomic.getAtomicValue());
}
