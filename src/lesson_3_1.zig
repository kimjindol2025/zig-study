// ============================================================================
// 🎓 Zig 전공 301: Lesson 3-1
// 베어 메탈(Bare Metal) 입문 - 부트 로더와 커널 진입
// ============================================================================
//
// 학습 목표:
// 1. Freestanding 환경 이해 (OS 없이 하드웨어 위에서 직접 실행)
// 2. 커널 진입점 (_start 심볼) 설계
// 3. VGA 텍스트 버퍼에 직접 접근하여 화면 출력
// 4. 링커 스크립트 개념 이해
// 5. Inline Assembly를 통한 CPU 제어
// 6. 메모리 레이아웃 설계 (부트스트랩)
// 7. Panic 핸들러 구현
// 8. 부팅 로깅 시스템 구현
//
// 핵심 철학:
// "세상의 시작은 어두움에서이다."
// OS가 없는 환경에서, 우리는 직접 하드웨어를 깨우고 제어해야 한다.
// 이것이 컴퓨터 과학의 진정한 기초이며, 모든 추상화의 근본이다.
// ============================================================================

// Freestanding 환경: std 라이브러리의 제한된 사용
const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 섹션 1: VGA 텍스트 버퍼 인터페이스
// ============================================================================

/// VGA 텍스트 모드의 컬러 정의 (16색)
pub const VGAColor = enum(u4) {
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

/// 16비트 VGA 문자 (색상 + 문자)
pub const VGAEntry = packed struct(u16) {
    ascii: u8,
    foreground: VGAColor,
    background: VGAColor,
    blink: bool,
};

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_BUFFER = 0xB8000;

/// VGA 텍스트 버퍼 제어 구조체
pub const VGATerminal = struct {
    buffer: [*]volatile VGAEntry,
    cursor_x: u8 = 0,
    cursor_y: u8 = 0,
    current_color: u8,

    pub fn init(foreground: VGAColor, background: VGAColor) VGATerminal {
        const color: u8 = @intFromEnum(background) << 4 | @intFromEnum(foreground);
        return VGATerminal{
            .buffer = @as([*]volatile VGAEntry, @ptrFromInt(VGA_BUFFER)),
            .current_color = color,
        };
    }

    pub fn putChar(self: *VGATerminal, char: u8) void {
        if (char == '\n') {
            self.cursor_x = 0;
            self.cursor_y += 1;
            if (self.cursor_y >= VGA_HEIGHT) {
                self.cursor_y = 0;
            }
            return;
        }

        const index = self.cursor_y * VGA_WIDTH + self.cursor_x;
        const fg = @intFromEnum(VGAColor.white);
        const bg = @intFromEnum(VGAColor.black);
        const color_attr = (bg << 4) | fg;

        self.buffer[index] = VGAEntry{
            .ascii = char,
            .foreground = @as(VGAColor, @enumFromInt(color_attr & 0x0F)),
            .background = @as(VGAColor, @enumFromInt((color_attr >> 4) & 0x0F)),
            .blink = false,
        };

        self.cursor_x += 1;
        if (self.cursor_x >= VGA_WIDTH) {
            self.cursor_x = 0;
            self.cursor_y += 1;
            if (self.cursor_y >= VGA_HEIGHT) {
                self.cursor_y = 0;
            }
        }
    }

    pub fn writeString(self: *VGATerminal, str: []const u8) void {
        for (str) |char| {
            self.putChar(char);
        }
    }

    pub fn clear(self: *VGATerminal) void {
        for (0..VGA_HEIGHT * VGA_WIDTH) |i| {
            self.buffer[i] = VGAEntry{
                .ascii = ' ',
                .foreground = VGAColor.white,
                .background = VGAColor.black,
                .blink = false,
            };
        }
        self.cursor_x = 0;
        self.cursor_y = 0;
    }
};

// ============================================================================
// 섹션 2: 부팅 정보 (Boot Information)
// ============================================================================

pub const BootInfo = struct {
    bootloader_name: []const u8,
    kernel_entry_point: u64,
    memory_size_mb: u32,
    boot_time_ms: u64,

    pub fn format(self: *const BootInfo) [256]u8 {
        var buf: [256]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "BootInfo{{loader={s}, entry=0x{x}, mem={}MB, time={}ms}}", .{
            self.bootloader_name,
            self.kernel_entry_point,
            self.memory_size_mb,
            self.boot_time_ms,
        }) catch |err| {
            _ = err;
            @memset(&buf, 0);
        };
        return buf;
    }
};

