// ============================================================================
// Lesson 3-4: 가상 메모리(Paging) 및 페이지 테이블 관리
// ============================================================================
//
// 핵심 개념:
// - 4단계 페이지 테이블 (PML4 → PDP → PD → PT)
// - 가상 주소와 물리 주소의 투명한 매핑
// - 페이지 테이블 엔트리(PTE)의 권한 관리
// - TLB 플러시를 통한 하드웨어 동기화
// - Higher Half Kernel 설계
//
// x86_64 주소 변환:
// 가상 주소 (64비트)
// [63..48: Sign-extended] [47..39: PML4 idx] [38..30: PDP idx]
// [29..21: PD idx] [20..12: PT idx] [11..0: 페이지 오프셋]
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 상수 정의
// ============================================================================

const PageSize = 4096;
const PageTableSize = 512; // 2^9
const PageTableCount = 4; // PML4, PDP, PD, PT

/// Higher Half Kernel 시작 주소
const HigherHalfKernelStart = 0xFFFFFFFF80000000;

/// 가상 메모리 인덱싱을 위한 비트 위치
const PML4Shift = 39;
const PDPShift = 30;
const PDShift = 21;
const PTShift = 12;
const PageOffsetMask = 0xFFF;

// ============================================================================
// 페이지 테이블 엔트리 (PTE) 구조
// ============================================================================

/// x86_64 페이지 테이블 엔트리 (64비트)
pub const PageTableEntry = packed struct {
    /// 비트 0: 페이지가 물리 메모리에 존재하는가?
    present: u1 = 0,

    /// 비트 1: 쓰기 가능한가? (0=읽기 전용)
    writeable: u1 = 0,

    /// 비트 2: 유저 모드(Ring 3)에서 접근 가능한가? (0=커널만)
    user: u1 = 0,

    /// 비트 3: 라이트-스루 캐싱 (0=라이트-백)
    write_through: u1 = 0,

    /// 비트 4: 캐시 비활성화
    cache_disable: u1 = 0,

    /// 비트 5: CPU가 이 페이지에 접근했는가? (자동 설정)
    accessed: u1 = 0,

    /// 비트 6: CPU가 이 페이지에 쓰기했는가? (자동 설정)
    dirty: u1 = 0,

    /// 비트 7: 큰 페이지(2MB 또는 1GB) 사용
    huge_page: u1 = 0,

    /// 비트 8: TLB 플러시 없이 모든 컨텍스트에서 유효 (전역 페이지)
    global: u1 = 0,

    /// 비트 9-11: 소프트웨어 사용 (OS가 자유롭게 사용)
    available: u3 = 0,

    /// 비트 12-51: 물리 주소 (40비트, 4KB 정렬)
    /// 총 52비트 주소 공간을 지원 (4PB)
    physical_address: u40 = 0,

    /// 비트 52-62: 예약됨 (0으로 설정)
    reserved: u11 = 0,

    /// 비트 63: No-Execute (NX) - 1이면 이 페이지 실행 불가
    no_execute: u1 = 0,

    // 생성자
    pub fn init() PageTableEntry {
        return .{};
    }

    pub fn withPhysicalAddress(self: PageTableEntry, address: u64) PageTableEntry {
        var result = self;
        result.physical_address = @intCast((address >> 12) & 0x0FFFFFFFFFFFFF);
        return result;
    }

    pub fn withFlags(self: PageTableEntry, flags: u64) PageTableEntry {
        var result = self;
        result.present = if ((flags & 0x001) != 0) 1 else 0;
        result.writeable = if ((flags & 0x002) != 0) 1 else 0;
        result.user = if ((flags & 0x004) != 0) 1 else 0;
        result.write_through = if ((flags & 0x008) != 0) 1 else 0;
        result.cache_disable = if ((flags & 0x010) != 0) 1 else 0;
        result.global = if ((flags & 0x100) != 0) 1 else 0;
        result.no_execute = if ((flags & 0x8000000000000000) != 0) 1 else 0;
        return result;
    }

    pub fn getPhysicalAddress(self: PageTableEntry) u64 {
        return @as(u64, self.physical_address) << 12;
    }

    pub fn getFlags(self: PageTableEntry) u64 {
        var flags: u64 = 0;
        if (self.present != 0) flags |= 0x001;
        if (self.writeable != 0) flags |= 0x002;
        if (self.user != 0) flags |= 0x004;
        if (self.write_through != 0) flags |= 0x008;
        if (self.cache_disable != 0) flags |= 0x010;
        if (self.global != 0) flags |= 0x100;
        if (self.no_execute != 0) flags |= 0x8000000000000000;
        return flags;
    }
};

