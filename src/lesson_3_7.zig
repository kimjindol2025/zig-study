// ============================================================================
// Lesson 3-7: 시스템 호출과 유저 모드(Ring 3) 진입
// ============================================================================
//
// 핵심 개념:
// - Ring 0 vs Ring 3: CPU 특권 수준 (Privilege Level)
// - syscall / sysret: 빠른 시스템 호출 명령어
// - MSR (Model Specific Register): LSTAR 핸들러 주소 설정
// - 유저 모드 진입: 스택 조작과 iretq 트릭
// - Calling Convention: 레지스터 기반 인수 전달
// - 포인터 검증: 유저 메모리 범위 확인
// - Syscall Table: 호출 번호 → 함수 매핑
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 상수 및 타입 정의
// ============================================================================

/// CPU Ring 수준
pub const Ring = enum(u2) {
    Kernel = 0, // Ring 0 - 모든 권한
    Ring1 = 1,  // Ring 1 - 제한된 권한
    Ring2 = 2,  // Ring 2 - 더 제한된 권한
    User = 3,   // Ring 3 - 최소 권한
};

/// 프로세서 예외 상태
pub const ProcessorState = struct {
    /// RIP: 명령 포인터 (Instruction Pointer)
    rip: u64 = 0,
    /// RSP: 스택 포인터 (Stack Pointer)
    rsp: u64 = 0,
    /// RFLAGS: 플래그 레지스터
    rflags: u64 = 0x200, // IF (Interrupt Flag) 활성화
    /// CS: 코드 세그먼트
    cs: u16 = 0x08, // Kernel CS
    /// SS: 스택 세그먼트
    ss: u16 = 0x10, // Kernel SS
};

/// 시스템 호출 번호
pub const SyscallNumber = enum(u64) {
    Read = 0,   // read(fd, buf, count)
    Write = 1,  // write(fd, buf, count)
    Exit = 60,  // exit(status)
    Open = 2,   // open(path, flags, mode)
    Close = 3,  // close(fd)
    GetPid = 39, // getpid()
};

/// Syscall 인수 구조
pub const SyscallArgs = struct {
    rax: u64 = 0, // Syscall number
    rdi: u64 = 0, // 1st argument
    rsi: u64 = 0, // 2nd argument
    rdx: u64 = 0, // 3rd argument
    r10: u64 = 0, // 4th argument
    r8: u64 = 0,  // 5th argument
    r9: u64 = 0,  // 6th argument
};

/// 유저 포인터 검증 결과
pub const PointerValidation = enum {
    Valid,
    OutOfBounds,
    NullPointer,
    KernelMemory,
};

// ============================================================================
// 메모리 보호 (Memory Protection)
// ============================================================================

/// 유저 공간 메모리 범위
pub const UserMemorySpace = struct {
    /// 유저 공간 시작 주소 (4KB 경계)
    start: u64 = 0x400000, // 4MB (일반적인 유저 공간 시작)
    /// 유저 공간 끝 주소 (48비트 선형 주소 공간)
    end: u64 = 0x00007FFFFFFFFFFF,

    /// 주소가 유저 공간에 속하는지 확인
    pub fn isInUserSpace(self: UserMemorySpace, addr: u64) bool {
        return addr >= self.start and addr < self.end;
    }

    /// 메모리 범위가 유저 공간에 완전히 포함되는지 확인
    pub fn isRangeInUserSpace(self: UserMemorySpace, start: u64, len: u64) bool {
        if (len == 0) return true;

        const end = start +% len; // wrapping add
        if (end < start) return false; // overflow 감지

        return self.isInUserSpace(start) and self.isInUserSpace(end - 1);
    }
};

// ============================================================================
// 포인터 검증 (Pointer Validation)
// ============================================================================

