// ============================================================================
// 🎓 Zig 전공 301: Lesson 3-2
// 시스템 보호와 이벤트 처리 - GDT 및 IDT 설계
// ============================================================================
//
// 학습 목표:
// 1. GDT (Global Descriptor Table) - 메모리 보호 설계
// 2. IDT (Interrupt Descriptor Table) - 이벤트 처리 설계
// 3. ISR (Interrupt Service Routine) - 핸들러 함수 작성
// 4. 예외(Exceptions) 처리
// 5. 하드웨어 포트 I/O (inb, outb)
// 6. CPU 권한 체계 (Ring 0/3)
// 7. 인터럽트 보호 메커니즘
// 8. 레지스터 상태 보존
//
// 핵심 철학:
// "대화의 시작은 이해에서이다."
// 하드웨어와 소프트웨어가 대화하려면, 명확한 규칙과 표(Table)가 필요하다.
// GDT와 IDT는 그 규칙을 정의하는 설계도이다.
// ============================================================================

const std = @import("std");

// ============================================================================
// 섹션 1: GDT (Global Descriptor Table) 설계
// ============================================================================

/// GDT 엔트리 (8바이트)
pub const GdtEntry = packed struct(u64) {
    limit_low: u16,           // 0-15: 세그먼트 크기 (낮은 16비트)
    base_low: u16,            // 16-31: 기본 주소 (낮은 16비트)
    base_mid: u8,             // 32-39: 기본 주소 (중간 8비트)
    access: u8,               // 40-47: 액세스 바이트 (권한 정보)
    limit_high_flags: u4,     // 48-51: 크기 (높은 4비트) + 플래그
    flags: u4,                // 52-55: 추가 플래그
    base_high: u8,            // 56-63: 기본 주소 (높은 8비트)

    pub fn init(base: u32, limit: u32, access: u8) GdtEntry {
        return GdtEntry{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .base_mid = @truncate(base >> 16),
            .access = access,
            .limit_high_flags = @truncate(limit >> 16),
            .flags = 0b1100, // 32-bit, 4KB pages
            .base_high = @truncate(base >> 24),
        };
    }
};

/// GDT 레지스터 (GDTR)
pub const GdtRegister = packed struct {
    limit: u16,
    base: u32,
} align(1);

const GDT_SIZE = 3; // null, code, data

/// GDT 초기화
pub var gdt: [GDT_SIZE]GdtEntry = undefined;

pub fn initializeGdt() void {
    // 0번: Null descriptor (필수)
    gdt[0] = @bitCast(@as(u64, 0));

    // 1번: Code segment (Ring 0)
    // Access byte: 10011010 = Present(1) + DPL(00) + Type(1) + Executable(1) + DC(0) + RW(1) + AC(0)
    gdt[1] = GdtEntry.init(0, 0xFFFFF, 0b10011010);

    // 2번: Data segment (Ring 0)
    // Access byte: 10010010 = Present(1) + DPL(00) + Type(1) + Executable(0) + DC(0) + RW(1) + AC(0)
    gdt[2] = GdtEntry.init(0, 0xFFFFF, 0b10010010);

    // GDTR에 GDT 등록
    const gdtr = GdtRegister{
        .limit = (GDT_SIZE * 8) - 1,
        .base = @intFromPtr(&gdt[0]),
    };

    // GDTR을 CPU에 로드
    loadGdt(&gdtr);
}

/// 어셈블리로 GDTR 로드
pub fn loadGdt(gdtr: *const GdtRegister) void {
    asm volatile (
        \\lgdt (%[gdtr])
        :
        : [gdtr] "r" (gdtr),
    );
}

// ============================================================================
// 섹션 2: IDT (Interrupt Descriptor Table) 설계
// ============================================================================