// PTE 플래그 상수
pub const PageTableFlags = struct {
    pub const Present = 0x001;
    pub const Writeable = 0x002;
    pub const User = 0x004;
    pub const WriteThrough = 0x008;
    pub const CacheDisable = 0x010;
    pub const Global = 0x100;
    pub const NoExecute = 0x8000000000000000;

    // 일반적인 조합
    pub const KernelCode = Present | Global; // 읽기/실행만
    pub const KernelData = Present | Writeable | Global;
    pub const KernelStack = Present | Writeable | Global | NoExecute;
    pub const UserCode = Present | User;
    pub const UserData = Present | Writeable | User;
    pub const UserStack = Present | Writeable | User | NoExecute;
};

// ============================================================================
// 페이지 테이블 구조
// ============================================================================

/// 4KB 정렬된 페이지 테이블 (512개 엔트리)
pub const PageTable = struct {
    entries: [PageTableSize]PageTableEntry align(PageSize) = undefined,

    pub fn init() PageTable {
        var table: PageTable = undefined;
        for (0..PageTableSize) |i| {
            table.entries[i] = PageTableEntry.init();
        }
        return table;
    }

    pub fn clear(self: *PageTable) void {
        for (0..PageTableSize) |i| {
            self.entries[i] = PageTableEntry.init();
        }
    }

    pub fn getPhysicalAddress(self: *PageTable) u64 {
        return @intFromPtr(self);
    }
};

// ============================================================================
// 가상 메모리 매니저
// ============================================================================