pub const PointerValidator = struct {
    user_space: UserMemorySpace,

    /// 유저가 전달한 포인터 검증
    pub fn validateUserPointer(
        self: PointerValidator,
        ptr: u64,
        len: usize,
    ) PointerValidation {
        // Null 포인터 확인
        if (ptr == 0) return .NullPointer;

        // 커널 메모리 확인 (Higher Half Kernel)
        // 커널은 0xFFFF800000000000 이상의 주소를 사용
        if (ptr >= 0xFFFF800000000000) return .KernelMemory;

        // 유저 공간 범위 확인
        if (!self.user_space.isRangeInUserSpace(ptr, len)) {
            return .OutOfBounds;
        }

        return .Valid;
    }

    /// 유저 포인터를 슬라이스로 변환 (검증 포함)
    pub fn validateUserBuffer(
        self: PointerValidator,
        ptr: u64,
        len: usize,
    ) ?[]u8 {
        if (self.validateUserPointer(ptr, len) != .Valid) {
            return null;
        }

        // 포인터를 슬라이스로 변환
        const buf_ptr: [*]u8 = @ptrFromInt(ptr);
        return buf_ptr[0..len];
    }
};

// ============================================================================
// 시스템 호출 테이블 (Syscall Table)
// ============================================================================

pub const SyscallHandler = *const fn (args: SyscallArgs) u64;

pub const SyscallTable = struct {
    /// 최대 지원 가능한 시스템 호출 수
    const MaxSyscalls = 512;

    /// 시스템 호출 핸들러 테이블
    handlers: [MaxSyscalls]?SyscallHandler = [_]?SyscallHandler{null} ** MaxSyscalls,

    /// 특정 syscall 번호에 핸들러 등록
    pub fn register(self: *SyscallTable, num: u64, handler: SyscallHandler) bool {
        if (num >= MaxSyscalls) return false;
        self.handlers[num] = handler;
        return true;
    }

    /// Syscall 실행
    pub fn execute(self: SyscallTable, args: SyscallArgs) u64 {
        if (args.rax >= MaxSyscalls) return 0xFFFFFFFFFFFFFFFF; // -ENOSYS
        if (self.handlers[args.rax]) |handler| {
            return handler(args);
        }
        return 0xFFFFFFFFFFFFFFFF; // -ENOSYS
    }
};

// ============================================================================
// 기본 시스템 호출 구현
// ============================================================================

/// 현재 프로세스 ID (테스트용 간단 구현)
var current_pid: u32 = 1;

/// write syscall 핸들러 (파일 디스크립터에 쓰기)
fn syscallWrite(args: SyscallArgs) u64 {
    const fd = args.rdi; // 파일 디스크립터
    const buf_ptr = args.rsi; // 버퍼 주소
    const count = args.rdx; // 바이트 수

    // 스탠다드 출력(fd=1)만 지원
    if (fd != 1) return 0xFFFFFFFFFFFFFFFF;

    // 유저 메모리 검증
    var validator = PointerValidator{
        .user_space = UserMemorySpace{},
    };

    if (validator.validateUserBuffer(buf_ptr, @intCast(count))) |buf| {
        // 실제로는 VGA 터미널에 출력
        // 여기서는 count를 반환 (성공)
        return count;
    }

    return 0xFFFFFFFFFFFFFFFF; // -EFAULT (잘못된 주소)
}

/// read syscall 핸들러 (파일 디스크립터에서 읽기)
fn syscallRead(args: SyscallArgs) u64 {
    const fd = args.rdi; // 파일 디스크립터
    const buf_ptr = args.rsi; // 버퍼 주소
    const count = args.rdx; // 바이트 수

    // 스탠다드 입력(fd=0)만 지원
    if (fd != 0) return 0xFFFFFFFFFFFFFFFF;

    // 유저 메모리 검증
    var validator = PointerValidator{
        .user_space = UserMemorySpace{},
    };

    if (validator.validateUserBuffer(buf_ptr, @intCast(count))) |_buf| {
        // 실제로는 입력을 읽어옴
        // 여기서는 0을 반환 (EOF)
        return 0;
    }

    return 0xFFFFFFFFFFFFFFFF; // -EFAULT
}