/// IDT 엔트리 (16바이트)
pub const IdtEntry = packed struct(u128) {
    offset_low: u16,          // 0-15: 핸들러 함수 주소 (낮은 16비트)
    selector: u16,            // 16-31: 코드 세그먼트 선택자
    ist: u8,                  // 32-39: Interrupt Stack Table (64-bit 모드)
    type_attributes: u8,      // 40-47: 타입 및 속성
    offset_mid: u16,          // 48-63: 핸들러 주소 (중간 16비트)
    offset_high: u32,         // 64-95: 핸들러 주소 (높은 32비트)
    zero: u32,                // 96-127: 예약 (0으로 채움)

    pub fn init(handler: u64, selector: u16, type_attr: u8) IdtEntry {
        return IdtEntry{
            .offset_low = @truncate(handler),
            .selector = selector,
            .ist = 0,
            .type_attributes = type_attr,
            .offset_mid = @truncate(handler >> 16),
            .offset_high = @truncate(handler >> 32),
            .zero = 0,
        };
    }
};

/// IDT 레지스터 (IDTR)
pub const IdtRegister = packed struct {
    limit: u16,
    base: u32,
} align(1);

const IDT_SIZE = 256;

/// IDT 테이블
pub var idt: [IDT_SIZE]IdtEntry align(16) = undefined;

pub fn initializeIdt() void {
    // 모든 항목을 0으로 초기화
    for (0..IDT_SIZE) |i| {
        idt[i] = @bitCast(@as(u128, 0));
    }

    // 0번: Division by Zero Exception
    idt[0] = IdtEntry.init(
        @intFromPtr(&divisionByZeroHandler),
        0x08, // Code segment selector
        0x8E  // Type: Interrupt Gate, Present
    );

    // 14번: Page Fault Exception
    idt[14] = IdtEntry.init(
        @intFromPtr(&pageFaultHandler),
        0x08,
        0x8E
    );

    // IDTR에 IDT 등록
    const idtr = IdtRegister{
        .limit = (IDT_SIZE * 16) - 1,
        .base = @intFromPtr(&idt[0]),
    };

    loadIdt(&idtr);
}

/// 어셈블리로 IDTR 로드
pub fn loadIdt(idtr: *const IdtRegister) void {
    asm volatile (
        \\lidt (%[idtr])
        :
        : [idtr] "r" (idtr),
    );
}

// ============================================================================
// 섹션 3: CPU 상태 레지스터 (Register State)
// ============================================================================

pub const CpuState = struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    rsp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,

    pub fn format(self: *const CpuState) [512]u8 {
        var buf: [512]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "CPU State{{rax=0x{x:0>16}, rbx=0x{x:0>16}, rcx=0x{x:0>16}, rdx=0x{x:0>16}}}", .{
            self.rax, self.rbx, self.rcx, self.rdx
        }) catch unreachable;
        return buf;
    }
};

// ============================================================================
// 섹션 4: 하드웨어 포트 I/O (Port I/O)
// ============================================================================

/// 포트에서 1바이트 읽기
pub fn inb(port: u16) u8 {
    var result: u8 = undefined;
    asm volatile (
        \\inb %[port], %[result]
        : [result] "={al}" (result),
        : [port] "N{dx}" (port),
    );
    return result;
}

/// 포트에 1바이트 쓰기
pub fn outb(port: u16, data: u8) void {
    asm volatile (
        \\outb %[data], %[port]
        :
        : [data] "{al}" (data),
          [port] "{dx}" (port),
    );
}

/// PIC (Programmable Interrupt Controller) EOI (End Of Interrupt) 전송
pub fn sendEoi(interrupt_number: u8) void {
    if (interrupt_number >= 40) {
        // 슬레이브 PIC (IRQ 8-15)
        outb(0xA0, 0x20);
    }
    // 마스터 PIC (IRQ 0-7)
    outb(0x20, 0x20);
}

// ============================================================================
// 섹션 5: ISR (Interrupt Service Routine) - 핸들러 함수
// ============================================================================

// VGA 터미널 참조 (Lesson 3-1에서 정의)
var terminal_buffer: [*]volatile u16 = @ptrFromInt(0xB8000);

pub fn writeError(msg: []const u8) void {
    for (msg, 0..) |char, i| {
        terminal_buffer[80 + i] = @as(u16, 0x0F00) | char; // 밝은 흰색 배경
    }
}

/// 0번 인터럽트: Division by Zero Exception
pub fn divisionByZeroHandler() callconv(.Interrupt) void {
    writeError("EXCEPTION: Division by Zero");
    while (true) {
        asm volatile ("hlt");
    }
}