pub const VirtualMemoryManager = struct {
    /// PML4 (최상위 페이지 테이블)
    pml4: *PageTable = undefined,

    /// PDP 테이블들 (512개 가능, 실제로는 필요한 만큼만 할당)
    pdp_tables: [512]?*PageTable = [_]?*PageTable{null} ** 512,

    /// PD 테이블들 (512*512 가능)
    pd_tables: [512 * 512]?*PageTable = [_]?*PageTable{null} ** (512 * 512),

    /// PT 테이블들 (512*512*512 가능)
    pt_tables: [512 * 512 * 512]?*PageTable = [_]?*PageTable{null} ** (512 * 512 * 512),

    /// 초기화 플래그
    initialized: bool = false,

    /// 매핑된 페이지 수
    mapped_pages: u64 = 0,

    /// 메모리 관리자 초기화
    pub fn init(self: *VirtualMemoryManager) !void {
        // PML4 할당 (실제로는 PMM에서 할당해야 함)
        self.pml4 = &pml4_table;
        self.pml4.clear();

        self.initialized = true;
    }

    /// 가상 주소를 인덱스로 변환
    fn getTableIndices(virtual_address: u64) [4]u9 {
        return [4]u9{
            @intCast((virtual_address >> PML4Shift) & 0x1FF),
            @intCast((virtual_address >> PDPShift) & 0x1FF),
            @intCast((virtual_address >> PDShift) & 0x1FF),
            @intCast((virtual_address >> PTShift) & 0x1FF),
        };
    }

    /// 가상 주소에서 오프셋 추출
    fn getPageOffset(virtual_address: u64) u12 {
        return @intCast(virtual_address & PageOffsetMask);
    }

    /// 주소 매핑: 가상 → 물리
    pub fn mapAddress(
        self: *VirtualMemoryManager,
        virtual_address: u64,
        physical_address: u64,
        flags: u64,
    ) !void {
        if (!self.initialized) {
            return error.NotInitialized;
        }

        const indices = self.getTableIndices(virtual_address);
        const pml4_idx = indices[0];
        const pdp_idx = indices[1];
        const pd_idx = indices[2];
        const pt_idx = indices[3];

        // PML4 엔트리 가져오기 또는 생성
        var pml4_entry = &self.pml4.entries[pml4_idx];
        if (pml4_entry.present == 0) {
            // PDP 테이블 할당 (실제로는 PMM 사용)
            const pdp = &pdp_tables[pml4_idx];
            pdp.clear();
            pml4_entry.* = PageTableEntry.init()
                .withPhysicalAddress(@intFromPtr(pdp))
                .withFlags(PageTableFlags.Present | PageTableFlags.Writeable | PageTableFlags.Global);
            self.pdp_tables[pml4_idx] = pdp;
        }

        // PDP 테이블 접근
        const pdp = self.pdp_tables[pml4_idx].?;
        var pdp_entry = &pdp.entries[pdp_idx];
        if (pdp_entry.present == 0) {
            const pd_table_idx = pml4_idx * 512 + pdp_idx;
            const pd = &pd_tables[pd_table_idx];
            pd.clear();
            pdp_entry.* = PageTableEntry.init()
                .withPhysicalAddress(@intFromPtr(pd))
                .withFlags(PageTableFlags.Present | PageTableFlags.Writeable | PageTableFlags.Global);
            self.pd_tables[pd_table_idx] = pd;
        }

        // PD 테이블 접근
        const pd_table_idx = pml4_idx * 512 + pdp_idx;
        const pd = self.pd_tables[pd_table_idx].?;
        var pd_entry = &pd.entries[pd_idx];
        if (pd_entry.present == 0) {
            const pt_table_idx = (pml4_idx * 512 + pdp_idx) * 512 + pd_idx;
            const pt = &pt_tables[pt_table_idx];
            pt.clear();
            pd_entry.* = PageTableEntry.init()
                .withPhysicalAddress(@intFromPtr(pt))
                .withFlags(PageTableFlags.Present | PageTableFlags.Writeable | PageTableFlags.Global);
            self.pt_tables[pt_table_idx] = pt;
        }

        // PT 테이블 접근 및 매핑
        const pt_table_idx = (pml4_idx * 512 + pdp_idx) * 512 + pd_idx;
        const pt = self.pt_tables[pt_table_idx].?;
        var pt_entry = &pt.entries[pt_idx];
        pt_entry.* = PageTableEntry.init()
            .withPhysicalAddress(physical_address)
            .withFlags(flags);

        self.mapped_pages += 1;

        // TLB 플러시
        self.invalidateTLB(virtual_address);
    }

    /// 주소 언매핑
    pub fn unmapAddress(self: *VirtualMemoryManager, virtual_address: u64) !void {
        if (!self.initialized) {
            return error.NotInitialized;
        }

        const indices = self.getTableIndices(virtual_address);
        const pml4_idx = indices[0];
        const pdp_idx = indices[1];
        const pd_idx = indices[2];
        const pt_idx = indices[3];

        if (self.pdp_tables[pml4_idx]) |pdp| {
            if (pdp.entries[pdp_idx].present != 0) {
                const pd_table_idx = pml4_idx * 512 + pdp_idx;
                if (self.pd_tables[pd_table_idx]) |pd| {
                    if (pd.entries[pd_idx].present != 0) {
                        const pt_table_idx = (pml4_idx * 512 + pdp_idx) * 512 + pd_idx;
                        if (self.pt_tables[pt_table_idx]) |pt| {
                            if (pt.entries[pt_idx].present != 0) {
                                pt.entries[pt_idx] = PageTableEntry.init();
                                self.mapped_pages -= 1;
                                self.invalidateTLB(virtual_address);
                                return;
                            }
                        }
                    }
                }
            }
        }

        return error.AddressNotMapped;
    }

    /// 물리 주소 조회
    pub fn getPhysicalAddress(self: VirtualMemoryManager, virtual_address: u64) !u64 {
        const indices = self.getTableIndices(virtual_address);
        const pml4_idx = indices[0];
        const pdp_idx = indices[1];
        const pd_idx = indices[2];
        const pt_idx = indices[3];

        if (self.pdp_tables[pml4_idx]) |pdp| {
            if (pdp.entries[pdp_idx].present != 0) {
                const pd_table_idx = pml4_idx * 512 + pdp_idx;
                if (self.pd_tables[pd_table_idx]) |pd| {
                    if (pd.entries[pd_idx].present != 0) {
                        const pt_table_idx = (pml4_idx * 512 + pdp_idx) * 512 + pd_idx;
                        if (self.pt_tables[pt_table_idx]) |pt| {
                            if (pt.entries[pt_idx].present != 0) {
                                const page_offset = self.getPageOffset(virtual_address);
                                const physical_page = pt.entries[pt_idx].getPhysicalAddress();
                                return physical_page | page_offset;
                            }
                        }
                    }
                }
            }
        }

        return error.PageNotPresent;
    }

    /// TLB 플러시 - 특정 주소의 캐시 무효화
    pub fn invalidateTLB(self: VirtualMemoryManager, virtual_address: u64) void {
        // 실제로는 invlpg 어셈블리 명령 사용
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (virtual_address),
        );
    }

    /// 전체 TLB 플러시 - CR3 재로드
    pub fn invalidateAllTLB(self: VirtualMemoryManager) void {
        // CR3 읽기
        var cr3: u64 = undefined;
        asm volatile ("movq %%cr3, %[cr3]"
            : [cr3] "=r" (cr3),
        );

        // CR3 쓰기 (같은 값을 다시 쓰면 TLB 전체 플러시)
        asm volatile ("movq %[cr3], %%cr3"
            :
            : [cr3] "r" (cr3),
        );
    }

    /// 매핑된 페이지 수 조회
    pub fn getMappedPageCount(self: VirtualMemoryManager) u64 {
        return self.mapped_pages;
    }
};

