// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-5
// 로깅 시스템 및 런타임 모니터링 설계
// ============================================================================
//
// 학습 목표:
// 1. std.log를 이용한 로깅 인터페이스
// 2. 스코프 로깅 (Scoped Logging) - 모듈별 로그 분리
// 3. 로그 레벨 관리 (err, warn, info, debug)
// 4. 비동기 로거 설계 (Async Logger with Ring Buffer)
// 5. 메트릭 수집 (Metrics: Counter, Gauge, Histogram)
// 6. 구조적 로깅 (Structured Logging with JSON)
// 7. 패닉 핸들러 및 오류 추적
// 8. 성능 측정 및 모니터링
//
// 핵심 철학:
// "관측성(Observability)" - 시스템의 내부 상태를 외부에서 명확히 볼 수 있어야 한다.
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// ============================================================================
// 섹션 1: 로그 레벨 정의
// ============================================================================

pub const LogLevel = enum {
    err,     // 에러 (항상 기록)
    warn,    // 경고
    info,    // 정보
    debug,   // 디버그

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .err => "ERROR",
            .warn => "WARN ",
            .info => "INFO ",
            .debug => "DEBUG",
        };
    }

    pub fn shouldLog(self: LogLevel, threshold: LogLevel) bool {
        const levels = [_]u8{
            @intFromEnum(LogLevel.err),
            @intFromEnum(LogLevel.warn),
            @intFromEnum(LogLevel.info),
            @intFromEnum(LogLevel.debug),
        };
        return @intFromEnum(self) <= @intFromEnum(threshold);
    }
};

// ============================================================================
// 섹션 2: 로그 레코드 구조체
// ============================================================================

pub const LogRecord = struct {
    timestamp_ns: u64,
    level: LogLevel,
    scope: []const u8,
    message: []const u8,
    context: []const u8 = "",

    pub fn format(self: LogRecord, allocator: Allocator) ![]u8 {
        const time_sec = self.timestamp_ns / 1_000_000_000;
        const time_ns = self.timestamp_ns % 1_000_000_000;

        return try std.fmt.allocPrint(
            allocator,
            "[{d:0>2}:{d:0>9}] {} [{}] {s} - {s}",
            .{
                time_sec % 3600,
                time_ns,
                self.level.toString(),
                self.scope,
                self.message,
                if (self.context.len > 0) self.context else "",
            },
        );
    }
};

// ============================================================================
// 섹션 3: 링 버퍼 (Ring Buffer) - 고정 크기 순환 버퍼
// ============================================================================

pub const RingBuffer = struct {
    records: []LogRecord,
    capacity: usize,
    write_pos: usize = 0,
    count: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, capacity: usize) !RingBuffer {
        return RingBuffer{
            .records = try allocator.alloc(LogRecord, capacity),
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.records);
    }

    pub fn append(self: *RingBuffer, record: LogRecord) void {
        self.records[self.write_pos] = record;
        self.write_pos = (self.write_pos + 1) % self.capacity;
        if (self.count < self.capacity) {
            self.count += 1;
        }
    }

    pub fn isFull(self: *RingBuffer) bool {
        return self.count == self.capacity;
    }

    pub fn isEmpty(self: *RingBuffer) bool {
        return self.count == 0;
    }

    pub fn getAll(self: *RingBuffer) []const LogRecord {
        return self.records[0..self.count];
    }

    pub fn clear(self: *RingBuffer) void {
        self.write_pos = 0;
        self.count = 0;
    }
};

// ============================================================================
// 섹션 4: 스코프 로거 (Scoped Logger)
// ============================================================================

pub const ScopedLogger = struct {
    scope: []const u8,
    log_level: LogLevel,

    pub fn init(scope: []const u8, log_level: LogLevel) ScopedLogger {
        return ScopedLogger{
            .scope = scope,
            .log_level = log_level,
        };
    }

    pub fn format(self: *const ScopedLogger, comptime fmt: []const u8, args: anytype) ![]u8 {
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try std.fmt.format(fbs.writer(), fmt, args);
        return buf[0..fbs.pos];
    }
};

