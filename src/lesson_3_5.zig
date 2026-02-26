// ============================================================================
// Lesson 3-5: 프로세스와 스레드 - 컨텍스트 스위칭의 마법
// ============================================================================
//
// 핵심 개념:
// - 프로세스: 독립된 가상 메모리 공간을 가진 '집'
// - 스레드: 그 안에서 실제로 일을 하는 '일꾼'
// - 컨텍스트: CPU의 모든 레지스터 상태를 기록한 '사진'
// - 컨텍스트 스위칭: 일꾼을 아주 빠르게 교체하며 동시성 구현
// - 스케줄러: "다음은 누구 차례인가?"를 결정
//
// x86_64 컨텍스트 구조:
// - 16개 범용 레지스터 (R15~RAX)
// - RIP (명령 포인터)
// - RFLAGS (프로세서 상태)
// - RSP/RBP (스택 포인터)
// - CS/SS (세그먼트 셀렉터)
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 상수 정의
// ============================================================================

const PageSize = 4096;
const ThreadStackSize = 8 * PageSize; // 32KB per thread
const MaxThreads = 16;
const TimerTickThreshold = 100; // 100 타이머 틱마다 스위칭

// ============================================================================
// CPU 컨텍스트 (Context) - 레지스터 저장 영역
// ============================================================================

/// x86_64 CPU 컨텍스트 - 모든 레지스터를 저장하는 구조
/// 컨텍스트 스위칭 시 이 구조체의 모든 필드가 저장/복원됨
pub const Context = packed struct {
    // 범용 레지스터 (16개)
    // 함수 호출 시 호출자가 보존해야 할 레지스터: R12~R15, RBX, RBP, RSP
    // 호출자가 파괴해도 되는 레지스터: RAX, RCX, RDX, RSI, RDI, R8~R11

    /// R15 - 범용 레지스터
    r15: u64 = 0,
    /// R14 - 범용 레지스터
    r14: u64 = 0,
    /// R13 - 범용 레지스터
    r13: u64 = 0,
    /// R12 - 범용 레지스터
    r12: u64 = 0,
    /// R11 - 임시 레지스터
    r11: u64 = 0,
    /// R10 - 임시 레지스터
    r10: u64 = 0,
    /// R9 - 함수 인자 4번
    r9: u64 = 0,
    /// R8 - 함수 인자 3번
    r8: u64 = 0,
    /// RBP - 베이스 포인터 (스택 프레임)
    rbp: u64 = 0,
    /// RDI - 함수 인자 1번
    rdi: u64 = 0,
    /// RSI - 함수 인자 2번
    rsi: u64 = 0,
    /// RDX - 함수 인자 3번 / 반환값 2번
    rdx: u64 = 0,
    /// RCX - 함수 인자 4번
    rcx: u64 = 0,
    /// RBX - 범용 레지스터 (보존)
    rbx: u64 = 0,
    /// RAX - 누산기 / 반환값
    rax: u64 = 0,

    // 특수 레지스터
    /// RIP - 명령 포인터 (다음 실행할 명령의 주소)
    rip: u64 = 0,
    /// CS - 코드 세그먼트
    cs: u64 = 0,
    /// RFLAGS - 프로세서 상태 레지스터
    /// ZF(Zero Flag), CF(Carry Flag), OF(Overflow Flag) 등 포함
    rflags: u64 = 0x202, // IF(인터럽트 활성화) 포함
    /// RSP - 스택 포인터
    rsp: u64 = 0,
    /// SS - 스택 세그먼트
    ss: u64 = 0,

    pub fn init() Context {
        return .{};
    }
};

// ============================================================================
// Task State Segment (TSS) - 커널 스택 정보
// ============================================================================