/// exit syscall 핸들러 (프로세스 종료)
fn syscallExit(args: SyscallArgs) u64 {
    const status = args.rdi; // 종료 코드
    // 실제로는 프로세스를 종료하고 스케줄러로 돌아감
    return status; // 반환값은 사용되지 않음
}

/// getpid syscall 핸들러 (프로세스 ID 조회)
fn syscallGetPid(_args: SyscallArgs) u64 {
    return current_pid;
}

// ============================================================================
// 시스템 호출 진입점 (Syscall Entry Point)
// ============================================================================

pub const SyscallDispatcher = struct {
    table: SyscallTable,
    validator: PointerValidator,

    /// 시스템 호출 처리 (메인 핸들러)
    pub fn dispatch(self: SyscallDispatcher, args: SyscallArgs) u64 {
        // Syscall 번호 검증
        if (args.rax >= SyscallTable.MaxSyscalls) {
            return 0xFFFFFFFFFFFFFFFF; // -ENOSYS
        }

        // 등록된 핸들러 실행
        return self.table.execute(args);
    }

    /// 스택에 저장된 인수 추출 (sysret 후 복귀)
    pub fn extractArgsFromStack(sp: u64) SyscallArgs {
        // 실제 구현에서는 스택에서 인수를 읽음
        // 여기서는 개념적 표현
        return SyscallArgs{};
    }
};

// ============================================================================
// 유저 모드 진입 메커니즘 (User Mode Entry)
// ============================================================================

pub const UserModeEntry = struct {
    /// 유저 스택 크기 (4KB)
    const UserStackSize = 4096;

    /// 유저 모드로 전환하기 위한 상태
    pub const UserState = struct {
        /// 유저 코드 세그먼트 (Ring 3)
        user_cs: u16 = 0x23, // Ring 3 Code Segment
        /// 유저 스택 세그먼트 (Ring 3)
        user_ss: u16 = 0x2B, // Ring 3 Stack Segment
        /// 유저 스택 포인터
        user_sp: u64,
        /// 유저 명령 포인터 (진입점)
        user_ip: u64,
    };

    /// iretq를 이용한 유저 모드 진입
    /// 커널은 스택에 특정 값들을 쌓은 후 iretq를 실행하여
    /// CPU를 속여 Ring 3로 점프하게 함
    pub fn enterUserMode(state: UserState) void {
        // iretq는 다음 순서로 스택에서 값을 pop함:
        // 1. RIP (명령 포인터) - 유저 코드 진입점
        // 2. CS (코드 세그먼트) - Ring 3 코드 세그먼트
        // 3. RFLAGS (플래그) - CPU 상태
        // 4. RSP (스택 포인터) - 유저 스택
        // 5. SS (스택 세그먼트) - Ring 3 스택 세그먼트

        // 이를 통해 CPU는 자동으로 CPL(Current Privilege Level)을 3으로 설정
        // 그리고 Ring 3로 점프

        // 실제 구현은 어셈블리로 수행됨
        // 여기서는 개념적 표현
    }

    /// 유저 프로세스를 위한 초기 스택 구성
    pub fn setupUserStack(
        stack_addr: u64,
        entry_point: u64,
    ) UserState {
        const stack_top = stack_addr + UserStackSize;

        return UserState{
            .user_sp = stack_top,
            .user_ip = entry_point,
        };
    }
};

// ============================================================================
// 진정한 Syscall Handler (x86_64 컨벤션)
// ============================================================================