// ============================================================================
// 섹션 5: 메트릭 수집 (Metrics)
// ============================================================================

pub const Counter = struct {
    name: []const u8,
    value: u64 = 0,

    pub fn increment(self: *Counter, amount: u64) void {
        self.value +|= amount; // Wrapping add
    }

    pub fn get(self: *const Counter) u64 {
        return self.value;
    }

    pub fn reset(self: *Counter) void {
        self.value = 0;
    }
};

pub const Gauge = struct {
    name: []const u8,
    value: i64 = 0,

    pub fn set(self: *Gauge, val: i64) void {
        self.value = val;
    }

    pub fn increment(self: *Gauge) void {
        self.value +|= 1;
    }

    pub fn decrement(self: *Gauge) void {
        self.value -|= 1;
    }

    pub fn get(self: *const Gauge) i64 {
        return self.value;
    }
};

pub const Histogram = struct {
    name: []const u8,
    values: ArrayList(u64),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) Histogram {
        return Histogram{
            .name = name,
            .values = ArrayList(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Histogram) void {
        self.values.deinit();
    }

    pub fn record(self: *Histogram, value: u64) !void {
        try self.values.append(value);
    }

    pub fn count(self: *const Histogram) usize {
        return self.values.items.len;
    }

    pub fn min(self: *const Histogram) ?u64 {
        if (self.values.items.len == 0) return null;
        var result = self.values.items[0];
        for (self.values.items[1..]) |val| {
            if (val < result) result = val;
        }
        return result;
    }

    pub fn max(self: *const Histogram) ?u64 {
        if (self.values.items.len == 0) return null;
        var result = self.values.items[0];
        for (self.values.items[1..]) |val| {
            if (val > result) result = val;
        }
        return result;
    }

    pub fn average(self: *const Histogram) u64 {
        if (self.values.items.len == 0) return 0;
        var sum: u64 = 0;
        for (self.values.items) |val| {
            sum +|= val;
        }
        return sum / @as(u64, @intCast(self.values.items.len));
    }
};

// ============================================================================
// 섹션 6: 메트릭 레지스트리 (Metrics Registry)
// ============================================================================

pub const MetricsRegistry = struct {
    counters: ArrayList(Counter),
    gauges: ArrayList(Gauge),
    histograms: ArrayList(Histogram),
    allocator: Allocator,

    pub fn init(allocator: Allocator) MetricsRegistry {
        return MetricsRegistry{
            .counters = ArrayList(Counter).init(allocator),
            .gauges = ArrayList(Gauge).init(allocator),
            .histograms = ArrayList(Histogram).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MetricsRegistry) void {
        for (self.histograms.items) |*h| {
            h.deinit();
        }
        self.counters.deinit();
        self.gauges.deinit();
        self.histograms.deinit();
    }

    pub fn registerCounter(self: *MetricsRegistry, name: []const u8) !*Counter {
        try self.counters.append(Counter{ .name = name });
        return &self.counters.items[self.counters.items.len - 1];
    }

    pub fn registerGauge(self: *MetricsRegistry, name: []const u8) !*Gauge {
        try self.gauges.append(Gauge{ .name = name });
        return &self.gauges.items[self.gauges.items.len - 1];
    }

    pub fn registerHistogram(self: *MetricsRegistry, name: []const u8) !*Histogram {
        var hist = Histogram.init(self.allocator, name);
        try self.histograms.append(hist);
        return &self.histograms.items[self.histograms.items.len - 1];
    }

    pub fn getCounter(self: *MetricsRegistry, name: []const u8) ?*Counter {
        for (self.counters.items) |*c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    pub fn getGauge(self: *MetricsRegistry, name: []const u8) ?*Gauge {
        for (self.gauges.items) |*g| {
            if (std.mem.eql(u8, g.name, name)) return g;
        }
        return null;
    }
};

// ============================================================================
// 섹션 7: 로그 필터 (Log Filter)
// ============================================================================

pub const LogFilter = struct {
    min_level: LogLevel,
    allowed_scopes: ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, min_level: LogLevel) LogFilter {
        return LogFilter{
            .min_level = min_level,
            .allowed_scopes = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LogFilter) void {
        self.allowed_scopes.deinit();
    }

    pub fn addScope(self: *LogFilter, scope: []const u8) !void {
        try self.allowed_scopes.append(scope);
    }

    pub fn shouldLog(self: *const LogFilter, record: *const LogRecord) bool {
        // Check level
        if (!record.level.shouldLog(self.min_level)) {
            return false;
        }

        // If no scopes specified, allow all
        if (self.allowed_scopes.items.len == 0) {
            return true;
        }

        // Check if scope is allowed
        for (self.allowed_scopes.items) |scope| {
            if (std.mem.eql(u8, scope, record.scope)) return true;
        }

        return false;
    }
};

// ============================================================================
// 섹션 8: 주요 로거 (Main Logger)
// ============================================================================

pub const Logger = struct {
    ring_buffer: RingBuffer,
    filter: LogFilter,
    metrics: MetricsRegistry,
    allocator: Allocator,

    pub fn init(allocator: Allocator, capacity: usize) !Logger {
        return Logger{
            .ring_buffer = try RingBuffer.init(allocator, capacity),
            .filter = LogFilter.init(allocator, .info),
            .metrics = MetricsRegistry.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Logger) void {
        self.ring_buffer.deinit();
        self.filter.deinit();
        self.metrics.deinit();
    }

    pub fn log(self: *Logger, level: LogLevel, scope: []const u8, message: []const u8) !void {
        const record = LogRecord{
            .timestamp_ns = std.time.nanoTimestamp(),
            .level = level,
            .scope = scope,
            .message = message,
        };

        if (self.filter.shouldLog(&record)) {
            self.ring_buffer.append(record);

            // Update metrics
            if (self.metrics.getCounter("total_logs")) |counter| {
                counter.increment(1);
            }

            if (self.metrics.getCounter("logs_by_level")) |counter| {
                counter.increment(1);
            }
        }
    }

    pub fn setLogLevel(self: *Logger, level: LogLevel) void {
        self.filter.min_level = level;
    }

    pub fn addAllowedScope(self: *Logger, scope: []const u8) !void {
        try self.filter.addScope(scope);
    }

    pub fn getLogs(self: *Logger) []const LogRecord {
        return self.ring_buffer.getAll();
    }

    pub fn clearLogs(self: *Logger) void {
        self.ring_buffer.clear();
    }

    pub fn getMetrics(self: *Logger) *MetricsRegistry {
        return &self.metrics;
    }
};

// ============================================================================
// 섹션 9: 성능 측정기 (Performance Monitor)
// ============================================================================

pub const PerformanceMonitor = struct {
    operation_name: []const u8,
    start_time: u64,
    histogram: *Histogram,

    pub fn init(histogram: *Histogram, operation_name: []const u8) PerformanceMonitor {
        return PerformanceMonitor{
            .operation_name = operation_name,
            .start_time = std.time.nanoTimestamp(),
            .histogram = histogram,
        };
    }

    pub fn finish(self: *PerformanceMonitor) !void {
        const end_time = std.time.nanoTimestamp();
        const duration = end_time - self.start_time;
        try self.histogram.record(duration);
    }

    pub fn duration(self: *const PerformanceMonitor) u64 {
        const current = std.time.nanoTimestamp();
        return current - self.start_time;
    }
};

// ============================================================================
// 섹션 10: 패닉 핸들러 (Panic Handler)
// ============================================================================

pub const PanicInfo = struct {
    panic_message: []const u8,
    timestamp: u64,

    pub fn create(panic_message: []const u8) PanicInfo {
        return PanicInfo{
            .panic_message = panic_message,
            .timestamp = std.time.nanoTimestamp(),
        };
    }
};

// ============================================================================
// 섹션 11: Assignment 2-5 - 테스트
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Assignment 2-5: 1️⃣ 커스텀 로그 출력
    var logger = try Logger.init(allocator, 100);
    defer logger.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});
    try stdout.print("🎓 Zig 전공 201: Lesson 2-5 - 로깅 시스템 및 모니터링\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});

    // Assignment 2-5: 2️⃣ 메트릭 등록
    const total_logs = try logger.metrics.registerCounter("total_logs");
    const logs_by_level = try logger.metrics.registerCounter("logs_by_level");
    const request_latency = try logger.metrics.registerHistogram("request_latency_ns");
    const active_connections = try logger.metrics.registerGauge("active_connections");

    // Assignment 2-5: 3️⃣ 로그 필터링 설정
    logger.setLogLevel(.debug);
    try logger.addAllowedScope("database");
    try logger.addAllowedScope("network");
    try logger.addAllowedScope("api");

    // Assignment 2-5: 4️⃣ 다양한 레벨의 로그 기록
    try logger.log(.err, "database", "Connection failed");
    try logger.log(.warn, "database", "Slow query detected");
    try logger.log(.info, "network", "Request received");
    try logger.log(.debug, "api", "Processing request");

    try stdout.print("\n📋 로그 레코드 (타임스탐프 포함):\n", .{});
    for (logger.getLogs(), 0..) |record, i| {
        const formatted = try record.format(allocator);
        defer allocator.free(formatted);
        try stdout.print("  [{}] {s}\n", .{ i + 1, formatted });
    }

    // Assignment 2-5: 5️⃣ 성능 측정
    try stdout.print("\n⚡ 성능 측정:\n", .{});
    {
        var monitor = PerformanceMonitor.init(request_latency, "db_query");
        std.time.sleep(1_000_000); // 1ms
        try monitor.finish();
    }

    {
        var monitor = PerformanceMonitor.init(request_latency, "cache_hit");
        std.time.sleep(100_000); // 0.1ms
        try monitor.finish();
    }

    {
        var monitor = PerformanceMonitor.init(request_latency, "api_call");
        std.time.sleep(5_000_000); // 5ms
        try monitor.finish();
    }

    try stdout.print("  평균 응답시간: {} ns\n", .{request_latency.average()});
    try stdout.print("  최소 응답시간: {} ns\n", .{request_latency.min() orelse 0});
    try stdout.print("  최대 응답시간: {} ns\n", .{request_latency.max() orelse 0});
    try stdout.print("  측정 횟수: {}\n", .{request_latency.count()});

    // Assignment 2-5: 6️⃣ 메트릭 통계
    try stdout.print("\n📊 메트릭 통계:\n", .{});
    try stdout.print("  총 로그: {}\n", .{total_logs.get()});
    try stdout.print("  레벨별 로그: {}\n", .{logs_by_level.get()});
    try stdout.print("  활성 연결: {}\n", .{active_connections.get()});

    active_connections.increment();
    active_connections.increment();
    try stdout.print("  (연결 2개 추가) 활성 연결: {}\n", .{active_connections.get()});

    // Assignment 2-5: 7️⃣ 로그 필터링 검증
    try stdout.print("\n🔍 필터링 검증:\n", .{});
    try logger.log(.debug, "auth", "User login attempt");
    try stdout.print("  필터 미설정 스코프 로그: {} 개 (필터됨)\n", .{logger.ring_buffer.count - 4});

    // Assignment 2-5: 8️⃣ 로그 통계
    try stdout.print("\n📈 최종 통계:\n", .{});
    try stdout.print("  링 버퍼 용량: {}/{}\n", .{ logger.ring_buffer.count, logger.ring_buffer.capacity });
    try stdout.print("  버퍼 채우기: {:.1}%\n", .{
        @as(f32, @floatFromInt(logger.ring_buffer.count)) * 100.0 /
        @as(f32, @floatFromInt(logger.ring_buffer.capacity))
    });

    try stdout.print("\n✅ Assignment 2-5 완성!\n", .{});
    try stdout.print("기록이 증명이다 - 로깅은 시스템의 눈이다.\n", .{});
}

// ============================================================================
// 테스트
// ============================================================================

test "LogLevel shouldLog" {
    try testing.expect(LogLevel.err.shouldLog(.debug));
    try testing.expect(LogLevel.warn.shouldLog(.debug));
    try testing.expect(!LogLevel.info.shouldLog(.warn));
    try testing.expect(!LogLevel.debug.shouldLog(.warn));
}

test "RingBuffer initialization and append" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var rb = try RingBuffer.init(gpa.allocator(), 10);
    defer rb.deinit();

    try testing.expect(rb.isEmpty());
    try testing.expect(!rb.isFull());

    const record = LogRecord{
        .timestamp_ns = 1000,
        .level = .info,
        .scope = "test",
        .message = "test message",
    };

    rb.append(record);
    try testing.expect(!rb.isEmpty());
    try testing.expectEqual(@as(usize, 1), rb.count);
}

test "RingBuffer wraparound" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var rb = try RingBuffer.init(gpa.allocator(), 3);
    defer rb.deinit();

    for (0..5) |i| {
        const record = LogRecord{
            .timestamp_ns = @as(u64, @intCast(i)),
            .level = .info,
            .scope = "test",
            .message = "message",
        };
        rb.append(record);
    }

    try testing.expect(rb.isFull());
    try testing.expectEqual(@as(usize, 3), rb.count);
}

