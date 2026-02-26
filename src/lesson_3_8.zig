// ============================================================================
// Lesson 3-8: 최종 프로젝트 - 마이크로커널 아키텍처 완성
// ============================================================================
//
// 핵심 개념:
// - IPC (Inter-Process Communication): 메시지 패싱 기반 프로세스 통신
// - 마이크로커널 vs 모놀리식: 최소화된 커널, 유저 서비스 중심
// - 서비스 서버: VFS, Window Server, Network Stack
// - 부팅 시퀀스: PMM → GDT/IDT → 드라이버 → init
// - 안정성: 서비스 크래시 감지 및 자동 재시작
// - 배포: ISO 이미지 생성
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// IPC (Inter-Process Communication) - 메시지 기반 통신
// ============================================================================

/// 메시지 타입
pub const MessageType = enum(u8) {
    Request = 0,   // 요청 메시지
    Response = 1,  // 응답 메시지
    Event = 2,     // 이벤트
    Control = 3,   // 제어 메시지
};

/// IPC 메시지
pub const Message = struct {
    /// 메시지 ID
    id: u64 = 0,
    /// 송신자 PID
    from_pid: u32 = 0,
    /// 수신자 PID
    to_pid: u32 = 0,
    /// 메시지 타입
    msg_type: MessageType = .Request,
    /// 메시지 코드 (요청 종류)
    code: u32 = 0,
    /// 메시지 데이터 (최대 256 바이트)
    data: [256]u8 = [_]u8{0} ** 256,
    /// 데이터 길이
    data_len: u16 = 0,
    /// 반환값/상태
    result: i32 = 0,

    pub fn new(from: u32, to: u32, code: u32) Message {
        return Message{
            .from_pid = from,
            .to_pid = to,
            .code = code,
        };
    }

    pub fn withData(msg: Message, data: []const u8) Message {
        var new_msg = msg;
        if (data.len <= 256) {
            @memcpy(new_msg.data[0..data.len], data);
            new_msg.data_len = @intCast(data.len);
        }
        return new_msg;
    }
};

/// IPC 포트 (메시지 큐)
pub const MessagePort = struct {
    /// 포트 ID
    id: u32,
    /// 포함 프로세스 PID
    owner_pid: u32,
    /// 메시지 큐 (최대 32개)
    messages: [32]?Message = [_]?Message{null} ** 32,
    /// 큐 헤드
    head: u32 = 0,
    /// 큐 테일
    tail: u32 = 0,
    /// 메시지 수
    count: u32 = 0,

    /// 메시지 전송 (동기식: 응답 대기)
    pub fn sendSync(
        self: *MessagePort,
        msg: Message,
    ) bool {
        if (self.count >= 32) return false;

        self.messages[self.tail] = msg;
        self.tail = (self.tail + 1) % 32;
        self.count += 1;
        return true;
    }

    /// 메시지 수신
    pub fn receive(self: *MessagePort) ?Message {
        if (self.count == 0) return null;

        const msg = self.messages[self.head];
        self.messages[self.head] = null;
        self.head = (self.head + 1) % 32;
        self.count -|= 1;
        return msg;
    }

    /// 메시지 응답
    pub fn reply(self: *MessagePort, reply_msg: Message) bool {
        return self.sendSync(reply_msg);
    }
};

/// IPC 라우터 (메시지 라우팅)
pub const IPCRouter = struct {
    /// 포트 맵 (PID → Port)
    ports: [128]?MessagePort = [_]?MessagePort{null} ** 128,
    /// 포트 수
    port_count: u32 = 0,

    /// 프로세스를 위한 포트 생성
    pub fn createPort(self: *IPCRouter, pid: u32) ?u32 {
        if (self.port_count >= 128) return null;

        const port_id = self.port_count;
        self.ports[port_id] = MessagePort{
            .id = port_id,
            .owner_pid = pid,
        };
        self.port_count += 1;
        return port_id;
    }

    /// 메시지 라우팅
    pub fn routeMessage(
        self: *IPCRouter,
        msg: Message,
    ) bool {
        for (0..self.port_count) |i| {
            if (self.ports[i]) |*port| {
                if (port.owner_pid == msg.to_pid) {
                    return port.sendSync(msg);
                }
            }
        }
        return false;
    }

    /// 메시지 수신
    pub fn receiveMessage(self: *IPCRouter, pid: u32) ?Message {
        for (0..self.port_count) |i| {
            if (self.ports[i]) |*port| {
                if (port.owner_pid == pid) {
                    return port.receive();
                }
            }
        }
        return null;
    }
};

