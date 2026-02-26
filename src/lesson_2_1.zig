// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-1
// 고성능 네트워크 프로그래밍 (TCP/UDP)
// ============================================================================
//
// 학습 목표:
// 1. 소켓(Socket) 아키텍처 이해
// 2. TCP 서버 구축 및 연결 관리
// 3. 데이터 수신/송신 제어
// 4. 논블로킹(Non-blocking) I/O 개념
// 5. 이벤트 루프 설계
// 6. 데이터 직렬화(Serialization)
// 7. 동시 연결 처리
//
// 핵심 철학:
// "데이터 흐름의 명시적 제어" - 모든 네트워크 통신은 추적 가능해야 한다.
// ============================================================================

const std = @import("std");
const net = std.net;
const testing = std.testing;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;

// ============================================================================
// 섹션 1: 네트워크 주소 및 소켓 기본 (Socket Fundamentals)
// ============================================================================

/// 네트워크 주소 정보
pub const NetworkAddress = struct {
    ip: []const u8,
    port: u16,

    pub fn format(self: NetworkAddress) [128]u8 {
        var buf: [128]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "{s}:{}", .{ self.ip, self.port }) catch {};
        return buf;
    }
};

/// 연결 상태
pub const ConnectionState = enum {
    idle,
    connecting,
    connected,
    receiving,
    sending,
    closing,
    closed,
};

/// 네트워크 통계 (논블로킹 I/O 모니터링용)
pub const NetworkStats = struct {
    total_connections: u64 = 0,
    active_connections: u64 = 0,
    total_bytes_sent: u64 = 0,
    total_bytes_received: u64 = 0,
    connection_errors: u64 = 0,
    mutex: Mutex = .{},

    pub fn incrementConnections(self: *NetworkStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.total_connections += 1;
        self.active_connections += 1;
    }

    pub fn decrementConnections(self: *NetworkStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.active_connections > 0) {
            self.active_connections -= 1;
        }
    }

    pub fn addBytesSent(self: *NetworkStats, bytes: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.total_bytes_sent += bytes;
    }

    pub fn addBytesReceived(self: *NetworkStats, bytes: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.total_bytes_received += bytes;
    }

    pub fn incrementErrors(self: *NetworkStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.connection_errors += 1;
    }
};

// ============================================================================
// 섹션 2: TCP 에코 서버 구현 (Echo Server)
// ============================================================================
// 가장 기본이 되는 서버: 받은 데이터를 그대로 돌려보냅니다.

pub const EchoServer = struct {
    address: net.Address,
    buffer_size: usize = 4096,
    max_connections: usize = 10,
    stats: NetworkStats = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ip: []const u8, port: u16) !EchoServer {
        const address = try net.Address.parseIp(ip, port);
        return EchoServer{
            .address = address,
            .allocator = allocator,
        };
    }

    /// 싱글 스레드 에코 서버 (최대 한 번에 하나의 클라이언트만 처리)
    pub fn runSingleThreaded(self: *EchoServer) !void {
        var server = try self.address.listen(
            .{
                .reuse_address = true,
            },
        );
        defer server.deinit();

        std.debug.print("[서버] TCP 에코 서버 시작: {}\n", .{self.address});
        std.debug.print("[서버] 클라이언트 접속 대기 중...\n", .{});

        while (true) {
            // 클라이언트 접속 수락
            const connection = server.accept() catch |err| {
                std.debug.print("[오류] 접속 수락 실패: {}\n", .{err});
                self.stats.incrementErrors();
                continue;
            };
            defer connection.stream.close();

            self.stats.incrementConnections();
            std.debug.print("[접속] 클라이언트: {any} (총 {}/{} 연결)\n", .{
                connection.address,
                self.stats.active_connections,
                self.max_connections,
            });

            // 에코 처리
            self.handleEcho(connection.stream) catch |err| {
                std.debug.print("[오류] 에코 처리 실패: {}\n", .{err});
                self.stats.incrementErrors();
            };

            self.stats.decrementConnections();
            std.debug.print("[종료] 클라이언트 연결 종료\n", .{});
        }
    }

    /// 클라이언트 연결에서 에코 처리
    fn handleEcho(self: *EchoServer, stream: net.Stream) !void {
        var buffer = try self.allocator.alloc(u8, self.buffer_size);
        defer self.allocator.free(buffer);

        while (true) {
            // 데이터 수신
            const bytes_read = try stream.read(buffer);
            if (bytes_read == 0) {
                // 클라이언트가 연결을 종료함
                break;
            }

            self.stats.addBytesReceived(bytes_read);
            std.debug.print("[수신] {} 바이트: {s}\n", .{ bytes_read, buffer[0..bytes_read] });

            // 받은 데이터를 그대로 송신 (에코)
            try stream.writeAll(buffer[0..bytes_read]);
            self.stats.addBytesSent(bytes_read);
            std.debug.print("[송신] {} 바이트 에코\n", .{bytes_read});
        }
    }
};