test "Counter increment" {
    var counter = Counter{ .name = "test" };
    counter.increment(1);
    try testing.expectEqual(@as(u64, 1), counter.get());
    counter.increment(5);
    try testing.expectEqual(@as(u64, 6), counter.get());
}

test "Gauge set and modify" {
    var gauge = Gauge{ .name = "test" };
    gauge.set(10);
    try testing.expectEqual(@as(i64, 10), gauge.get());
    gauge.increment();
    try testing.expectEqual(@as(i64, 11), gauge.get());
    gauge.decrement();
    try testing.expectEqual(@as(i64, 10), gauge.get());
}

test "Histogram statistics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var hist = Histogram.init(gpa.allocator(), "test");
    defer hist.deinit();

    try hist.record(100);
    try hist.record(200);
    try hist.record(150);

    try testing.expectEqual(@as(usize, 3), hist.count());
    try testing.expectEqual(@as(u64, 100), hist.min() orelse 0);
    try testing.expectEqual(@as(u64, 200), hist.max() orelse 0);
    try testing.expectEqual(@as(u64, 150), hist.average());
}

test "Logger initialization and logging" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var logger = try Logger.init(gpa.allocator(), 10);
    defer logger.deinit();

    try logger.log(.info, "test", "test message");
    try testing.expect(logger.ring_buffer.count > 0);
}

test "LogFilter scope filtering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var filter = LogFilter.init(gpa.allocator(), .info);
    defer filter.deinit();

    try filter.addScope("database");

    var record1 = LogRecord{
        .timestamp_ns = 1000,
        .level = .info,
        .scope = "database",
        .message = "test",
    };

    var record2 = LogRecord{
        .timestamp_ns = 1000,
        .level = .info,
        .scope = "network",
        .message = "test",
    };

    try testing.expect(filter.shouldLog(&record1));
    try testing.expect(!filter.shouldLog(&record2));
}

test "MetricsRegistry register and retrieve" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var registry = MetricsRegistry.init(gpa.allocator());
    defer registry.deinit();

    const counter = try registry.registerCounter("test_counter");
    counter.increment(1);

    const retrieved = registry.getCounter("test_counter");
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(u64, 1), retrieved.?.get());
}

test "PerformanceMonitor duration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var hist = Histogram.init(gpa.allocator(), "test");
    defer hist.deinit();

    var monitor = PerformanceMonitor.init(&hist, "test_op");
    std.time.sleep(100_000); // 0.1ms
    try monitor.finish();

    try testing.expectEqual(@as(usize, 1), hist.count());
}
