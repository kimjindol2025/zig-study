// ============================================================================
// Lesson 3-3: 물리 메모리 관리자(PMM) 및 비트맵 설계
// ============================================================================
//
// 핵심 개념:
// - 비트맵(Bitmap) 알고리즘을 사용한 효율적인 페이지 관리
// - u64 배열로 64개 페이지를 1개 단위로 처리
// - @ctz (Count Trailing Zeros)를 사용한 빠른 빈 페이지 검색
// - 메모리 정렬(Alignment) 강제로 하드웨어 규격 준수
// - 메모리 맵(Memory Map) 읽기 및 초기화
//
// 메모리 효율성:
// - 32GB RAM 관리 = 1MB 비트맵 메모리만 필요
// - 128MB RAM 관리 = 4KB 비트맵 메모리
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 상수 정의
// ============================================================================

/// 페이지 크기 (4KB) - 현대 x86_64 아키텍처 표준
const PageSize = 4096;

/// 128MB 메모리 관리
const TotalMemory = 128 * 1024 * 1024; // 128 MB

/// 128MB를 4KB 페이지로 나누면?
/// 128 * 1024 * 1024 / 4096 = 32,768개 페이지
const TotalPages = TotalMemory / PageSize; // 32,768

/// u64 배열 크기: 32,768 / 64 = 512개 (4KB)
const BitmapSize = (TotalPages + 63) / 64; // 512

// ============================================================================
// 메모리 맵 구조체 (BIOS/UEFI가 제공하는 메모리 정보)
// ============================================================================

/// 메모리 영역 타입
pub const MemoryType = enum(u32) {
    Usable = 1,
    Reserved = 2,
    ACPIReclaimable = 3,
    ACPINVSMemory = 4,
    BadMemory = 5,
};

/// 메모리 맵 엔트리
pub const MemoryMapEntry = struct {
    base_address: u64,
    length: u64,
    memory_type: MemoryType,

    pub fn end(self: MemoryMapEntry) u64 {
        return self.base_address + self.length;
    }

    pub fn pageStart(self: MemoryMapEntry) u64 {
        return self.base_address / PageSize;
    }

    pub fn pageEnd(self: MemoryMapEntry) u64 {
        return (self.end() + PageSize - 1) / PageSize;
    }

    pub fn pageCount(self: MemoryMapEntry) u64 {
        return self.pageEnd() - self.pageStart();
    }
};

/// 메모리 맵
pub const MemoryMap = struct {
    entries: [32]MemoryMapEntry = undefined,
    entry_count: usize = 0,

    pub fn add(self: *MemoryMap, entry: MemoryMapEntry) !void {
        if (self.entry_count >= self.entries.len) {
            return error.OutOfSpace;
        }
        self.entries[self.entry_count] = entry;
        self.entry_count += 1;
    }

    pub fn isUsable(self: MemoryMap, page_index: u64) bool {
        const address = page_index * PageSize;
        for (self.entries[0..self.entry_count]) |entry| {
            if (address >= entry.base_address and address < entry.end()) {
                return entry.memory_type == .Usable;
            }
        }
        return false;
    }
};

// ============================================================================
// 물리 메모리 관리자 (PMM, Physical Memory Manager)
// ============================================================================