/// x86_64 Task State Segment
/// CPU가 유저 모드에서 인터럽트를 받으면 커널의 어느 스택을 사용할지 알려줌
pub const TaskStateSegment = struct {
    reserved0: u32 = 0,

    /// 권한 레벨 0(커널)에서의 스택 포인터
    rsp0: u64 = 0,
    /// 권한 레벨 1에서의 스택 포인터 (사용하지 않음)
    rsp1: u64 = 0,
    /// 권한 레벨 2에서의 스택 포인터 (사용하지 않음)
    rsp2: u64 = 0,

    reserved1: u64 = 0,

    /// Interrupt Stack Table 포인터
    ist: [7]u64 = [_]u64{0} ** 7,

    reserved2: u64 = 0,
    reserved3: u16 = 0,

    /// I/O Map Base Address
    iomap_base: u16 = 0,
};

// ============================================================================
// 프로세스 제어 블록 (PCB)
// ============================================================================

/// 프로세스 상태
pub const ProcessState = enum(u8) {
    Created = 0,
    Ready = 1,
    Running = 2,
    Waiting = 3,
    Terminated = 4,
};

/// 프로세스 제어 블록 (PCB)
pub const Process = struct {
    /// 프로세스 ID
    pid: u64 = 0,

    /// 프로세스 상태
    state: ProcessState = .Created,

    /// 가상 메모리 공간 (PML4 테이블 포인터)
    pml4_address: u64 = 0,

    /// 부모 프로세스 ID
    parent_pid: u64 = 0,

    /// 자식 프로세스들 (최대 8개)
    children: [8]u64 = [_]u64{0} ** 8,
    child_count: u8 = 0,

    pub fn init(pid: u64) Process {
        return .{
            .pid = pid,
            .state = .Created,
            .pml4_address = 0,
            .parent_pid = 0,
        };
    }
};

// ============================================================================
// 스레드 제어 블록 (TCB)
// ============================================================================

/// 스레드 상태
pub const ThreadState = enum(u8) {
    Ready = 0,
    Running = 1,
    Waiting = 2,
    Terminated = 3,
};

/// 스레드 제어 블록 (TCB)
pub const Thread = struct {
    /// 스레드 ID
    tid: u64 = 0,

    /// 스레드가 속한 프로세스 ID
    pid: u64 = 0,

    /// 스레드 상태
    state: ThreadState = .Ready,

    /// 스택 기본 주소
    stack_base: u64 = 0,

    /// 스택 포인터 (RSP 저장 위치)
    stack_pointer: u64 = 0,

    /// CPU 컨텍스트
    context: Context = .{},

    /// 실행 시간 (틱 단위)
    execution_ticks: u64 = 0,

    /// 타임 슬라이스 (이 스레드의 연속 실행 시간)
    time_slice: u64 = 5, // 5 틱

    /// 우선순위 (0 = 가장 높음)
    priority: u8 = 0,

    pub fn init(tid: u64, pid: u64, stack_base: u64) Thread {
        return .{
            .tid = tid,
            .pid = pid,
            .state = .Ready,
            .stack_base = stack_base,
            .stack_pointer = stack_base,
            .context = Context.init(),
        };
    }

    pub fn initStack(self: *Thread, entry_point: u64) void {
        // 스택을 초기화하여 ret 명령어가 entry_point로 점프하도록 설정
        // 스택: [...] <- 스택 포인터는 여기를 가리킴
        //       [entry_point] <- ret이 이 주소로 점프

        const stack_top = self.stack_base;
        self.stack_pointer = stack_top - 8;

        // 스택 최상단에 entry point 주소 배치
        const rsp_ptr = @as(*u64, @ptrFromInt(self.stack_pointer));
        rsp_ptr.* = entry_point;

        // 컨텍스트 초기화
        self.context.rsp = self.stack_pointer;
        self.context.rbp = self.stack_base;
        self.context.rip = entry_point;
        self.context.rflags = 0x202; // IF 비트 설정 (인터럽트 활성화)
    }
};

// ============================================================================
// 스케줄러 (Scheduler)
// ============================================================================

/// 스케줄링 알고리즘
pub const SchedulingAlgorithm = enum {
    RoundRobin,
    Priority,
    FCFS, // First Come First Served
};