// 전역 페이지 테이블 (static, 링커 스크립트에서 정렬)
var pml4_table: PageTable = undefined;
var pdp_tables: [512]PageTable = undefined;
var pd_tables: [512 * 512]PageTable = undefined;
var pt_tables: [512 * 512 * 512]PageTable = undefined;

// ============================================================================
// 페이지 폴트 분석 (Page Fault Error Code)
// ============================================================================

pub const PageFaultError = struct {
    /// 에러 코드 (CR2와 함께 제공됨)
    error_code: u32 = 0,

    /// 비트 0: 페이지가 존재하지 않음 (0) 또는 권한 위반 (1)
    pub fn isProtectionViolation(self: PageFaultError) bool {
        return (self.error_code & 0x01) != 0;
    }

    /// 비트 1: 쓰기 작업 (0=읽기, 1=쓰기)
    pub fn isWrite(self: PageFaultError) bool {
        return (self.error_code & 0x02) != 0;
    }

    /// 비트 2: 유저 모드 (0=커널, 1=유저)
    pub fn isUserMode(self: PageFaultError) bool {
        return (self.error_code & 0x04) != 0;
    }

    /// 비트 3: 예약된 비트 위반
    pub fn isReservedBitViolation(self: PageFaultError) bool {
        return (self.error_code & 0x08) != 0;
    }

    /// 비트 4: 명령 페치 (1GiB 페이지에서 실행 시도)
    pub fn isInstructionFetch(self: PageFaultError) bool {
        return (self.error_code & 0x10) != 0;
    }
};

// ============================================================================
// 주소 계산 유틸리티
// ============================================================================