pub const MemoryManager = struct {
    /// 비트맵 배열 - 각 비트는 1개 페이지를 나타냄
    /// 1 = 사용 중, 0 = 비어 있음
    bitmap: [BitmapSize]u64 align(PageSize) = undefined,

    /// 총 관리 가능한 페이지 수
    total_pages: u64 = TotalPages,

    /// 현재 사용 중인 페이지 수
    used_pages: u64 = 0,

    /// 메모리 맵 (BIOS/UEFI에서 제공)
    memory_map: MemoryMap = .{},

    /// 초기화 플래그
    initialized: bool = false,

    /// 메모리 관리자 초기화
    pub fn init(self: *MemoryManager, memory_map: ?MemoryMap) !void {
        // 비트맵 초기화 (모두 0 = 모두 비어 있음)
        for (self.bitmap[0..]) |*entry| {
            entry.* = 0;
        }

        self.used_pages = 0;
        self.total_pages = TotalPages;

        if (memory_map) |map| {
            self.memory_map = map;
            // 사용 불가능한 영역을 비트맵에 표시
            try self.markUnavailableRegions();
        }

        self.initialized = true;
    }

    /// 사용 불가능한 메모리 영역을 비트맵에 표시
    fn markUnavailableRegions(self: *MemoryManager) !void {
        for (self.memory_map.entries[0..self.memory_map.entry_count]) |entry| {
            if (entry.memory_type != .Usable) {
                var page_idx = entry.pageStart();
                while (page_idx < entry.pageEnd()) : (page_idx += 1) {
                    try self.setPageUsed(page_idx);
                }
            }
        }
    }

    /// 특정 페이지가 사용 중인지 확인
    pub fn isUsed(self: MemoryManager, page_index: u64) bool {
        if (page_index >= TotalPages) return true;

        const bit_idx = page_index % 64;
        const array_idx = page_index / 64;

        return (self.bitmap[array_idx] & (@as(u64, 1) << @intCast(bit_idx))) != 0;
    }

    /// 특정 페이지를 사용 중으로 표시
    pub fn setPageUsed(self: *MemoryManager, page_index: u64) !void {
        if (page_index >= TotalPages) {
            return error.PageOutOfBounds;
        }

        const bit_idx = page_index % 64;
        const array_idx = page_index / 64;

        const was_free = !self.isUsed(page_index);
        self.bitmap[array_idx] |= (@as(u64, 1) << @intCast(bit_idx));

        if (was_free) {
            self.used_pages += 1;
        }
    }

    /// 특정 페이지를 사용 가능으로 표시
    pub fn setPageFree(self: *MemoryManager, page_index: u64) !void {
        if (page_index >= TotalPages) {
            return error.PageOutOfBounds;
        }

        const bit_idx = page_index % 64;
        const array_idx = page_index / 64;

        const was_used = self.isUsed(page_index);
        self.bitmap[array_idx] &= ~(@as(u64, 1) << @intCast(bit_idx));

        if (was_used) {
            self.used_pages -= 1;
        }
    }

    /// 단일 빈 페이지 할당 (First-fit 알고리즘)
    /// @ctz (Count Trailing Zeros)를 사용하여 빠르게 빈 비트 찾기
    pub fn allocPage(self: *MemoryManager) !u64 {
        for (self.bitmap[0..], 0..) |*entry, array_idx| {
            // 모든 비트가 사용 중이면 skip
            if (entry.* != 0xFFFFFFFFFFFFFFFF) {
                // 첫 번째 0 비트를 찾음
                const bit_idx = @ctz(~entry.*);
                const page_idx = array_idx * 64 + bit_idx;

                if (page_idx >= TotalPages) {
                    return error.OutOfMemory;
                }

                entry.* |= (@as(u64, 1) << @intCast(bit_idx));
                self.used_pages += 1;

                return page_idx;
            }
        }

        return error.OutOfMemory;
    }

    /// 단일 페이지 해제 (Free)
    pub fn freePage(self: *MemoryManager, page_index: u64) !void {
        try self.setPageFree(page_index);
    }

    /// 연속된 여러 페이지 할당
    pub fn allocPages(self: *MemoryManager, count: u64) !u64 {
        if (count == 0) {
            return error.InvalidCount;
        }

        var consecutive_free: u64 = 0;
        var start_page: u64 = 0;

        for (0..TotalPages) |page_idx| {
            if (!self.isUsed(page_idx)) {
                if (consecutive_free == 0) {
                    start_page = page_idx;
                }
                consecutive_free += 1;

                if (consecutive_free == count) {
                    // 할당할 수 있는 연속 공간을 찾았음
                    for (start_page..start_page + count) |idx| {
                        try self.setPageUsed(idx);
                    }
                    return start_page;
                }
            } else {
                consecutive_free = 0;
            }
        }

        return error.OutOfMemory;
    }

    /// 연속된 여러 페이지 해제
    pub fn freePages(self: *MemoryManager, start_page: u64, count: u64) !void {
        if (count == 0) {
            return error.InvalidCount;
        }

        if (start_page + count > TotalPages) {
            return error.PageOutOfBounds;
        }

        for (start_page..start_page + count) |page_idx| {
            try self.setPageFree(page_idx);
        }
    }

    /// 메모리 상태 정보
    pub fn getStats(self: MemoryManager) MemoryStats {
        return .{
            .total_pages = self.total_pages,
            .used_pages = self.used_pages,
            .free_pages = self.total_pages - self.used_pages,
            .used_memory_bytes = self.used_pages * PageSize,
            .free_memory_bytes = (self.total_pages - self.used_pages) * PageSize,
        };
    }

    /// 메모리 사용률 계산 (백분율)
    pub fn getUsagePercent(self: MemoryManager) f32 {
        if (self.total_pages == 0) return 0.0;
        return @as(f32, @floatFromInt(self.used_pages)) * 100.0 / @as(f32, @floatFromInt(self.total_pages));
    }

    /// 다음 할당 가능한 페이지 찾기 (정보 제공용)
    pub fn findFreePageIndex(self: MemoryManager) ?u64 {
        for (0..TotalPages) |page_idx| {
            if (!self.isUsed(page_idx)) {
                return page_idx;
            }
        }
        return null;
    }

    /// 연속된 빈 페이지의 최대 개수 찾기
    pub fn findMaxConsecutivePages(self: MemoryManager) u64 {
        var max_consecutive: u64 = 0;
        var current_consecutive: u64 = 0;

        for (0..TotalPages) |page_idx| {
            if (!self.isUsed(page_idx)) {
                current_consecutive += 1;
                max_consecutive = @max(max_consecutive, current_consecutive);
            } else {
                current_consecutive = 0;
            }
        }

        return max_consecutive;
    }
};