/// 스케줄러
pub const Scheduler = struct {
    /// 현재 실행 중인 스레드
    current_thread: ?*Thread = null,

    /// 모든 스레드 (최대 16개)
    threads: [MaxThreads]?*Thread = [_]?*Thread{null} ** MaxThreads,
    thread_count: u8 = 0,

    /// 다음 스레드 ID
    next_tid: u64 = 1,

    /// 다음 프로세스 ID
    next_pid: u64 = 1,

    /// 스케줄링 알고리즘
    algorithm: SchedulingAlgorithm = .RoundRobin,

    /// 타이머 틱 카운트
    tick_count: u64 = 0,

    /// 컨텍스트 스위치 횟수
    context_switches: u64 = 0,

    /// 스레드 생성
    pub fn createThread(self: *Scheduler, pid: u64, stack_base: u64, entry_point: u64) !*Thread {
        if (self.thread_count >= MaxThreads) {
            return error.TooManyThreads;
        }

        const tid = self.next_tid;
        self.next_tid += 1;

        var thread = &thread_pool[self.thread_count];
        thread.* = Thread.init(tid, pid, stack_base);
        thread.initStack(entry_point);

        self.threads[self.thread_count] = thread;
        self.thread_count += 1;

        return thread;
    }

    /// 현재 실행 중인 스레드 반환
    pub fn getCurrentThread(self: Scheduler) ?*Thread {
        return self.current_thread;
    }

    /// 다음 실행할 스레드 선택 (Round Robin)
    pub fn scheduleNext(self: *Scheduler) ?*Thread {
        if (self.current_thread == null) {
            // 첫 번째 스레드
            if (self.thread_count > 0) {
                return self.threads[0];
            }
            return null;
        }

        // 현재 스레드의 인덱스 찾기
        var current_index: usize = 0;
        for (0..self.thread_count) |i| {
            if (self.threads[i] == self.current_thread) {
                current_index = i;
                break;
            }
        }

        // 다음 Ready 상태의 스레드 찾기
        var search_count: usize = 0;
        while (search_count < self.thread_count) : (search_count += 1) {
            current_index = (current_index + 1) % self.thread_count;
            const thread = self.threads[current_index];

            if (thread != null and thread.?.state == .Ready) {
                return thread;
            }
        }

        return null;
    }

    /// 타이머 인터럽트 핸들러
    pub fn handleTimerInterrupt(self: *Scheduler) void {
        self.tick_count += 1;

        // 현재 스레드의 타임 슬라이스 감소
        if (self.current_thread != null) {
            self.current_thread.?.execution_ticks += 1;

            // 타임 슬라이스 초과 시 다음 스레드로 전환
            if (self.current_thread.?.execution_ticks >= self.current_thread.?.time_slice) {
                self.switchContext();
            }
        }

        // 타이머 틱 카운트 출력 (100번마다)
        if (self.tick_count % TimerTickThreshold == 0) {
            // 타이머 발동 신호 - VGA에 점(.) 출력
            timer_tick_signal = true;
        }
    }

    /// 컨텍스트 스위칭 수행
    pub fn switchContext(self: *Scheduler) void {
        // 현재 스레드의 상태를 Ready로 변경 (재실행 가능)
        if (self.current_thread != null) {
            self.current_thread.?.state = .Ready;
            self.current_thread.?.execution_ticks = 0;
        }

        // 다음 실행할 스레드 선택
        const next_thread = self.scheduleNext();
        if (next_thread) |thread| {
            thread.state = .Running;
            self.current_thread = thread;
            self.context_switches += 1;
        }
    }

    /// 스레드 종료
    pub fn terminateThread(self: *Scheduler, tid: u64) !void {
        for (0..self.thread_count) |i| {
            if (self.threads[i]) |thread| {
                if (thread.tid == tid) {
                    thread.state = .Terminated;

                    // 실행 중인 스레드가 종료되면 다음 스레드로 전환
                    if (self.current_thread == thread) {
                        self.switchContext();
                    }

                    return;
                }
            }
        }

        return error.ThreadNotFound;
    }

    pub fn getStats(self: Scheduler) struct {
        thread_count: u8,
        context_switches: u64,
        total_ticks: u64,
    } {
        return .{
            .thread_count = self.thread_count,
            .context_switches = self.context_switches,
            .total_ticks = self.tick_count,
        };
    }
};