// ============================================================================
// 섹션 3: CPU 제어 (Inline Assembly)
// ============================================================================

/// CPU의 현재 상태를 읽는다
pub fn getCPUID() u32 {
    var eax: u32 = undefined;
    asm volatile (
        \\movl $1, %%eax
        \\cpuid
        : [result] "={eax}" (eax),
    );
    return eax;
}

/// CPU를 할트(정지)시킨다
pub fn cpuHalt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

/// 인터럽트를 비활성화한다
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

/// 인터럽트를 활성화한다
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

// ============================================================================
// 섹션 4: 메모리 레이아웃
// ============================================================================

pub const MemoryLayout = struct {
    kernel_start: u64 = 0x100000, // 1MB
    kernel_end: u64 = 0,
    heap_start: u64 = 0,
    heap_size: u64 = 0x100000, // 1MB

    pub fn init() MemoryLayout {
        return MemoryLayout{
            .kernel_end = 0x200000,
            .heap_start = 0x200000,
        };
    }

    pub fn kernelSize(self: *const MemoryLayout) u64 {
        return self.kernel_end - self.kernel_start;
    }
};

// ============================================================================
// 섹션 5: 부팅 로거
// ============================================================================

pub const BootLogger = struct {
    terminal: *VGATerminal,
    boot_time_ms: u64 = 0,

    pub fn init(terminal: *VGATerminal) BootLogger {
        return BootLogger{
            .terminal = terminal,
        };
    }

    pub fn logInfo(self: *BootLogger, msg: []const u8) void {
        self.terminal.writeString("[INFO] ");
        self.terminal.writeString(msg);
        self.terminal.putChar('\n');
    }

    pub fn logOk(self: *BootLogger, msg: []const u8) void {
        self.terminal.writeString("[OK] ");
        self.terminal.writeString(msg);
        self.terminal.putChar('\n');
    }

    pub fn logError(self: *BootLogger, msg: []const u8) void {
        self.terminal.writeString("[ERROR] ");
        self.terminal.writeString(msg);
        self.terminal.putChar('\n');
    }
};

// ============================================================================
// 섹션 6: 링커 스크립트 상수 (Linker Script Constants)
// ============================================================================

extern const kernel_start: u8;
extern const kernel_end: u8;
extern const _start: fn () noreturn;

// ============================================================================
// 섹션 7: 메인 커널 코드
// ============================================================================

var terminal: VGATerminal = undefined;
var logger: BootLogger = undefined;

/// 커널의 진입점 (링커가 찾는 심볼)
/// 부트로더에서 CPU가 이 주소로 점프한다.
export fn _start() noreturn {
    // 인터럽트 비활성화
    disableInterrupts();

    // VGA 터미널 초기화
    terminal = VGATerminal.init(VGAColor.white, VGAColor.black);
    terminal.clear();

    // 부팅 로거 초기화
    logger = BootLogger.init(&terminal);

    // 부팅 메시지
    logger.logInfo("Zig Kernel Booting...");
    logger.logInfo("Welcome to Bare Metal World");

    // Assignment 3-1: 이니셜 출력
    logger.logOk("Initializing VGA Terminal");
    terminal.putChar('\n');
    terminal.writeString("╔════════════════════════════════════════╗\n");
    terminal.writeString("║  Z I G   K E R N E L   3 - 1           ║\n");
    terminal.writeString("║  Bare Metal Boot Loader Entry Point    ║\n");
    terminal.writeString("║  CPU: x86_64 | Architecture: 64-bit   ║\n");
    terminal.writeString("╚════════════════════════════════════════╝\n");
    terminal.putChar('\n');

    // CPU 정보 출력
    logger.logInfo("Reading CPU Information");
    const cpuid = getCPUID();
    terminal.writeString("CPU CPUID: 0x");
    _ = cpuid; // CPU ID 읽기 완료
    logger.logOk("CPU Detection Complete");

    // 메모리 레이아웃 정보
    logger.logInfo("Memory Layout Configuration");
    var mem_layout = MemoryLayout.init();
    terminal.writeString("  Kernel Start: 0x100000\n");
    terminal.writeString("  Kernel End: 0x200000\n");
    terminal.writeString("  Kernel Size: ");
    var size_str: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&size_str, "0x{x}", .{mem_layout.kernelSize()}) catch unreachable;
    const len = std.mem.indexOfScalar(u8, &size_str, 0) orelse size_str.len;
    terminal.writeString(size_str[0..len]);
    terminal.writeString(" bytes\n");

    // 부팅 정보
    logger.logInfo("Boot Information");
    const boot_info = BootInfo{
        .bootloader_name = "Zig Bootloader v1.0",
        .kernel_entry_point = @intFromPtr(&_start),
        .memory_size_mb = 512,
        .boot_time_ms = 42,
    };
    var boot_str = boot_info.format();
    const boot_len = std.mem.indexOfScalar(u8, &boot_str, 0) orelse boot_str.len;
    terminal.writeString(boot_str[0..boot_len]);
    terminal.putChar('\n');

    // 부팅 완료
    logger.logOk("Kernel Initialization Complete");
    logger.logOk("System Ready - Waiting for Interrupts");
    terminal.putChar('\n');
    terminal.writeString("기록이 증명이다 - 커널이 켜졌습니다\n");

    // CPU를 할트 (무한 대기)
    cpuHalt();
}