/// 14번 인터럽트: Page Fault Exception
pub fn pageFaultHandler() callconv(.Interrupt) void {
    writeError("EXCEPTION: Page Fault");
    while (true) {
        asm volatile ("hlt");
    }
}

/// 키보드 인터럽트 핸들러 (선택사항)
pub fn keyboardHandler() callconv(.Interrupt) void {
    // 키보드 컨트롤러(Port 0x60)에서 데이터 읽기
    const scancode = inb(0x60);

    // 스캔코드를 ASCII로 변환하는 로직 (간단한 예)
    var ascii: u8 = 0;
    if (scancode < 0x3B) {
        const keymap = "1234567890-=\x08\t" ++ // 0-13
                      "qwertyuiop[]\n\x00" ++ // 14-27
                      "asdfghjkl;'`\x00\\" ++ // 28-41
                      "zxcvbnm,./\x00*\x00 ";  // 42-57
        if (scancode < keymap.len) {
            ascii = keymap[scancode];
        }
    }

    // EOI 전송
    sendEoi(1);
}

// ============================================================================
// 섹션 6: 시스템 초기화
// ============================================================================

pub fn initializeSystem() void {
    // GDT 초기화
    initializeGdt();

    // IDT 초기화
    initializeIdt();

    // 인터럽트 활성화
    enableInterrupts();
}

pub fn enableInterrupts() void {
    asm volatile ("sti");
}

pub fn disableInterrupts() void {
    asm volatile ("cli");
}

// ============================================================================
// 섹션 7: 테스트 및 검증
// ============================================================================

pub const SystemInfo = struct {
    gdt_base: u32,
    gdt_size: u16,
    idt_base: u32,
    idt_size: u16,
    cpu_protection_enabled: bool,

    pub fn format(self: *const SystemInfo) [256]u8 {
        var buf: [256]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "System{{gdt=0x{x}, idt=0x{x}, protection={}}}", .{
            self.gdt_base,
            self.idt_base,
            self.cpu_protection_enabled
        }) catch unreachable;
        return buf;
    }
};

pub fn getSystemInfo() SystemInfo {
    return SystemInfo{
        .gdt_base = @intFromPtr(&gdt[0]),
        .gdt_size = (GDT_SIZE * 8) - 1,
        .idt_base = @intFromPtr(&idt[0]),
        .idt_size = (IDT_SIZE * 16) - 1,
        .cpu_protection_enabled = true,
    };
}

// ============================================================================
// 섹션 8: Assignment 3-2 - 메인 커널 코드
// ============================================================================

export fn kernelMain() noreturn {
    disableInterrupts();

    // VGA 터미널에 메시지 출력
    terminal_buffer[0] = @as(u16, 0x0F00) | 'G';
    terminal_buffer[1] = @as(u16, 0x0F00) | 'D';
    terminal_buffer[2] = @as(u16, 0x0F00) | 'T';
    terminal_buffer[3] = @as(u16, 0x0F00) | ' ';
    terminal_buffer[4] = @as(u16, 0x0F00) | '&';
    terminal_buffer[5] = @as(u16, 0x0F00) | ' ';
    terminal_buffer[6] = @as(u16, 0x0F00) | 'I';
    terminal_buffer[7] = @as(u16, 0x0F00) | 'D';
    terminal_buffer[8] = @as(u16, 0x0F00) | 'T';

    // 시스템 초기화
    initializeSystem();

    // 시스템 정보 출력
    const sys_info = getSystemInfo();
    var sys_str = sys_info.format();
    const sys_len = std.mem.indexOfScalar(u8, &sys_str, 0) orelse sys_str.len;
    for (sys_str[0..sys_len], 0..) |char, i| {
        terminal_buffer[160 + i] = @as(u16, 0x0F00) | char;
    }

    // Assignment 3-2: Division by Zero 테스트 (주석 처리됨)
    // var a: i32 = 0;
    // _ = 10 / a;  // 이 줄이 실행되면 0번 인터럽트 발생

    // CPU 할트
    while (true) {
        asm volatile ("hlt");
    }
}

// ============================================================================
// 섹션 9: GDT/IDT 분석
// ============================================================================