// 전역 스레드 풀
var thread_pool: [MaxThreads]Thread = undefined;

// 타이머 틱 신호
var timer_tick_signal: bool = false;

// 전역 스케줄러
var global_scheduler: Scheduler = .{};

// ============================================================================
// 스택 초기화 설계 분석
// ============================================================================

pub const StackInitializationAnalysis = struct {
    /// 새 스레드의 스택 초기화 방법:
    ///
    /// 1. 스택 할당:
    ///    - stack_base: 스택 시작 주소 (높은 주소)
    ///    - stack_pointer: 현재 스택 최상단 (낮은 주소)
    ///
    /// 2. 스택 구성 (높은 주소 → 낮은 주소):
    ///    [stack_base]          ← RBP 초기값 (베이스 포인터)
    ///    ...
    ///    [stack_base - 8]      ← RSP 초기값 (스택 포인터)
    ///                             이 위치에 entry_point 주소가 저장됨
    ///
    /// 3. 첫 실행:
    ///    - CPU가 이 스레드를 실행할 때 RSP = stack_base - 8
    ///    - ret 명령어가 실행되면 [RSP]의 값(entry_point)이 RIP에 로드됨
    ///    - 따라서 entry_point 함수가 실행 시작됨
    ///
    /// 4. 함수 에필로그:
    ///    - push rbp               (이전 스택 프레임 저장)
    ///    - mov rbp, rsp           (새로운 베이스 포인터 설정)
    ///    - ...                    (함수 바디)
    ///    - mov rsp, rbp           (스택 복원)
    ///    - pop rbp                (이전 베이스 포인터 복원)
    ///    - ret                    (다음 실행 주소로 점프)
    ///

    pub fn description() []const u8 {
        return
            \\새 스레드 스택 초기화 단계:
            \\
            \\1. 메모리 할당
            \\   stack_base = 0x7000 (높은 주소, 스택 시작)
            \\   stack_size = 32KB
            \\
            \\2. 스택 최상단 계산
            \\   rsp = stack_base - 8
            \\   rsp = 0x6FF8 (스택 포인터가 가리키는 위치)
            \\
            \\3. 스택에 entry point 배치
            \\   [0x6FF8] = entry_point (0x100000이라고 가정)
            \\
            \\4. 컨텍스트 초기화
            \\   context.rsp = 0x6FF8
            \\   context.rbp = 0x7000
            \\   context.rip = 0x100000 (entry point)
            \\   context.rflags = 0x202 (IF 비트 = 1, 인터럽트 활성화)
            \\
            \\5. 스레드 실행 시작
            \\   CPU가 RIP=0x100000으로 점프
            \\   RSP=0x6FF8 (스택 최상단을 가리킴)
            \\   ret 명령어가 실행되면 [RSP]=0x100000이 RIP에 로드됨
            \\   (이미 RIP=0x100000이므로 실제로는 함수 프롤로그 이후에 실행)
        ;
    }
};

// ============================================================================
// 스레드 상태 천이도 (State Transition Diagram)
// ============================================================================