/// 메모리 통계
pub const MemoryStats = struct {
    total_pages: u64,
    used_pages: u64,
    free_pages: u64,
    used_memory_bytes: u64,
    free_memory_bytes: u64,
};

// ============================================================================
// 페이지 주소 변환 유틸리티
// ============================================================================

pub const PageAddress = struct {
    /// 물리 주소를 페이지 인덱스로 변환
    pub fn physicalToPageIndex(address: u64) u64 {
        return address / PageSize;
    }

    /// 페이지 인덱스를 물리 주소로 변환
    pub fn pageIndexToPhysical(page_index: u64) u64 {
        return page_index * PageSize;
    }

    /// 정렬된 주소인지 확인 (4KB 경계)
    pub fn isAligned(address: u64) bool {
        return address % PageSize == 0;
    }

    /// 주소를 페이지 경계에 정렬 (올림)
    pub fn alignUp(address: u64) u64 {
        return ((address + PageSize - 1) / PageSize) * PageSize;
    }

    /// 주소를 페이지 경계에 정렬 (내림)
    pub fn alignDown(address: u64) u64 {
        return (address / PageSize) * PageSize;
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
};

// ============================================================================
// 테스트 함수
// ============================================================================

pub fn testBitmapSize() !void {
    var terminal: VGATerminal = .{};
    terminal.clear();

    terminal.writeString("=== Test 1: Bitmap Size Calculation ===\n");

    // 비트맵 크기 계산
    const pages_128mb = 128 * 1024 * 1024 / PageSize;
    const bitmap_entries = (pages_128mb + 63) / 64;
    const bitmap_bytes = bitmap_entries * 8;

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "128MB pages: {}\n", .{pages_128mb});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Bitmap entries (u64): {}\n", .{bitmap_entries});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Bitmap bytes: {}\n", .{bitmap_bytes});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageAllocation() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 2: Single Page Allocation ===\n");

    const page1 = try mm.allocPage();
    const page2 = try mm.allocPage();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Allocated page: {}\n", .{page1});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Allocated page: {}\n", .{page2});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageFreeing() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 3: Page Freeing ===\n");

    const page = try mm.allocPage();
    try mm.freePage(page);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Freed page: {}\n", .{page});
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("Allocation after free: ");
    const page_new = try mm.allocPage();
    fbs.reset();
    try std.fmt.format(fbs.writer(), "{}\n", .{page_new});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testConsecutivePages() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 4: Consecutive Pages Allocation ===\n");

    const start_page = try mm.allocPages(16);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Start page (16 pages): {}\n", .{start_page});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testMemoryStats() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 5: Memory Statistics ===\n");

    const stats = mm.getStats();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Total pages: {}\n", .{stats.total_pages});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Used pages: {}\n", .{stats.used_pages});
    terminal.writeString(buffer[0..fbs.pos]);

    // 할당해서 통계 업데이트
    _ = try mm.allocPage();
    const stats2 = mm.getStats();

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Used after alloc: {}\n", .{stats2.used_pages});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPageAddressConversion() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 6: Page Address Conversion ===\n");

    const address1: u64 = 0x100000;
    const page_idx = PageAddress.physicalToPageIndex(address1);
    const address2 = PageAddress.pageIndexToPhysical(page_idx);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Address: 0x{X}\n", .{address1});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Page index: {}\n", .{page_idx});
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "Back to address: 0x{X}\n", .{address2});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testMemoryMapInitialization() !void {
    var terminal: VGATerminal = .{};
    var map: MemoryMap = .{};

    try map.add(.{
        .base_address = 0x0,
        .length = 0x100000,
        .memory_type = .Reserved,
    });

    try map.add(.{
        .base_address = 0x100000,
        .length = 128 * 1024 * 1024,
        .memory_type = .Usable,
    });

    var mm: MemoryManager = .{};
    try mm.init(map);

    terminal.writeString("=== Test 7: Memory Map Initialization ===\n");
    terminal.writeString("Memory map initialized with 2 entries\n");
}