pub const AddressCalculation = struct {
    /// 4단계 인덱스 계산 및 해석
    pub fn calculateIndices(virtual_address: u64) struct {
        pml4_idx: u9,
        pdp_idx: u9,
        pd_idx: u9,
        pt_idx: u9,
        offset: u12,
    } {
        return .{
            .pml4_idx = @intCast((virtual_address >> 39) & 0x1FF),
            .pdp_idx = @intCast((virtual_address >> 30) & 0x1FF),
            .pd_idx = @intCast((virtual_address >> 21) & 0x1FF),
            .pt_idx = @intCast((virtual_address >> 12) & 0x1FF),
            .offset = @intCast(virtual_address & 0xFFF),
        };
    }

    /// 재귀적 매핑 (Recursive Mapping) 설명
    /// PML4의 마지막 엔트리가 PML4 자신을 가리키도록 하면,
    /// 가상 주소 0xFFFFFFFFFFFFE000 이상에서 페이지 테이블을 직접 접근 가능
    pub fn getRecursiveMapVirtualAddress(
        pml4_idx: u9,
        pdp_idx: u9,
        pd_idx: u9,
        pt_idx: u9,
    ) u64 {
        return 0xFFFFFFFFFFFF0000 |
            (@as(u64, pml4_idx) << 39) |
            (@as(u64, pdp_idx) << 30) |
            (@as(u64, pd_idx) << 21) |
            (@as(u64, pt_idx) << 12);
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
                .foreground = @intFromEnum(VGAColor.light_cyan),
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
};

// ============================================================================
// 테스트 함수
// ============================================================================

pub fn testAddressCalculation() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 1: Address Index Calculation ===\n");

    // Assignment 3-4: 0x00007FFFFFFFF000의 인덱스 계산
    const virtual_addr: u64 = 0x00007FFFFFFFF000;
    const indices = AddressCalculation.calculateIndices(virtual_addr);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Virtual: 0x{X}\n", .{virtual_addr}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "PML4 idx: {}\n", .{indices.pml4_idx}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "PDP idx: {}\n", .{indices.pdp_idx}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "PD idx: {}\n", .{indices.pd_idx}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "PT idx: {}\n", .{indices.pt_idx}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Offset: 0x{X}\n", .{indices.offset}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageTableEntry() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 2: Page Table Entry Flags ===\n");

    // 커널 코드: 읽기/실행만
    var kernel_code = PageTableEntry.init()
        .withPhysicalAddress(0x100000)
        .withFlags(PageTableFlags.KernelCode);

    // 유저 스택: 읽기/쓰기, No-Execute
    var user_stack = PageTableEntry.init()
        .withPhysicalAddress(0x7FFFF000)
        .withFlags(PageTableFlags.UserStack);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Kernel code - Present: {}\n", .{kernel_code.present}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Kernel code - NX: {}\n", .{kernel_code.no_execute}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User stack - Present: {}\n", .{user_stack.present}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User stack - NX: {}\n", .{user_stack.no_execute}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testVirtualMemoryManager() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 3: Virtual Memory Manager ===\n");

    var vmm: VirtualMemoryManager = .{};
    try vmm.init();

    // 매핑 테스트
    try vmm.mapAddress(0x1000, 0x100000, PageTableFlags.KernelData);
    try vmm.mapAddress(0x2000, 0x101000, PageTableFlags.KernelData);

    const phys1 = try vmm.getPhysicalAddress(0x1000);
    const phys2 = try vmm.getPhysicalAddress(0x2000);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Mapped pages: {}\n", .{vmm.getMappedPageCount()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Virtual 0x1000 -> 0x{X}\n", .{phys1}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Virtual 0x2000 -> 0x{X}\n", .{phys2}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageTableAlignment() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 4: Page Table Alignment ===\n");

    const table = PageTable.init();
    const addr = @intFromPtr(&table);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "PageTable addr: 0x{X}\n", .{addr}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Aligned to 4KB: {}\n", .{addr % PageSize == 0}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageFaultAnalysis() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 5: Page Fault Error Code ===\n");

    // 시뮬레이션: 유저 모드에서 쓰기 시도 (권한 위반)
    const pf_error: PageFaultError = .{ .error_code = 0x07 };

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Error code: 0x{X}\n", .{pf_error.error_code}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Protection violation: {}\n", .{pf_error.isProtectionViolation()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Is write: {}\n", .{pf_error.isWrite()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User mode: {}\n", .{pf_error.isUserMode()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testRecursiveMapping() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 6: Recursive Mapping Analysis ===\n");

    const pml4_idx: u9 = 256;
    const pdp_idx: u9 = 100;
    const pd_idx: u9 = 50;
    const pt_idx: u9 = 25;

    const recursive_vaddr = AddressCalculation.getRecursiveMapVirtualAddress(
        pml4_idx,
        pdp_idx,
        pd_idx,
        pt_idx,
    );

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Recursive vaddr: 0x{X}\n", .{recursive_vaddr}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("PML4의 마지막 엔트리가 PML4 자신을 가리킬 때\n");
    terminal.writeString("페이지 테이블을 직접 수정 가능\n");
}

pub fn testHigherHalfKernel() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 7: Higher Half Kernel ===\n");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Kernel start: 0x{X}\n", .{HigherHalfKernelStart}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User space: 0x0 ~ 0x{X}\n", .{HigherHalfKernelStart - 1}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("모든 프로세스에서 동일한 커널 주소\n");
}