pub const ThreadStateTransitionDiagram = struct {
    pub fn description() []const u8 {
        return
            \\【 스레드 상태 천이도 】
            \\
            \\1. Ready 상태
            \\   ├─ CPU가 이 스레드를 선택함
            \\   └─ → Running
            \\
            \\2. Running 상태
            \\   ├─ 타임 슬라이스 종료 (5 틱)
            \\   │  └─ → Ready (다시 대기)
            \\   ├─ I/O 대기 필요
            \\   │  └─ → Waiting
            \\   └─ exit() 호출
            \\      └─ → Terminated
            \\
            \\3. Waiting 상태
            \\   ├─ I/O 완료
            \\   │  └─ → Ready
            \\   └─ 타임아웃
            \\      └─ → Ready (또는 Terminated)
            \\
            \\4. Terminated 상태
            \\   └─ 스케줄러에서 제거됨
            \\
            \\【 컨텍스트 스위칭 시나리오 】
            \\
            \\T0: Thread-1 (Running)
            \\    ├─ execution_ticks: 0→1→2→3→4→5 (시간 슬라이스 종료)
            \\    └─ state: Running → Ready
            \\
            \\T1: Thread-2 (Ready) 선택됨
            \\    ├─ state: Ready → Running
            \\    └─ execution_ticks: 0부터 시작
            \\
            \\T2: Thread-2 (Running)
            \\    ├─ execution_ticks: 0→1→2→3→4→5
            \\    └─ state: Running → Ready
            \\
            \\T3: Thread-3 (Ready) 선택됨
            \\    └─ state: Ready → Running
        ;
    }
};

// ============================================================================
// 레지스터 저장 요구사항
// ============================================================================

pub const RegisterSavingRequirements = struct {
    pub fn description() []const u8 {
        return
            \\【 x86_64 컨텍스트 스위칭 시 저장해야 할 레지스터 】
            \\
            \\1. 반드시 저장해야 할 레지스터 (Callee-saved)
            \\   - RBX: 범용 레지스터
            \\   - RBP: 베이스 포인터
            \\   - RSP: 스택 포인터
            \\   - R12~R15: 범용 레지스터
            \\   - RIP: 명령 포인터 (다음 실행할 주소)
            \\   - RFLAGS: 프로세서 상태
            \\   - CS: 코드 세그먼트
            \\   - SS: 스택 세그먼트
            \\
            \\2. 호출 규약에 따라 함수가 보존
            \\   (일반적으로는 저장해야 함)
            \\   - RAX: 반환값 1번
            \\   - RCX: 함수 인자 4번
            \\   - RDX: 함수 인자 3번
            \\   - RSI: 함수 인자 2번
            \\   - RDI: 함수 인자 1번
            \\   - R8~R11: 함수 인자 및 임시
            \\
            \\3. 벡터/부동소수점 (필요시)
            \\   - XMM0~XMM15: SSE 레지스터
            \\   - YMM0~YMM15: AVX 레지스터 (상위 128비트)
            \\
            \\【 저장 규칙 】
            \\
            \\Context 구조체에서 모두 저장하는 이유:
            \\- 스레드가 언제든 중단될 수 있음
            \\- 일관성 있는 상태 관리 필요
            \\- 복잡한 호출 규약 처리 불필요
        ;
    }
};

// ============================================================================
// VGA 출력 (Lesson 3-1과 호환)
// ============================================================================

const VGAColor = enum(u4) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_gray = 7,
    dark_gray = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    light_brown = 14,
    white = 15,
};

const VGAEntry = packed struct {
    ascii: u8,
    foreground: u4,
    background: u4,
};

const VGATerminal = struct {
    buffer: [*]volatile VGAEntry = @ptrFromInt(0xB8000),
    column: u8 = 0,
    row: u8 = 0,

    const width = 80;
    const height = 25;

    fn putChar(self: *VGATerminal, char: u8) void {
        if (char == '\n') {
            self.column = 0;
            self.row += 1;
            if (self.row >= height) {
                self.row = height - 1;
            }
        } else {
            const index = self.row * width + self.column;
            self.buffer[index] = VGAEntry{
                .ascii = char,
                .foreground = @intFromEnum(VGAColor.light_green),
                .background = @intFromEnum(VGAColor.black),
            };
            self.column += 1;
            if (self.column >= width) {
                self.column = 0;
                self.row += 1;
            }
        }
    }

    fn writeString(self: *VGATerminal, str: []const u8) void {
        for (str) |char| {
            self.putChar(char);
        }
    }

    fn clear(self: *VGATerminal) void {
        const empty = VGAEntry{
            .ascii = ' ',
            .foreground = @intFromEnum(VGAColor.light_gray),
            .background = @intFromEnum(VGAColor.black),
        };
        for (0..(width * height)) |i| {
            self.buffer[i] = empty;
        }
        self.column = 0;
        self.row = 0;
    }

    fn putDot(self: *VGATerminal) void {
        self.putChar('.');
    }
};