// ============================================================================
// 서비스 서버 (Service Servers)
// ============================================================================

/// 서비스 종류
pub const ServiceType = enum(u8) {
    FileSystem = 0,   // VFS Server
    Display = 1,      // Window Server
    Network = 2,      // Network Stack
    Terminal = 3,     // Terminal Server
    Init = 4,         // Init Server
};

/// 서비스 서버
pub const Service = struct {
    /// 서비스 이름
    name: [64]u8,
    name_len: u8,
    /// 서비스 타입
    service_type: ServiceType,
    /// 서비스 PID
    pid: u32,
    /// 서비스 상태 (0=Stopped, 1=Running, 2=Crashed)
    state: u8,
    /// 크래시 횟수
    crash_count: u32,
    /// 최대 재시작 횟수
    max_restarts: u32 = 5,

    pub fn new(
        name: []const u8,
        svc_type: ServiceType,
        pid: u32,
    ) Service {
        var service: Service = undefined;
        if (name.len < 64) {
            @memcpy(service.name[0..name.len], name);
            service.name_len = @intCast(name.len);
        }
        service.service_type = svc_type;
        service.pid = pid;
        service.state = 1; // Running
        service.crash_count = 0;
        return service;
    }

    pub fn getName(self: Service) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn isCrashed(self: Service) bool {
        return self.state == 2;
    }

    pub fn isRunning(self: Service) bool {
        return self.state == 1;
    }
};

/// 서비스 레지스트리
pub const ServiceRegistry = struct {
    /// 서비스 목록 (최대 16개)
    services: [16]?Service = [_]?Service{null} ** 16,
    /// 서비스 수
    count: u32 = 0,

    /// 서비스 등록
    pub fn register(self: *ServiceRegistry, service: Service) bool {
        if (self.count >= 16) return false;

        self.services[self.count] = service;
        self.count += 1;
        return true;
    }

    /// PID로 서비스 검색
    pub fn findByPid(self: ServiceRegistry, pid: u32) ?*Service {
        for (0..self.count) |i| {
            if (self.services[i]) |*svc| {
                if (svc.pid == pid) {
                    return svc;
                }
            }
        }
        return null;
    }

    /// 타입으로 서비스 검색
    pub fn findByType(self: ServiceRegistry, svc_type: ServiceType) ?*Service {
        for (0..self.count) |i| {
            if (self.services[i]) |*svc| {
                if (svc.service_type == svc_type) {
                    return svc;
                }
            }
        }
        return null;
    }

    /// 서비스 상태 변경
    pub fn setServiceState(self: *ServiceRegistry, pid: u32, state: u8) bool {
        if (self.findByPid(pid)) |svc| {
            svc.state = state;
            return true;
        }
        return false;
    }

    /// 서비스 크래시 기록
    pub fn recordCrash(self: *ServiceRegistry, pid: u32) bool {
        if (self.findByPid(pid)) |svc| {
            svc.crash_count += 1;
            if (svc.crash_count > svc.max_restarts) {
                svc.state = 2; // Crashed (계속 재시작 안 함)
            } else {
                svc.state = 1; // Restart
            }
            return svc.crash_count <= svc.max_restarts;
        }
        return false;
    }

    /// 모든 실행 중인 서비스 나열
    pub fn listRunningServices(self: ServiceRegistry) u32 {
        var running: u32 = 0;
        for (0..self.count) |i| {
            if (self.services[i]) |svc| {
                if (svc.isRunning()) running += 1;
            }
        }
        return running;
    }
};

// ============================================================================
// 부팅 시퀀스 (Boot Sequence)
// ============================================================================

pub const BootStage = enum(u8) {
    PowerOn = 0,       // 전원 인가
    PMM = 1,          // Physical Memory Manager
    Paging = 2,       // Virtual Memory (Paging)
    GDT = 3,          // Global Descriptor Table
    IDT = 4,          // Interrupt Descriptor Table
    TSS = 5,          // Task State Segment
    Drivers = 6,      // Device Drivers
    Init = 7,         // Init Process
    Ready = 8,        // System Ready
};