pub fn testMultipleMappings() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 8: Multiple Mappings ===\n");

    var vmm: VirtualMemoryManager = .{};
    try vmm.init();

    // 연속된 가상 주소를 다양한 물리 주소로 매핑
    for (0..10) |i| {
        const virt = 0x1000 + (i * PageSize);
        const phys = 0x100000 + (i * PageSize);
        try vmm.mapAddress(virt, phys, PageTableFlags.KernelData);
    }

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Mapped {} pages\n", .{vmm.getMappedPageCount()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testUnmapping() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 9: Unmapping ===\n");

    var vmm: VirtualMemoryManager = .{};
    try vmm.init();

    try vmm.mapAddress(0x1000, 0x100000, PageTableFlags.KernelData);
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Mapped pages: {}\n", .{vmm.getMappedPageCount()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    try vmm.unmapAddress(0x1000);

    fbs.reset();
    std.fmt.format(fbs.writer(), "After unmap: {}\n", .{vmm.getMappedPageCount()}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPermissionDesign() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 10: Permission Design ===\n");

    // 커널 코드: RX (읽기/실행)
    const kernel_code = PageTableEntry.init()
        .withPhysicalAddress(0x100000)
        .withFlags(PageTableFlags.KernelCode);

    // 커널 데이터: RW (읽기/쓰기)
    const kernel_data = PageTableEntry.init()
        .withPhysicalAddress(0x200000)
        .withFlags(PageTableFlags.KernelData);

    // 커널 스택: RW, NX (읽기/쓰기, 실행 불가)
    const kernel_stack = PageTableEntry.init()
        .withPhysicalAddress(0x300000)
        .withFlags(PageTableFlags.KernelStack);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Code - W:{}, NX:{}\n", .{ kernel_code.writeable, kernel_code.no_execute }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Data - W:{}, NX:{}\n", .{ kernel_data.writeable, kernel_data.no_execute }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Stack - W:{}, NX:{}\n", .{ kernel_stack.writeable, kernel_stack.no_execute }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

// ============================================================================
// 메인 진입점
// ============================================================================

pub export fn _start() noreturn {
    var terminal: VGATerminal = .{};
    terminal.clear();

    // 헤더
    terminal.writeString("╔═════════════════════════════════════════════╗\n");
    terminal.writeString("║ Lesson 3-4: Virtual Memory & Paging        ║\n");
    terminal.writeString("║    4-Level Page Table (x86_64)             ║\n");
    terminal.writeString("╚═════════════════════════════════════════════╝\n\n");

    // 메모리 계층 정보
    terminal.writeString("📊 Virtual Memory Architecture:\n");
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    std.fmt.format(fbs.writer(), "  Page Size: {}KB\n", .{PageSize / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Page Table Entries: {}\n", .{PageTableSize}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Levels: PML4 → PDP → PD → PT\n", .{}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Higher Half Kernel: 0x{X}\n", .{HigherHalfKernelStart}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("\n🧪 Running Tests...\n\n");

    // 테스트 실행
    testAddressCalculation();
    terminal.writeString("\n");

    testPageTableEntry();
    terminal.writeString("\n");

    testVirtualMemoryManager() catch |err| {
        terminal.writeString("ERROR: Test 3 failed\n");
    };
    terminal.writeString("\n");

    testPageTableAlignment();
    terminal.writeString("\n");

    testPageFaultAnalysis();
    terminal.writeString("\n");

    testRecursiveMapping();
    terminal.writeString("\n");

    testHigherHalfKernel();
    terminal.writeString("\n");

    testMultipleMappings() catch |err| {
        terminal.writeString("ERROR: Test 8 failed\n");
    };
    terminal.writeString("\n");

    testUnmapping() catch |err| {
        terminal.writeString("ERROR: Test 9 failed\n");
    };
    terminal.writeString("\n");

    testPermissionDesign();
    terminal.writeString("\n");

    terminal.writeString("═════════════════════════════════════════════\n");
    terminal.writeString("✅ Assignment 3-4: Virtual Memory Complete!\n");
    terminal.writeString("기록이 증명이다 - Paging Ready!\n");
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