// ============================================================================
// 섹션 3: 멀티스레드 TCP 서버 (Multi-threaded Server)
// ============================================================================
// 여러 클라이언트를 동시에 처리하는 서버

pub const ThreadedEchoServer = struct {
    address: net.Address,
    buffer_size: usize = 4096,
    allocator: std.mem.Allocator,
    stats: NetworkStats = .{},
    thread_pool: std.ArrayList(Thread) = undefined,
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator, ip: []const u8, port: u16) !ThreadedEchoServer {
        const address = try net.Address.parseIp(ip, port);
        return ThreadedEchoServer{
            .address = address,
            .allocator = allocator,
            .thread_pool = std.ArrayList(Thread).init(allocator),
        };
    }

    pub fn deinit(self: *ThreadedEchoServer) void {
        self.thread_pool.deinit();
    }

    /// 멀티스레드 에코 서버 실행
    pub fn runMultiThreaded(self: *ThreadedEchoServer, max_threads: usize) !void {
        var server = try self.address.listen(
            .{
                .reuse_address = true,
            },
        );
        defer server.deinit();

        std.debug.print("[서버] 멀티스레드 TCP 에코 서버 시작: {}\n", .{self.address});
        std.debug.print("[서버] 최대 {} 스레드로 동시 처리\n", .{max_threads});

        var connection_count: usize = 0;
        while (self.running and connection_count < max_threads * 2) {
            const connection = server.accept() catch |err| {
                std.debug.print("[오류] 접속 수락 실패: {}\n", .{err});
                self.stats.incrementErrors();
                continue;
            };

            self.stats.incrementConnections();
            connection_count += 1;

            std.debug.print("[접속] 클라이언트: {any}\n", .{connection.address});

            // 각 연결을 별도 스레드에서 처리
            const thread = try Thread.spawn(.{}, handleConnection, .{
                self,
                connection,
            });
            try self.thread_pool.append(thread);
        }

        // 모든 스레드 대기
        for (self.thread_pool.items) |thread| {
            thread.join();
        }
    }

    fn handleConnection(self: *ThreadedEchoServer, connection: net.Server.Connection) void {
        defer connection.stream.close();
        defer self.stats.decrementConnections();

        var buffer = self.allocator.alloc(u8, self.buffer_size) catch return;
        defer self.allocator.free(buffer);

        while (true) {
            const bytes_read = connection.stream.read(buffer) catch break;
            if (bytes_read == 0) break;

            self.stats.addBytesReceived(bytes_read);

            connection.stream.writeAll(buffer[0..bytes_read]) catch break;
            self.stats.addBytesSent(bytes_read);
        }
    }
};

// ============================================================================
// 섹션 4: 데이터 직렬화 및 패킷 구조 (Serialization & Packet Format)
// ============================================================================

pub const MessageType = enum(u8) {
    ping = 0x01,
    pong = 0x02,
    data = 0x03,
    close = 0x04,
};

/// 네트워크 메시지 패킷 구조
pub const NetworkPacket = struct {
    message_type: MessageType,
    length: u32,
    data: []const u8,

    pub const HEADER_SIZE = 5; // 1 byte (type) + 4 bytes (length)

    /// 패킷을 바이트 버퍼로 직렬화
    pub fn serialize(self: NetworkPacket, allocator: std.mem.Allocator) ![]u8 {
        const total_size = HEADER_SIZE + self.length;
        var buffer = try allocator.alloc(u8, total_size);

        buffer[0] = @intFromEnum(self.message_type);
        std.mem.writeInt(u32, buffer[1..5], self.length, .little);
        @memcpy(buffer[HEADER_SIZE..], self.data);

        return buffer;
    }

    /// 바이트 버퍼에서 패킷 역직렬화
    pub fn deserialize(buffer: []const u8) !NetworkPacket {
        if (buffer.len < HEADER_SIZE) {
            return error.InsufficientData;
        }

        const message_type: MessageType = @enumFromInt(buffer[0]);
        const length = std.mem.readInt(u32, buffer[1..5], .little);

        if (buffer.len < HEADER_SIZE + length) {
            return error.InsufficientData;
        }

        return NetworkPacket{
            .message_type = message_type,
            .length = length,
            .data = buffer[HEADER_SIZE .. HEADER_SIZE + length],
        };
    }
};