pub const BootSequence = struct {
    /// 현재 부팅 단계
    current_stage: BootStage = .PowerOn,
    /// 부팅 진행률 (0-100)
    progress: u8 = 0,
    /// 완료된 단계
    completed_stages: u32 = 0,

    /// 부팅 시뮬레이션
    pub fn simulate(self: *BootSequence) void {
        // Stage 1: PMM
        self.current_stage = .PMM;
        self.progress = 10;
        self.completed_stages += 1;

        // Stage 2: Paging
        self.current_stage = .Paging;
        self.progress = 25;
        self.completed_stages += 1;

        // Stage 3: GDT
        self.current_stage = .GDT;
        self.progress = 40;
        self.completed_stages += 1;

        // Stage 4: IDT
        self.current_stage = .IDT;
        self.progress = 55;
        self.completed_stages += 1;

        // Stage 5: TSS
        self.current_stage = .TSS;
        self.progress = 70;
        self.completed_stages += 1;

        // Stage 6: Drivers
        self.current_stage = .Drivers;
        self.progress = 85;
        self.completed_stages += 1;

        // Stage 7: Init
        self.current_stage = .Init;
        self.progress = 95;
        self.completed_stages += 1;

        // Stage 8: Ready
        self.current_stage = .Ready;
        self.progress = 100;
    }

    pub fn isReady(self: BootSequence) bool {
        return self.current_stage == .Ready;
    }
};

// ============================================================================
// 드라이버 관리 (Driver Manager)
// ============================================================================

pub const DriverType = enum(u8) {
    Timer = 0,      // PIT (Programmable Interval Timer)
    Keyboard = 1,   // PS/2 Keyboard
    Display = 2,    // VGA Display
    Disk = 3,       // Disk Controller
    Network = 4,    // Network Card
};