pub fn testMultipleAllocations() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 8: Multiple Allocations ===\n");

    var pages: [5]u64 = undefined;
    for (0..5) |i| {
        pages[i] = try mm.allocPage();
    }

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Allocated 5 pages\n", .{});
    terminal.writeString(buffer[0..fbs.pos]);

    const stats3 = mm.getStats();
    fbs.reset();
    try std.fmt.format(fbs.writer(), "Used pages: {}\n", .{stats3.used_pages});
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testAlignmentCheck() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 9: Alignment Check ===\n");

    const addr1: u64 = 0x1000;
    const addr2: u64 = 0x1001;

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "0x{X} aligned: {}\n", .{ addr1, PageAddress.isAligned(addr1) });
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    try std.fmt.format(fbs.writer(), "0x{X} aligned: {}\n", .{ addr2, PageAddress.isAligned(addr2) });
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testMaxConsecutivePages() !void {
    var terminal: VGATerminal = .{};
    var mm: MemoryManager = .{};

    try mm.init(null);

    terminal.writeString("=== Test 10: Max Consecutive Pages ===\n");

    const max_consecutive = mm.findMaxConsecutivePages();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.fmt.format(fbs.writer(), "Max consecutive: {}\n", .{max_consecutive});
    terminal.writeString(buffer[0..fbs.pos]);
}

// ============================================================================
// 메인 진입점
// ============================================================================

pub export fn _start() noreturn {
    var terminal: VGATerminal = .{};
    terminal.clear();

    // 헤더
    terminal.writeString("╔═══════════════════════════════════════════╗\n");
    terminal.writeString("║ Lesson 3-3: Physical Memory Manager (PMM) ║\n");
    terminal.writeString("║     Bitmap-based Page Management          ║\n");
    terminal.writeString("╚═══════════════════════════════════════════╝\n\n");

    // 비트맵 크기 정보
    terminal.writeString("📊 Memory Configuration:\n");
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    std.fmt.format(fbs.writer(), "  Total Memory: {}MB\n", .{TotalMemory / 1024 / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Page Size: {}KB\n", .{PageSize / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Total Pages: {}\n", .{TotalPages}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Bitmap Entries: {}\n", .{BitmapSize}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Bitmap Size: {}KB\n", .{BitmapSize * 8 / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("\n🧪 Running Tests...\n\n");

    // 테스트 실행
    testBitmapSize() catch |err| {
        terminal.writeString("ERROR: Test 1 failed\n");
    };
    terminal.writeString("\n");

    testPageAllocation() catch |err| {
        terminal.writeString("ERROR: Test 2 failed\n");
    };
    terminal.writeString("\n");

    testPageFreeing() catch |err| {
        terminal.writeString("ERROR: Test 3 failed\n");
    };
    terminal.writeString("\n");

    testConsecutivePages() catch |err| {
        terminal.writeString("ERROR: Test 4 failed\n");
    };
    terminal.writeString("\n");

    testMemoryStats() catch |err| {
        terminal.writeString("ERROR: Test 5 failed\n");
    };
    terminal.writeString("\n");

    testPageAddressConversion() catch |err| {
        terminal.writeString("ERROR: Test 6 failed\n");
    };
    terminal.writeString("\n");

    testMemoryMapInitialization() catch |err| {
        terminal.writeString("ERROR: Test 7 failed\n");
    };
    terminal.writeString("\n");

    testMultipleAllocations() catch |err| {
        terminal.writeString("ERROR: Test 8 failed\n");
    };
    terminal.writeString("\n");

    testAlignmentCheck() catch |err| {
        terminal.writeString("ERROR: Test 9 failed\n");
    };
    terminal.writeString("\n");

    testMaxConsecutivePages() catch |err| {
        terminal.writeString("ERROR: Test 10 failed\n");
    };
    terminal.writeString("\n");

    terminal.writeString("═══════════════════════════════════════════\n");
    terminal.writeString("✅ Assignment 3-3: Memory Bitmap Complete!\n");
    terminal.writeString("기록이 증명이다 - Memory Management Ready!\n");
    terminal.writeString("═══════════════════════════════════════════\n");

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