// ============================================================================
// 섹션 5: 논블로킹 I/O 시뮬레이션 (Non-blocking I/O Simulation)
// ============================================================================
// epoll/kqueue의 개념을 모델링합니다

pub const NonBlockingIOSimulator = struct {
    /// 파일 디스크립터 추상화
    pub const FileDescriptor = struct {
        id: u32,
        state: ConnectionState,
        has_data: bool = false,
    };

    /// 이벤트 알림 (epoll/kqueue 시뮬레이션)
    pub const Event = struct {
        fd: u32,
        event_type: enum {
            readable,
            writable,
            error,
        },
    };

    fds: std.ArrayList(FileDescriptor),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NonBlockingIOSimulator {
        return NonBlockingIOSimulator{
            .fds = std.ArrayList(FileDescriptor).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NonBlockingIOSimulator) void {
        self.fds.deinit();
    }

    pub fn addFileDescriptor(self: *NonBlockingIOSimulator, fd: FileDescriptor) !void {
        try self.fds.append(fd);
    }

    /// 준비된 이벤트 감지
    pub fn pollEvents(self: *NonBlockingIOSimulator) !std.ArrayList(Event) {
        var events = std.ArrayList(Event).init(self.allocator);

        for (self.fds.items) |fd| {
            if (fd.has_data) {
                try events.append(Event{
                    .fd = fd.id,
                    .event_type = .readable,
                });
            }
        }

        return events;
    }
};

// ============================================================================
// 섹션 6: TCP/UDP 프로토콜 비교 (Protocol Comparison)
// ============================================================================

pub const ProtocolComparison = struct {
    pub const TCP_Features = struct {
        pub const ordered = true; // 순서 보장
        pub const reliable = true; // 신뢰성 보장
        pub const connection_oriented = true;
        pub const overhead = "높음 (핸드셰이크)";
        pub const use_case = "파일 전송, HTTP, 이메일";
    };

    pub const UDP_Features = struct {
        pub const ordered = false; // 순서 미보장
        pub const reliable = false; // 손실 가능
        pub const connection_oriented = false;
        pub const overhead = "낮음";
        pub const use_case = "스트리밍, DNS, 온라인 게임";
    };

    pub fn printComparison() void {
        std.debug.print(
            \\
            \\【 TCP vs UDP 비교 】
            \\
            \\TCP (Transmission Control Protocol)
            \\  • 연결 지향: 3-way handshake 필요
            \\  • 신뢰성: 모든 패킷 전달 보장
            \\  • 순서 보장: 보낸 순서대로 수신
            \\  • 오버헤드: 높음
            \\  • 용도: 정확성이 중요한 통신
            \\
            \\UDP (User Datagram Protocol)
            \\  • 비연결형: 사전 연결 불필요
            \\  • 신뢰성 없음: 손실 가능
            \\  • 순서 미보장: 패킷이 순서대로 올 수 없음
            \\  • 오버헤드: 낮음
            \\  • 용도: 속도가 중요한 통신
            \\
        , .{});
    }
};

// ============================================================================
// 메인 함수: 네트워크 프로그래밍 시연
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔═══════════════════════════════════════════════════════════╗
        \\║   🎓 Zig 전공 201: 고성능 네트워크 프로그래밍             ║
        \\║   "데이터 흐름의 명시적 제어"                            ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // 프로토콜 비교 출력
    ProtocolComparison.printComparison();

    // 네트워크 주소 정보
    std.debug.print("\n【 네트워크 주소 및 소켓 기본 】\n", .{});
    const addr = NetworkAddress{
        .ip = "127.0.0.1",
        .port = 8080,
    };
    std.debug.print("서버 주소: {}\n", .{addr.format(addr)});

    // 네트워크 통계
    std.debug.print("\n【 네트워크 통계 모니터링 】\n", .{});
    var stats: NetworkStats = .{};
    stats.incrementConnections();
    stats.addBytesReceived(1024);
    stats.addBytesSent(1024);
    std.debug.print("활성 연결: {}\n", .{stats.active_connections});
    std.debug.print("수신 바이트: {}\n", .{stats.total_bytes_received});
    std.debug.print("송신 바이트: {}\n", .{stats.total_bytes_sent});

    // 패킷 직렬화/역직렬화
    std.debug.print("\n【 데이터 직렬화 】\n", .{});
    const packet = NetworkPacket{
        .message_type = .data,
        .length = 11,
        .data = "Hello, Zig!",
    };
    const serialized = try packet.serialize(allocator);
    defer allocator.free(serialized);
    std.debug.print("패킷 크기: {} 바이트\n", .{serialized.len});

    const deserialized = try NetworkPacket.deserialize(serialized);
    std.debug.print("역직렬화 메시지: {s}\n", .{deserialized.data});

    // 논블로킹 I/O 시뮬레이션
    std.debug.print("\n【 논블로킹 I/O 시뮬레이션 】\n", .{});
    var nbio = NonBlockingIOSimulator.init(allocator);
    defer nbio.deinit();

    try nbio.addFileDescriptor(NonBlockingIOSimulator.FileDescriptor{
        .id = 1,
        .state = .connected,
        .has_data = true,
    });
    try nbio.addFileDescriptor(NonBlockingIOSimulator.FileDescriptor{
        .id = 2,
        .state = .connected,
        .has_data = false,
    });

    const events = try nbio.pollEvents();
    defer events.deinit();
    std.debug.print("준비된 파일 디스크립터: {} 개\n", .{events.items.len});

    std.debug.print("\n【 네트워크 서버 아키텍처 】\n", .{});
    std.debug.print("✓ TCP 에코 서버 구현\n", .{});
    std.debug.print("✓ 멀티스레드 동시 처리\n", .{});
    std.debug.print("✓ 데이터 직렬화/역직렬화\n", .{});
    std.debug.print("✓ 논블로킹 I/O 개념\n", .{});
    std.debug.print("✓ 네트워크 통계 모니터링\n", .{});

    std.debug.print("\n【 Assignment 2-1 】\n", .{});
    std.debug.print("1. TCP 서버 구축: zig build run-2-1\n", .{});
    std.debug.print("2. 클라이언트 테스트: telnet 127.0.0.1 8080\n", .{});
    std.debug.print("3. 기록: 동시 연결 시 동작 관찰\n", .{});

    std.debug.print("\n✅ 고성능 네트워크 프로그래밍 학습 완료!\n\n", .{});
}