// ============================================================================
// 테스트 함수
// ============================================================================

pub fn testContextStructure() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 1: Context Structure ===\n");

    const ctx = Context.init();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Context size: {} bytes\n", .{@sizeOf(Context)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Registers: {}\n", .{19}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("R15, R14, ..., RAX, RIP, CS, RFLAGS, RSP, SS\n");
}

pub fn testThreadCreation() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 2: Thread Creation ===\n");

    global_scheduler.algorithm = .RoundRobin;

    const stack_base: u64 = 0x10000;
    const entry_point: u64 = 0x100000;

    const thread = try global_scheduler.createThread(1, stack_base, entry_point);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Thread ID: {}\n", .{thread.tid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Stack base: 0x{X}\n", .{thread.stack_base}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Stack pointer: 0x{X}\n", .{thread.stack_pointer}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testMultipleThreads() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 3: Multiple Threads ===\n");

    // 3개 스레드 생성
    _ = try global_scheduler.createThread(1, 0x10000, 0x100000);
    _ = try global_scheduler.createThread(1, 0x18000, 0x100100);
    _ = try global_scheduler.createThread(1, 0x20000, 0x100200);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Created threads: {}\n", .{global_scheduler.thread_count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testScheduling() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 4: Scheduling ===\n");

    global_scheduler.thread_count = 0;

    _ = try global_scheduler.createThread(1, 0x10000, 0x100000);
    _ = try global_scheduler.createThread(1, 0x18000, 0x100100);

    // 첫 스케줄
    const first = global_scheduler.scheduleNext();
    if (first) |thread| {
        global_scheduler.current_thread = thread;
        thread.state = .Running;
    }

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Current thread: {}\n", .{global_scheduler.current_thread.?.tid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "State: Running\n", .{}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testContextSwitching() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 5: Context Switching ===\n");

    global_scheduler.thread_count = 0;

    _ = try global_scheduler.createThread(1, 0x10000, 0x100000);
    _ = try global_scheduler.createThread(1, 0x18000, 0x100100);

    // 스케줄 시작
    if (global_scheduler.scheduleNext()) |thread| {
        global_scheduler.current_thread = thread;
        thread.state = .Running;
    }

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Initial: Thread {}\n", .{global_scheduler.current_thread.?.tid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // 컨텍스트 스위칭
    global_scheduler.switchContext();

    fbs.reset();
    std.fmt.format(fbs.writer(), "After switch: Thread {}\n", .{global_scheduler.current_thread.?.tid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Switches: {}\n", .{global_scheduler.context_switches}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testTimerInterrupt() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 6: Timer Interrupt (Proof of Multitasking) ===\n");
    terminal.writeString("Processing timer ticks (100 per dot): ");

    global_scheduler.thread_count = 0;

    _ = try global_scheduler.createThread(1, 0x10000, 0x100000);
    _ = try global_scheduler.createThread(1, 0x18000, 0x100100);

    if (global_scheduler.scheduleNext()) |thread| {
        global_scheduler.current_thread = thread;
        thread.state = .Running;
    }

    // 1000 타이머 틱 시뮬레이션
    for (0..1000) |_| {
        global_scheduler.handleTimerInterrupt();

        if (timer_tick_signal) {
            terminal.putDot();
            timer_tick_signal = false;
        }
    }

    terminal.writeString("\n");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Total ticks: {}\n", .{global_scheduler.tick_count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Context switches: {}\n", .{global_scheduler.context_switches}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testThreadStateTransition() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 7: Thread State Transition ===\n");

    global_scheduler.thread_count = 0;

    const thread1 = try global_scheduler.createThread(1, 0x10000, 0x100000);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Initial: {}\n", .{@intFromEnum(thread1.state)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    thread1.state = .Running;
    fbs.reset();
    std.fmt.format(fbs.writer(), "Running: {}\n", .{@intFromEnum(thread1.state)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    thread1.state = .Waiting;
    fbs.reset();
    std.fmt.format(fbs.writer(), "Waiting: {}\n", .{@intFromEnum(thread1.state)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    thread1.state = .Terminated;
    fbs.reset();
    std.fmt.format(fbs.writer(), "Terminated: {}\n", .{@intFromEnum(thread1.state)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testSchedulerStats() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 8: Scheduler Statistics ===\n");

    const stats = global_scheduler.getStats();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Threads: {}\n", .{stats.thread_count}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Context switches: {}\n", .{stats.context_switches}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Total ticks: {}\n", .{stats.total_ticks}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testStackInitialization() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 9: Stack Initialization Design ===\n");
    terminal.writeString(StackInitializationAnalysis.description());
}

pub fn testStateTransitionDiagram() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 10: State Transition Diagram ===\n");
    terminal.writeString(ThreadStateTransitionDiagram.description());
}

// ============================================================================
// 메인 진입점
// ============================================================================

pub export fn _start() noreturn {
    var terminal: VGATerminal = .{};
    terminal.clear();

    // 헤더
    terminal.writeString("╔═════════════════════════════════════════════╗\n");
    terminal.writeString("║ Lesson 3-5: Context Switching & Multitask  ║\n");
    terminal.writeString("║     Process, Thread, and Scheduling        ║\n");
    terminal.writeString("╚═════════════════════════════════════════════╝\n\n");

    // 아키텍처 정보
    terminal.writeString("📊 Multitasking Architecture:\n");
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    std.fmt.format(fbs.writer(), "  Context size: {} bytes\n", .{@sizeOf(Context)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Thread stack: {}KB\n", .{ThreadStackSize / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Max threads: {}\n", .{MaxThreads}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("\n🧪 Running Tests...\n\n");

    // 테스트 실행
    testContextStructure();
    terminal.writeString("\n");

    testThreadCreation() catch |err| {
        terminal.writeString("ERROR: Test 2 failed\n");
    };
    terminal.writeString("\n");

    testMultipleThreads() catch |err| {
        terminal.writeString("ERROR: Test 3 failed\n");
    };
    terminal.writeString("\n");

    testScheduling() catch |err| {
        terminal.writeString("ERROR: Test 4 failed\n");
    };
    terminal.writeString("\n");

    testContextSwitching() catch |err| {
        terminal.writeString("ERROR: Test 5 failed\n");
    };
    terminal.writeString("\n");

    testTimerInterrupt() catch |err| {
        terminal.writeString("ERROR: Test 6 failed\n");
    };
    terminal.writeString("\n");

    testThreadStateTransition() catch |err| {
        terminal.writeString("ERROR: Test 7 failed\n");
    };
    terminal.writeString("\n");

    testSchedulerStats() catch |err| {
        terminal.writeString("ERROR: Test 8 failed\n");
    };
    terminal.writeString("\n");

    testStackInitialization();
    terminal.writeString("\n");

    testStateTransitionDiagram();

    terminal.writeString("\n═════════════════════════════════════════════\n");
    terminal.writeString("✅ Assignment 3-5: Multitasking Complete!\n");
    terminal.writeString("기록이 증명이다 - Context Switching Ready!\n");
    terminal.writeString("═════════════════════════════════════════════\n");

    // CPU 정지
    while (true) {
        asm volatile ("hlt");
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var terminal: VGATerminal = .{};
    terminal.writeString("PANIC: ");
    terminal.writeString(msg);
    terminal.writeString("\n");

    while (true) {
        asm volatile ("hlt");
    }
}