pub const SyscallHandlerX86_64 = struct {
    /// 시스템 호출 전달 규약 (Calling Convention)
    /// Linux x86_64:
    /// - RAX: 시스템 호출 번호
    /// - RDI, RSI, RDX, R10, R8, R9: 인수 (최대 6개)
    /// - RCX, R11: syscall에 의해 파괴됨
    /// - 반환값: RAX
    ///
    /// 중요: RCX와 R11은 syscall이 실행되면 파괴되므로
    /// 인수 4개(R10이 4번째)를 사용하는 규약

    pub const CallConvention = struct {
        // 인수 전달
        const arg_registers = [_][]const u8{ "rdi", "rsi", "rdx", "r10", "r8", "r9" };
        const result_register = "rax";
        const clobbered_registers = [_][]const u8{ "rcx", "r11" };

        pub fn getArgRegister(index: u32) ?[]const u8 {
            if (index >= arg_registers.len) return null;
            return arg_registers[index];
        }
    };

    /// 실제 syscall 핸들러 (어셈블리와 Zig 하이브리드)
    /// 이것은 CPU가 LSTAR MSR에 저장한 주소로 직접 점프
    pub fn handler() callconv(.Naked) void {
        // 의사 코드:
        // 1. 커널 스택으로 전환 (TSS.RSP0 사용)
        // 2. 레지스터 상태 저장 (iretq 용)
        // 3. 시스템 호출 번호(RAX) 확인
        // 4. 핸들러 함수 호출
        // 5. 결과를 RAX에 저장
        // 6. sysret으로 유저 모드 복귀
    }

    /// 포인터 검증을 위한 도우미
    pub fn validateUserPointerArgs(
        args: SyscallArgs,
        buf_index: u32,
        len_index: u32,
    ) bool {
        const validators = [_]?*u64{
            if (buf_index == 0) &args.rdi else null,
            if (buf_index == 1) &args.rsi else null,
            if (buf_index == 2) &args.rdx else null,
            if (buf_index == 3) &args.r10 else null,
            if (buf_index == 4) &args.r8 else null,
            if (buf_index == 5) &args.r9 else null,
        };

        if (validators[buf_index]) |ptr_ref| {
            const validator = PointerValidator{
                .user_space = UserMemorySpace{},
            };
            const len_sources = [_]?*u64{
                if (len_index == 0) &args.rdi else null,
                if (len_index == 1) &args.rsi else null,
                if (len_index == 2) &args.rdx else null,
                if (len_index == 3) &args.r10 else null,
                if (len_index == 4) &args.r8 else null,
                if (len_index == 5) &args.r9 else null,
            };

            if (len_sources[len_index]) |len_ref| {
                return validator.validateUserPointer(ptr_ref.*, @intCast(len_ref.*)) == .Valid;
            }
        }

        return false;
    }
};

// ============================================================================
// TSS와 Ring 0 ↔ Ring 3 전환
// ============================================================================

pub const PrivilegeTransition = struct {
    /// Task State Segment (TSS) - Ring 3 → Ring 0 스택 교체
    /// Lesson 3-5에서 배운 TSS를 활용하여 특권 수준 전환
    pub const TSS = struct {
        /// 예약
        reserved_0: u32 = 0,
        /// Ring 0 스택 포인터
        rsp0: u64,
        /// Ring 1 스택 포인터
        rsp1: u64 = 0,
        /// Ring 2 스택 포인터
        rsp2: u64 = 0,
        /// 예약
        reserved_1: u64 = 0,
        /// 인터럽트 스택 테이블 (IST)
        ist: [7]u64 = [_]u64{0} ** 7,
        /// 예약
        reserved_2: u16 = 0,
        /// I/O 맵 기본 주소
        iomap_base: u16 = 0,

        pub fn setKernelStackRing0(self: *TSS, sp: u64) void {
            self.rsp0 = sp;
        }
    };

    /// CPU 특권 수준 전환 시뮬레이션
    pub const PrivilegeLevelTransition = struct {
        /// 이전 특권 수준
        from_ring: Ring,
        /// 새로운 특권 수준
        to_ring: Ring,
        /// 인터럽트/예외로 인한 전환인지
        is_interrupt: bool,
        /// 이전 커널 스택 포인터 (복귀용)
        saved_kernel_sp: u64,
        /// 이전 유저 스택 포인터 (복귀용)
        saved_user_sp: u64,

        pub fn fromUserToKernel(user_sp: u64, kernel_sp: u64) PrivilegeLevelTransition {
            return PrivilegeLevelTransition{
                .from_ring = Ring.User,
                .to_ring = Ring.Kernel,
                .is_interrupt = false,
                .saved_kernel_sp = kernel_sp,
                .saved_user_sp = user_sp,
            };
        }

        pub fn fromKernelToUser(kernel_sp: u64, user_sp: u64) PrivilegeLevelTransition {
            return PrivilegeLevelTransition{
                .from_ring = Ring.Kernel,
                .to_ring = Ring.User,
                .is_interrupt = false,
                .saved_kernel_sp = kernel_sp,
                .saved_user_sp = user_sp,
            };
        }
    };
};