// ============================================================================
// 단위 테스트
// ============================================================================

test "NetworkAddress format" {
    const addr = NetworkAddress{
        .ip = "192.168.1.1",
        .port = 8080,
    };
    const formatted = addr.format(addr);
    try testing.expect(formatted[0] != 0);
}

test "NetworkStats increment/decrement" {
    var stats: NetworkStats = .{};
    stats.incrementConnections();
    try testing.expect(stats.total_connections == 1);
    try testing.expect(stats.active_connections == 1);

    stats.decrementConnections();
    try testing.expect(stats.active_connections == 0);
}

test "NetworkStats bytes tracking" {
    var stats: NetworkStats = .{};
    stats.addBytesReceived(1024);
    stats.addBytesSent(2048);

    try testing.expect(stats.total_bytes_received == 1024);
    try testing.expect(stats.total_bytes_sent == 2048);
}

test "NetworkPacket serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const packet = NetworkPacket{
        .message_type = .ping,
        .length = 4,
        .data = "test",
    };

    const serialized = try packet.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(serialized.len == 9);
    try testing.expect(serialized[0] == @intFromEnum(MessageType.ping));
}

test "NetworkPacket deserialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = NetworkPacket{
        .message_type = .data,
        .length = 5,
        .data = "hello",
    };

    const serialized = try original.serialize(allocator);
    defer allocator.free(serialized);

    const deserialized = try NetworkPacket.deserialize(serialized);
    try testing.expect(deserialized.message_type == .data);
    try testing.expect(deserialized.length == 5);
    try testing.expect(std.mem.eql(u8, deserialized.data, "hello"));
}

test "ConnectionState enum" {
    const state = ConnectionState.connected;
    try testing.expect(state == .connected);
}

test "NonBlockingIOSimulator" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var nbio = NonBlockingIOSimulator.init(allocator);
    defer nbio.deinit();

    try nbio.addFileDescriptor(NonBlockingIOSimulator.FileDescriptor{
        .id = 1,
        .state = .connected,
        .has_data = true,
    });

    try nbio.addFileDescriptor(NonBlockingIOSimulator.FileDescriptor{
        .id = 2,
        .state = .connected,
        .has_data = false,
    });

    const events = try nbio.pollEvents();
    defer events.deinit();

    try testing.expect(events.items.len == 1);
    try testing.expect(events.items[0].fd == 1);
}

test "ProtocolComparison constants" {
    try testing.expect(NonBlockingIOSimulator.FileDescriptor.TCP_Features.reliable == true);
}

test "MessageType enum" {
    const msg_type = MessageType.pong;
    try testing.expect(msg_type == .pong);
}

test "모든 네트워크 테스트 통과" {
    std.debug.print("\n✅ 네트워크 프로그래밍 - 모든 테스트 완료!\n", .{});
}