pub const ProtectionAnalysis = struct {
    pub const gdt_explanation =
        \\GDT (Global Descriptor Table):
        \\- CPU에게 메모리 세그먼트의 범위와 권한을 알려주는 테이블
        \\- 각 엔트리는 8바이트 (64비트)
        \\- 엔트리 0: Null descriptor (필수)
        \\- 엔트리 1: Code segment (Ring 0 - Kernel)
        \\- 엔트리 2: Data segment (Ring 0 - Kernel)
        \\- 엔트리 3+: User segments, TSS 등
        \\
        \\Access Byte (권한 정보):
        \\- Bit 7: Present (1 = 존재)
        \\- Bits 6-5: DPL (Descriptor Privilege Level: 0=Kernel, 3=User)
        \\- Bit 4: Type (1=Code/Data, 0=System)
        \\- Bit 3: Executable (1=Code, 0=Data)
        \\- Bit 2: Direction/Conforming
        \\- Bit 1: Readable/Writable
        \\- Bit 0: Accessed
    ;

    pub const idt_explanation =
        \\IDT (Interrupt Descriptor Table):
        \\- CPU가 인터럽트 발생 시 호출할 핸들러 함수의 주소를 담는 테이블
        \\- 256개 엔트리 (0-255번 인터럽트)
        \\- 각 엔트리는 16바이트 (128비트)
        \\
        \\인터럽트 분류:
        \\- 0-31: CPU Exception (0: Div by 0, 14: Page Fault 등)
        \\- 32-47: Hardware Interrupt (IRQ 0-15)
        \\- 48-255: Software Interrupt & User-defined
        \\
        \\IDT Entry 구조:
        \\- Offset (64-bit): 핸들러 함수의 주소
        \\- Selector (16-bit): 코드 세그먼트 선택자
        \\- IST (8-bit): Interrupt Stack Table (64-bit 모드)
        \\- Type Attributes (8-bit): Gate type (Interrupt=0xE, Trap=0xF)
    ;

    pub const cpu_interrupt_process =
        \\CPU 인터럽트 처리 프로세스:
        \\
        \\1. 인터럽트 발생
        \\   - 하드웨어: 키보드, 타이머 등
        \\   - 소프트웨어: int 0x80 명령어
        \\   - 예외: Division by Zero, Page Fault 등
        \\
        \\2. CPU가 인터럽트 벡터로 IDT 인덱싱
        \\   - IDT 엔트리 검색
        \\   - Selector에서 코드 세그먼트 획득
        \\
        \\3. 레지스터 상태 자동 저장 (스택에 푸시)
        \\   - 64-bit 모드에서:
        \\   - RSP (스택 포인터)
        \\   - SS (스택 세그먼트)
        \\   - RFLAGS (플래그)
        \\   - RIP (다음 명령어 주소)
        \\   - CS (코드 세그먼트)
        \\
        \\4. 핸들러 함수 호출
        \\   - RIP가 IDT Entry의 offset으로 설정
        \\   - ISR (Interrupt Service Routine) 실행
        \\
        \\5. 인터럽트 처리 완료
        \\   - EOI (End Of Interrupt) 신호 전송
        \\   - iret 명령어로 원래 상태로 복원
    ;
};

// ============================================================================
// 테스트 함수
// ============================================================================

pub fn testGdtEntry() void {
    const entry = GdtEntry.init(0, 0xFFFFF, 0b10011010);
    if (entry.limit_low != 0xFFFF) {
        @panic("GDT entry limit_low failed");
    }
}

pub fn testIdtEntry() void {
    const handler_addr = @intFromPtr(&divisionByZeroHandler);
    const entry = IdtEntry.init(handler_addr, 0x08, 0x8E);
    if (entry.selector != 0x08) {
        @panic("IDT entry selector failed");
    }
}

pub fn testPortIO() void {
    // 포트 I/O 함수가 컴파일되는지 확인
    // 실제 포트 읽기/쓰기는 사용하지 않음 (시뮬레이션)
    _ = inb;
    _ = outb;
}

pub fn runAllTests() void {
    testGdtEntry();
    testIdtEntry();
    testPortIO();
}