// ============================================================================
// VGA 터미널 헬퍼 (테스트용)
// ============================================================================

pub const VGATerminal = struct {
    cursor: u32 = 0,
    const Width = 80;
    const Height = 25;
    const Color = u8;
    const Black = 0;
    const Green = 2;

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
// 유저 프로세스 로더 (User Process Loader)
// ============================================================================

pub const UserProcessLoader = struct {
    /// 로드된 프로세스 정보
    pub const ProcessInfo = struct {
        /// 프로세스 ID
        pid: u32,
        /// 프로세스명
        name: [256]u8,
        name_len: u8,
        /// 진입점 주소
        entry_point: u64,
        /// 할당된 메모리 시작 주소
        mem_start: u64,
        /// 할당된 메모리 크기
        mem_size: u64,
        /// 상태 (0=Ready, 1=Running, 2=Blocked)
        state: u8,
    };

    /// 아주 작은 유저 프로세스 바이너리 로드
    /// (실제로는 ELF 파서가 필요하지만, 여기서는 간단히)
    pub fn loadUserProcess(
        name: []const u8,
        entry_point: u64,
    ) ProcessInfo {
        var info: ProcessInfo = undefined;
        info.pid = current_pid;
        current_pid += 1;

        @memcpy(info.name[0..name.len], name);
        info.name_len = @intCast(name.len);
        info.entry_point = entry_point;
        info.mem_start = 0x400000; // 유저 공간 시작
        info.mem_size = 0x1000; // 4KB
        info.state = 0; // Ready

        return info;
    }

    /// 프로세스 실행
    pub fn executeUserProcess(info: ProcessInfo) void {
        // TSS를 통해 커널 스택 설정
        // LSTAR를 syscall 핸들러로 설정
        // sysret을 이용해 유저 모드로 진입
    }
};

// ============================================================================
// 데이터 흐름 분석 (Data Flow Analysis)
// ============================================================================

pub const SyscallFlowAnalysis = struct {
    /// Syscall 요청부터 반환까지의 전체 과정
    pub const FlowSteps = [_][]const u8{
        "1. 유저 프로세스: syscall 명령어 실행",
        "2. CPU: LSTAR에서 커널 핸들러 주소 로드",
        "3. CPU: Ring 3 → Ring 0 권한 전환",
        "4. CPU: RCX=RIP, R11=RFLAGS 저장 (복귀용)",
        "5. CPU: 커널 GDT 로드 (CS, SS 자동 설정)",
        "6. 커널: 유저 스택에서 커널 스택으로 전환 (TSS.RSP0 사용)",
        "7. 커널: 레지스터 상태 전체 저장",
        "8. 커널: RAX 시스템 호출 번호 확인",
        "9. 커널: 인수 검증 (RDI, RSI, RDX, R10, R8, R9)",
        "10. 커널: 포인터 검증 (유저 메모리 범위 확인)",
        "11. 커널: Syscall Table에서 핸들러 조회",
        "12. 커널: 핸들러 함수 실행",
        "13. 커널: 결과를 RAX에 저장",
        "14. 커널: 레지스터 상태 복원",
        "15. CPU: sysret 명령어 실행",
        "16. CPU: Ring 0 → Ring 3 권한 복귀",
        "17. CPU: RCX → RIP, R11 → RFLAGS 복원",
        "18. CPU: 유저 스택 복원",
        "19. 유저 프로세스: 다음 명령어 실행",
    };

    pub fn printFlow() void {
        for (FlowSteps) |step| {
            _ = step; // 실제로는 printk로 출력
        }
    }
};

// ============================================================================
// 테스트 함수들
// ============================================================================

/// Test 1: 포인터 검증
fn testPointerValidation() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const validator = PointerValidator{
        .user_space = UserMemorySpace{},
    };

    // 유효한 포인터
    const valid = validator.validateUserPointer(0x400000, 256);
    std.fmt.format(fbs.writer(), "Valid pointer: {}\n", .{valid == .Valid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // 커널 메모리
    const kernel = validator.validateUserPointer(0xFFFF800000000000, 256);
    fbs.reset();
    std.fmt.format(fbs.writer(), "Kernel memory rejected: {}\n", .{kernel == .KernelMemory}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // Null 포인터
    const null_ptr = validator.validateUserPointer(0, 256);
    fbs.reset();
    std.fmt.format(fbs.writer(), "Null pointer rejected: {}\n", .{null_ptr == .NullPointer}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 2: Syscall Table 등록
fn testSyscallTableRegistration() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var table: SyscallTable = undefined;

    // 시스템 호출 등록
    const read_ok = table.register(0, &syscallRead);
    const write_ok = table.register(1, &syscallWrite);
    const exit_ok = table.register(60, &syscallExit);

    std.fmt.format(fbs.writer(), "Read registered: {}\n", .{read_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Write registered: {}\n", .{write_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Exit registered: {}\n", .{exit_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 3: Syscall 실행
fn testSyscallExecution() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var table: SyscallTable = undefined;
    _ = table.register(@intFromEnum(SyscallNumber.Write), &syscallWrite);
    _ = table.register(@intFromEnum(SyscallNumber.GetPid), &syscallGetPid);

    // write(1, buf, 5)
    var args: SyscallArgs = undefined;
    args.rax = 1; // write
    args.rdi = 1; // fd=stdout
    args.rsi = 0x400000; // buf
    args.rdx = 5; // count
    args.r10 = 0;
    args.r8 = 0;
    args.r9 = 0;

    const result = table.execute(args);
    std.fmt.format(fbs.writer(), "Write syscall returned: {}\n", .{result}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // getpid()
    fbs.reset();
    args.rax = 39;
    const pid = table.execute(args);
    std.fmt.format(fbs.writer(), "Current PID: {}\n", .{pid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 4: 유저 메모리 범위 검증
fn testUserMemoryRangeValidation() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const user_space = UserMemorySpace{};

    // 작은 범위 (유효)
    const small_ok = user_space.isRangeInUserSpace(0x400000, 256);
    std.fmt.format(fbs.writer(), "Small range valid: {}\n", .{small_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // 대용량 범위 (범위 초과)
    fbs.reset();
    const large_ok = user_space.isRangeInUserSpace(0x400000, 0x100000000);
    std.fmt.format(fbs.writer(), "Large range invalid: {}\n", .{!large_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // Overflow (음수)
    fbs.reset();
    const overflow_ok = user_space.isRangeInUserSpace(0xFFFFFFFFFFFFF000, 0x2000);
    std.fmt.format(fbs.writer(), "Overflow detected: {}\n", .{!overflow_ok}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 5: Ring 전환 시뮬레이션
fn testRingTransition() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const transition = PrivilegeTransition.PrivilegeLevelTransition.fromUserToKernel(0x500000, 0xFFFF800000010000);

    std.fmt.format(fbs.writer(), "Transition: Ring {} -> Ring {}\n", .{
        @intFromEnum(transition.from_ring),
        @intFromEnum(transition.to_ring),
    }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User SP: 0x{X:0>16}\n", .{transition.saved_user_sp}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Kernel SP: 0x{X:0>16}\n", .{transition.saved_kernel_sp}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 6: 유저 프로세스 로더
fn testUserProcessLoader() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const process = UserProcessLoader.loadUserProcess("init", 0x400000);

    std.fmt.format(fbs.writer(), "Process: {s}\n", .{process.name[0..process.name_len]}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "PID: {}\n", .{process.pid}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Entry: 0x{X:0>16}\n", .{process.entry_point}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Memory: 0x{X:0>16} ({}B)\n", .{ process.mem_start, process.mem_size }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 7: Syscall 호출 규약 검증
fn testSyscallCallingConvention() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const args = SyscallArgs{
        .rax = 1, // write
        .rdi = 1, // fd
        .rsi = 0x400000, // buf
        .rdx = 10, // count
        .r10 = 0,
        .r8 = 0,
        .r9 = 0,
    };

    std.fmt.format(fbs.writer(), "Syscall #: {}\n", .{args.rax}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Args: {} {} {}\n", .{ args.rdi, args.rsi, args.rdx }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 8: 보안 검증 - 유저 포인터 접근 제한
fn testSecurityValidation() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const validator = PointerValidator{
        .user_space = UserMemorySpace{},
    };

    // 유효한 버퍼
    if (validator.validateUserBuffer(0x400000, 100)) |_buf| {
        std.fmt.format(fbs.writer(), "User buffer accepted\n", .{}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    } else {
        std.fmt.format(fbs.writer(), "User buffer rejected\n", .{}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }

    // 커널 메모리 접근 시도
    fbs.reset();
    if (validator.validateUserBuffer(0xFFFF800000000000, 100)) |_buf| {
        std.fmt.format(fbs.writer(), "Kernel access allowed (BAD)\n", .{}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    } else {
        std.fmt.format(fbs.writer(), "Kernel access blocked (GOOD)\n", .{}) catch unreachable;
        terminal.writeString(buffer[0..fbs.pos]);
    }
}

/// Test 9: MSR (Model Specific Register) 설정 시뮬레이션
fn testMSRConfiguration() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    // LSTAR: Long Mode Syscall Target Address
    const LSTAR_MSR = 0xC0000082;
    const lstar_value: u64 = @intFromPtr(&SyscallHandlerX86_64.handler);

    std.fmt.format(fbs.writer(), "LSTAR MSR (0x{X:0>4}): 0x{X:0>16}\n", .{ LSTAR_MSR, lstar_value }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    // STAR: Segment Type And Register (CS/SS 지정)
    fbs.reset();
    const STAR_MSR = 0xC0000081;
    const star_value: u64 = (0x08 << 32) | 0x20; // Kernel CS | User CS
    std.fmt.format(fbs.writer(), "STAR MSR (0x{X:0>4}): 0x{X:0>16}\n", .{ STAR_MSR, star_value }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

/// Test 10: 유저 모드 진입 준비
fn testUserModeSetup() void {
    var terminal: VGATerminal = undefined;
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const state = UserModeEntry.setupUserStack(0x500000, 0x400000);

    std.fmt.format(fbs.writer(), "User Stack: 0x{X:0>16}\n", .{state.user_sp}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User IP: 0x{X:0>16}\n", .{state.user_ip}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User CS: 0x{X:0>4}\n", .{state.user_cs}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User SS: 0x{X:0>4}\n", .{state.user_ss}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

// ============================================================================
// 메인 실행 (테스트)
// ============================================================================

pub fn main() void {
    // Test execution
    testPointerValidation();
    testSyscallTableRegistration();
    testSyscallExecution();
    testUserMemoryRangeValidation();
    testRingTransition();
    testUserProcessLoader();
    testSyscallCallingConvention();
    testSecurityValidation();
    testMSRConfiguration();
    testUserModeSetup();
}