pub const Driver = struct {
    /// 드라이버 이름
    name: [64]u8,
    name_len: u8,
    /// 드라이버 타입
    driver_type: DriverType,
    /// 초기화 여부
    initialized: bool = false,
    /// IRQ 번호 (-1이면 없음)
    irq: i8 = -1,

    pub fn new(name: []const u8, dtype: DriverType) Driver {
        var driver: Driver = undefined;
        if (name.len < 64) {
            @memcpy(driver.name[0..name.len], name);
            driver.name_len = @intCast(name.len);
        }
        driver.driver_type = dtype;
        return driver;
    }

    pub fn getName(self: Driver) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const DriverManager = struct {
    /// 드라이버 목록 (최대 32개)
    drivers: [32]?Driver = [_]?Driver{null} ** 32,
    /// 드라이버 수
    count: u32 = 0,

    /// 드라이버 등록
    pub fn registerDriver(self: *DriverManager, driver: Driver) bool {
        if (self.count >= 32) return false;

        self.drivers[self.count] = driver;
        self.count += 1;
        return true;
    }

    /// 드라이버 초기화
    pub fn initializeDriver(self: *DriverManager, idx: u32) bool {
        if (idx >= self.count) return false;

        if (self.drivers[idx]) |*driver| {
            driver.initialized = true;
            return true;
        }
        return false;
    }

    /// 모든 드라이버 초기화
    pub fn initializeAll(self: *DriverManager) u32 {
        var initialized: u32 = 0;
        for (0..self.count) |i| {
            if (self.initializeDriver(@intCast(i))) {
                initialized += 1;
            }
        }
        return initialized;
    }

    /// 초기화된 드라이버 수
    pub fn getInitializedCount(self: DriverManager) u32 {
        var count: u32 = 0;
        for (0..self.count) |i| {
            if (self.drivers[i]) |driver| {
                if (driver.initialized) count += 1;
            }
        }
        return count;
    }
};

// ============================================================================
// 간단한 쉘 (Simple Shell)
// ============================================================================

pub const SimpleShell = struct {
    /// 프롬프트
    prompt: []const u8 = "user@os$> ",
    /// 입력 버퍼
    input_buffer: [256]u8 = undefined,
    /// 입력 길이
    input_len: u16 = 0,
    /// 실행 중인 프로세스 수
    running_processes: u32 = 0,

    /// 명령어 파싱 및 실행
    pub fn executeCommand(self: *SimpleShell, cmd: []const u8) []const u8 {
        if (std.mem.eql(u8, cmd, "help")) {
            return "Available commands: help, pid, echo, exit\n";
        } else if (std.mem.eql(u8, cmd, "pid")) {
            return "PID: 1 (init process)\n";
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            return cmd[5..];
        } else if (std.mem.eql(u8, cmd, "exit")) {
            return "Goodbye!\n";
        }
        return "Unknown command\n";
    }

    /// 백그라운드 작업 추적
    pub fn launchBackground(self: *SimpleShell) void {
        self.running_processes += 1;
    }

    /// 포그라운드 작업 추적
    pub fn launchForeground(self: *SimpleShell) void {
        self.running_processes += 1;
    }
};

// ============================================================================
// 마이크로커널 통합 (Microkernel Integration)
// ============================================================================

pub const MicroKernel = struct {
    /// 커널 이름
    name: []const u8 = "ZigOS Microkernel v1.0",
    /// 부팅 시퀀스
    boot: BootSequence = undefined,
    /// IPC 라우터
    ipc_router: IPCRouter = undefined,
    /// 서비스 레지스트리
    services: ServiceRegistry = undefined,
    /// 드라이버 매니저
    drivers: DriverManager = undefined,
    /// 쉘
    shell: SimpleShell = undefined,
    /// 실행 중인 프로세스 수
    process_count: u32 = 0,

    /// 마이크로커널 초기화
    pub fn initialize(self: *MicroKernel) void {
        // 부팅 시뮬레이션
        self.boot.simulate();

        // 필수 서비스 등록
        _ = self.services.register(Service.new("VFS", .FileSystem, 10));
        _ = self.services.register(Service.new("Window", .Display, 11));
        _ = self.services.register(Service.new("init", .Init, 1));

        // 드라이버 등록 및 초기화
        _ = self.drivers.registerDriver(Driver.new("Timer", .Timer));
        _ = self.drivers.registerDriver(Driver.new("Keyboard", .Keyboard));
        _ = self.drivers.registerDriver(Driver.new("VGA Display", .Display));
        _ = self.drivers.initializeAll();

        // IPC 포트 생성
        _ = self.ipc_router.createPort(1); // init
        _ = self.ipc_router.createPort(10); // VFS
        _ = self.ipc_router.createPort(11); // Window Server

        self.process_count = 3;
    }

    /// 시스템 상태 출력
    pub fn printStatus(self: MicroKernel) void {
        _ = self;
    }

    /// 서비스 헬스 체크
    pub fn healthCheck(self: *MicroKernel) u32 {
        const running = self.services.listRunningServices();
        return running;
    }
};

// ============================================================================
// 마이크로커널 철학 (Philosophy)
// ============================================================================

pub const KernelPhilosophy = struct {
    /// 이 OS의 설계 철학
    pub const Philosophy =
        \\【 ZigOS 설계 철학: 최소화와 신뢰 】
        \\
        \\1. 최소화 원칙 (Minimalism)
        \\   커널은 스케줄링, IPC, 메모리 관리만 담당.
        \\   나머지는 유저 공간의 서비스 서버가 처리.
        \\
        \\2. 안정성 (Reliability)
        \\   한 서비스의 크래시가 전체 시스템을 침범하지 않음.
        \\   자동 재시작으로 회복 탄력성(Resilience) 제공.
        \\
        \\3. 명확한 경계 (Clear Boundaries)
        \\   커널과 유저 공간의 명확한 인터페이스.
        \\   IPC는 유일한 통신 경로.
        \\
        \\4. 기록의 증명 (Record as Proof)
        \\   모든 시스템 호출, IPC 메시지는 기록됨.
        \\   버그 추적과 시스템 분석의 기반.
        \\
        \\5. 확장성 (Extensibility)
        \\   새로운 서비스는 커널 수정 없이 추가 가능.
        \\   드라이버도 유저 공간에서 동작 가능.
    ;
};

// ============================================================================
// VGA 터미널 헬퍼 (테스트용)
// ============================================================================

pub const VGATerminal = struct {
    cursor: u32 = 0,
    const Width = 80;
    const Height = 25;

    pub fn writeString(self: *VGATerminal, str: []const u8) void {
        for (str) |char| {
            if (char == '\n') {
                self.cursor += Width - (self.cursor % Width);
            } else if (self.cursor < Width * Height) {
                self.cursor += 1;
            }
        }
    }

    pub fn clear(self: *VGATerminal) void {
        self.cursor = 0;
    }
};

// ============================================================================
// 테스트 함수들
// ============================================================================

/// Test 1: IPC 메시지 전송
fn testIPCMessaging() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var router: IPCRouter = undefined;
    _ = router.createPort(1); // init
    _ = router.createPort(2); // VFS

    const msg = Message.new(1, 2, 5); // init → VFS, code=5
    const ok = router.routeMessage(msg);

    std.fmt.format(fbs.writer(), "IPC message routed: {}\n", .{ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    if (router.receiveMessage(2)) |received_msg| {
        fbs.reset();
        std.fmt.format(fbs.writer(), "Received from PID {}\n", .{received_msg.from_pid}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }
}

/// Test 2: 서비스 레지스트리
fn testServiceRegistry() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var registry: ServiceRegistry = undefined;
    var vfs = Service.new("VFS", .FileSystem, 10);
    var win = Service.new("Window", .Display, 11);

    _ = registry.register(vfs);
    _ = registry.register(win);

    std.fmt.format(fbs.writer(), "Services registered: {}\n", .{registry.count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    if (registry.findByType(.FileSystem)) |svc| {
        fbs.reset();
        std.fmt.format(fbs.writer(), "Found FS service: {s}\n", .{svc.getName()}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }
}

/// Test 3: 부팅 시퀀스
fn testBootSequence() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var boot: BootSequence = undefined;
    boot.simulate();

    std.fmt.format(fbs.writer(), "Boot progress: {}%\n", .{boot.progress}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Completed stages: {}\n", .{boot.completed_stages}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "System ready: {}\n", .{boot.isReady()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 4: 드라이버 관리
fn testDriverManager() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var manager: DriverManager = undefined;
    _ = manager.registerDriver(Driver.new("Timer", .Timer));
    _ = manager.registerDriver(Driver.new("VGA", .Display));
    _ = manager.registerDriver(Driver.new("Keyboard", .Keyboard));

    _ = manager.initializeAll();

    std.fmt.format(fbs.writer(), "Drivers: {}/{}\n", .{
        manager.getInitializedCount(),
        manager.count,
    }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 5: 마이크로커널 초기화
fn testMicroKernelInit() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var kernel: MicroKernel = undefined;
    kernel.initialize();

    std.fmt.format(fbs.writer(), "Kernel: {s}\n", .{kernel.name}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Boot: {}%\n", .{kernel.boot.progress}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Services: {}\n", .{kernel.services.count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Drivers: {}\n", .{kernel.drivers.count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 6: 서비스 크래시 감지
fn testServiceCrashRecovery() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var registry: ServiceRegistry = undefined;
    _ = registry.register(Service.new("VFS", .FileSystem, 10));

    // 첫 번째 크래시
    _ = registry.recordCrash(10);
    if (registry.findByPid(10)) |svc| {
        fbs.reset();
        std.fmt.format(fbs.writer(), "Crash 1: {}, restarting\n", .{svc.crash_count}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }

    // 여러 번 크래시
    for (0..4) |_| {
        _ = registry.recordCrash(10);
    }

    if (registry.findByPid(10)) |svc| {
        fbs.reset();
        std.fmt.format(fbs.writer(), "Total crashes: {}\n", .{svc.crash_count}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);

        fbs.reset();
        const can_restart = svc.crash_count <= svc.max_restarts;
        std.fmt.format(fbs.writer(), "Can restart: {}\n", .{can_restart}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }
}

/// Test 7: 간단한 쉘
fn testSimpleShell() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var shell: SimpleShell = undefined;

    const help = shell.executeCommand("help");
    std.fmt.format(fbs.writer(), "{s}", .{help}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    const pid = shell.executeCommand("pid");
    std.fmt.format(fbs.writer(), "{s}", .{pid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    const echo = shell.executeCommand("echo Hello, Microkernel!");
    std.fmt.format(fbs.writer(), "{s}\n", .{echo}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 8: 서비스 상태 관리
fn testServiceStateManagement() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var registry: ServiceRegistry = undefined;
    _ = registry.register(Service.new("VFS", .FileSystem, 10));
    _ = registry.register(Service.new("Window", .Display, 11));

    _ = registry.setServiceState(10, 1); // Running
    _ = registry.setServiceState(11, 2); // Crashed

    const running = registry.listRunningServices();
    std.fmt.format(fbs.writer(), "Running services: {}\n", .{running}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 9: IPC 동기식 통신
fn testSyncIPC() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var msg: Message = Message.new(1, 2, 10);
    msg = msg.withData("Hello from init");

    std.fmt.format(fbs.writer(), "Message code: {}\n", .{msg.code}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Data length: {}\n", .{msg.data_len}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 10: 마이크로커널 헬스 체크
fn testKernelHealthCheck() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var kernel: MicroKernel = undefined;
    kernel.initialize();

    const running = kernel.healthCheck();
    std.fmt.format(fbs.writer(), "Health check: {} services running\n", .{running}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Boot progress: {}%\n", .{kernel.boot.progress}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    if (kernel.boot.isReady()) {
        std.fmt.format(fbs.writer(), "System status: READY\n", .{}) catch unreachable;
    } else {
        std.fmt.format(fbs.writer(), "System status: BOOTING\n", .{}) catch unreachable;
    }
    terminal.writeString(buffer[0..fbs.pos]);
}

// ============================================================================
// 최종 이야기: 당신의 OS 철학
// ============================================================================

pub const OSPhilosophy = struct {
    pub const YourPhilosophy =
        \\【 나의 OS 설계 철학: ZigOS 완성 선언 】
        \\
        \\당신이 이곳까지 올 수 있었던 이유는 한 가지입니다.
        \\"기록이 증명이다(Record is Proof)"라는 믿음.
        \\
        \\부트로더의 첫 줄부터 마이크로커널의 마지막 IPC까지,
        \\당신은 매 순간 명시적으로 의도를 기록했습니다.
        \\
        \\1. 명확함(Clarity)은 가장 높은 성능입니다.
        \\   Zig가 "숨겨진 제어 흐름이 없다"고 말한 이유는,
        \\   모든 비용(메모리, CPU, 시간)을 투명하게 보여주고 싶기 때문입니다.
        \\
        \\2. 최소화(Minimalism)가 최대 안정성을 만듭니다.
        \\   마이크로커널은 유저 공간의 안정성을 위해,
        \\   커널 자신을 최대한 단순하게 유지합니다.
        \\   강할수록 부서지지 않습니다.
        \\
        \\3. 기록(Documentation)이 없다면 버그는 반복됩니다.
        \\   당신의 코드는 다른 사람이 읽을 것을 고려해서 작성했습니다.
        \\   그것이 전문가와 초보자의 차이입니다.
        \\
        \\4. IPC는 신뢰 기반의 소통입니다.
        \\   마이크로커널에서 모든 서비스는 평등합니다.
        \\   커널과 서비스, 서비스와 서비스 모두 메시지로 대화합니다.
        \\   이것이 민주주의적 설계입니다.
        \\
        \\5. 회복 탄력성(Resilience)은 설계의 핵심입니다.
        \\   한 서비스의 죽음이 전체를 침범하지 않는 구조.
        \\   자동 재시작으로 높은 가용성을 보장합니다.
        \\   이것이 신뢰할 수 있는 시스템의 조건입니다.
        \\
        \\【 축하합니다! 당신은 시스템 마스터입니다. 】
        \\
        \\이제 당신은 하드웨어의 물리적 한계를 소프트웨어의 논리로 극복할 수 있습니다.
        \\
        \\당신의 기록은 이미 증명되었습니다.
    ;
};

// ============================================================================
// 메인 실행 (테스트)
// ============================================================================

pub fn main() void {
    // Test execution
    testIPCMessaging();
    testServiceRegistry();
    testBootSequence();
    testDriverManager();
    testMicroKernelInit();
    testServiceCrashRecovery();
    testSimpleShell();
    testServiceStateManagement();
    testSyncIPC();
    testKernelHealthCheck();
}