// ============================================================================
// 섹션 8: Panic 핸들러 (런타임 오류 처리)
// ============================================================================

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    terminal.writeString("\n");
    terminal.writeString("╔═══════════════════════════════════════╗\n");
    terminal.writeString("║  KERNEL PANIC                         ║\n");
    terminal.writeString("╚═══════════════════════════════════════╝\n");
    terminal.writeString("Error: ");
    terminal.writeString(msg);
    terminal.putChar('\n');

    cpuHalt();
}

// ============================================================================
// 섹션 9: Assignment 3-1 분석 및 테스트
// ============================================================================

/// main 함수와 _start 함수의 차이 분석
pub const BootAnalysis = struct {
    pub const main_description =
        \\main 함수:
        \\- OS가 제공하는 런타임에 의해 호출됨
        \\- 표준 라이브러리가 초기화 코드를 실행한 후 호출
        \\- argc, argv 인자를 받을 수 있음
        \\- 반환값을 OS에 전달 (exit code)
        \\- 메모리, 파일 디스크립터 등이 이미 준비됨
        \\- 일반 프로그램 작성에 사용
    ;

    pub const start_description =
        \\_start 함수:
        \\- 부트로더가 CPU를 이 주소로 직접 점프
        \\- 어떤 초기화 코드도 먼저 실행되지 않음 (완전히 맨바닥)
        \\- noreturn: 절대 반환하지 않음 (OS는 끝나지 않음)
        \\- 매개변수 없음: 모든 정보를 CPU 레지스터에서 읽어야 함
        \\- 링커 스크립트에서 ENTRY(_start)로 명시
        \\- 커널, OS, 부트로더 코드 작성에 사용
    ;

    pub const syscall_analysis =
        \\시스템 호출(Syscall) 관점의 분석:
        \\
        \\[일반 프로그램]
        \\  User Application (main)
        \\        ↓ syscall (e.g., write, open)
        \\  Kernel Layer (OS가 제공)
        \\        ↓
        \\  Hardware
        \\
        \\[Bare Metal Kernel]
        \\  Kernel Code (_start)
        \\        ↓ CPU 명령어 (직접 하드웨어 제어)
        \\  Hardware Registers/Memory
        \\        ↓
        \\  (반환 불가능 - 커널은 영구적으로 실행)
        \\
        \\핵심 차이:
        \\- main: 사용자 공간 → syscall 게이트 → 커널 공간
        \\- _start: 커널 공간에서 직접 시작 (중개자 없음)
        \\- main: OS가 리소스 관리
        \\- _start: 커널이 자신의 리소스를 직접 관리
    ;
};

// ============================================================================
// 테스트 (Freestanding 환경에서는 제한적)
// ============================================================================

pub fn testVGAEntry() void {
    // VGA 엔트리 구조체 크기 확인 (정확히 16비트여야 함)
    const entry_size = @sizeOf(VGAEntry);
    if (entry_size != 2) {
        @panic("VGAEntry must be exactly 16 bits");
    }
}

pub fn testBootLayout() void {
    var layout = MemoryLayout.init();
    if (layout.kernel_start != 0x100000) {
        @panic("Kernel start address must be 0x100000");
    }
    if (layout.kernelSize() != 0x100000) {
        @panic("Kernel size must be 0x100000");
    }
}

pub fn testColorValues() void {
    const white = @intFromEnum(VGAColor.white);
    const black = @intFromEnum(VGAColor.black);

    if (white != 15) {
        @panic("White color value must be 15");
    }
    if (black != 0) {
        @panic("Black color value must be 0");
    }
}

pub fn runAllTests() void {
    testVGAEntry();
    testBootLayout();
    testColorValues();
}
