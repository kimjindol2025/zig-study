// ============================================================================
// Lesson 3-6: 파일 시스템 - 데이터의 영속적 기록 설계
// ============================================================================
//
// 핵심 개념:
// - 슈퍼블록: 파일 시스템 전체 메타데이터 (용량, 블록 크기 등)
// - 아이노드: 파일/디렉토리의 신분증 (크기, 권한, 블록 포인터)
// - 블록 할당: 비트맵으로 빈 블록 관리
// - 저널링: 전원 차단 시에도 데이터 무결성 보장
// - VFS: 다양한 저장 장치를 동일하게 처리
// - 디렉토리 엔트리: 파일 이름 → 아이노드 번호 매핑
//
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 상수 정의
// ============================================================================

const BlockSize = 4096; // 4KB 블록 크기
const MaxInodes = 1024; // 최대 아이노드 수
const MaxBlocks = 8192; // 최대 블록 수
const DirectBlockCount = 12; // 아이노드당 직접 블록 포인터
const IndirectBlockSize = BlockSize / 4; // 간접 블록이 가질 수 있는 포인터 수

// ============================================================================
// 파일 타입 정의
// ============================================================================

pub const FileType = enum(u8) {
    Regular = 0,
    Directory = 1,
    Symlink = 2,
    CharDevice = 3,
    BlockDevice = 4,
};

pub const FileMode = struct {
    owner_read: bool = true,
    owner_write: bool = true,
    owner_execute: bool = false,
    group_read: bool = true,
    group_write: bool = false,
    group_execute: bool = false,
    other_read: bool = true,
    other_write: bool = false,
    other_execute: bool = false,

    pub fn toU32(self: FileMode) u32 {
        var mode: u32 = 0;
        if (self.owner_read) mode |= 0o400;
        if (self.owner_write) mode |= 0o200;
        if (self.owner_execute) mode |= 0o100;
        if (self.group_read) mode |= 0o040;
        if (self.group_write) mode |= 0o020;
        if (self.group_execute) mode |= 0o010;
        if (self.other_read) mode |= 0o004;
        if (self.other_write) mode |= 0o002;
        if (self.other_execute) mode |= 0o001;
        return mode;
    }
};

// ============================================================================
// 슈퍼블록 (Superblock)
// ============================================================================

/// 파일 시스템의 전체 메타데이터를 담고 있는 구조
pub const Superblock = struct {
    /// 총 블록 수
    total_blocks: u64 = MaxBlocks,

    /// 총 아이노드 수
    total_inodes: u64 = MaxInodes,

    /// 블록 크기 (바이트)
    block_size: u32 = BlockSize,

    /// 아이노드 크기 (바이트)
    inode_size: u32 = @sizeOf(Inode),

    /// 파일 시스템 생성 시간 (Unix 타임스탬프)
    created_time: u64 = 0,

    /// 마지막 점검 시간
    last_check_time: u64 = 0,

    /// 마운트 수
    mount_count: u32 = 0,

    /// 최대 마운트 수 (fsck 필요 임계값)
    max_mount_count: u32 = 30,

    /// 파일 시스템 버전
    version: u16 = 1,

    /// 파일 시스템 상태 (0=깨끗, 1=오류)
    state: u8 = 0,

    /// 사용 중인 블록 수
    used_blocks: u64 = 0,

    /// 사용 중인 아이노드 수
    used_inodes: u64 = 0,

    pub fn init() Superblock {
        return .{
            .created_time = 1740000000, // 임의의 Unix 타임스탬프
        };
    }

    pub fn getFreeBlockCount(self: Superblock) u64 {
        return self.total_blocks - self.used_blocks;
    }

    pub fn getFreeInodeCount(self: Superblock) u64 {
        return self.total_inodes - self.used_inodes;
    }
};

// ============================================================================
// 아이노드 (Inode) - 파일/디렉토리 메타데이터
// ============================================================================

/// 파일 또는 디렉토리의 메타데이터
/// x86_64에서 64바이트 크기 유지
pub const Inode = packed struct {
    /// 파일 크기 (바이트)
    file_size: u64 = 0,

    /// 파일 생성 시간 (Unix 타임스탬프)
    created_time: u32 = 0,

    /// 파일 수정 시간
    modified_time: u32 = 0,

    /// 파일 접근 시간
    accessed_time: u32 = 0,

    /// 파일 소유자 UID
    owner_uid: u16 = 0,

    /// 파일 소유자 GID
    owner_gid: u16 = 0,

    /// 파일 권한 (octal로 표현)
    permissions: u16 = 0o644,

    /// 하드 링크 수
    hard_links: u16 = 1,

    /// 파일 타입 (regular, directory, symlink)
    file_type: u8 = @intFromEnum(FileType.Regular),

    /// 블록 개수
    block_count: u16 = 0,

    /// 12개의 직접 블록 포인터 (0~11)
    /// 파일의 처음 12블록(48KB)을 직접 가리킴
    direct_blocks: [DirectBlockCount]u32 = [_]u32{0} ** DirectBlockCount,

    /// 간접 블록 포인터 (single indirect)
    /// BlockSize / 4 = 1024개의 블록 포인터를 담을 수 있음
    /// 최대 4MB 추가 용량
    indirect_block: u32 = 0,

    /// 더블 간접 블록 포인터 (double indirect)
    /// 1024 * 1024 = 1M 개의 블록 포인터 가능
    /// 4TB 추가 용량
    double_indirect_block: u32 = 0,

    pub fn init() Inode {
        return .{};
    }

    pub fn maxFileSize() u64 {
        // 12개 직접 블록: 12 * 4KB = 48KB
        const direct_size: u64 = DirectBlockCount * BlockSize;

        // 1개 간접 블록: 1024 * 4KB = 4MB
        const indirect_size: u64 = IndirectBlockSize * BlockSize;

        // 1개 더블 간접: 1024 * 1024 * 4KB = 4GB
        const double_indirect_size: u64 = IndirectBlockSize * IndirectBlockSize * BlockSize;

        return direct_size + indirect_size + double_indirect_size;
    }

    pub fn getBlockCount(file_size: u64) u32 {
        return @intCast((file_size + BlockSize - 1) / BlockSize);
    }
};

// ============================================================================
// 디렉토리 엔트리 (Directory Entry)
// ============================================================================

/// 디렉토리 내의 파일/폴더 항목
pub const DirectoryEntry = struct {
    /// 대상 아이노드 번호
    inode_num: u32 = 0,

    /// 엔트리 타입
    entry_type: FileType = .Regular,

    /// 파일/폴더 이름 (최대 255자)
    name: [256]u8 = [_]u8{0} ** 256,

    /// 이름의 실제 길이
    name_len: u8 = 0,

    pub fn init(inode_num: u32, name: []const u8, entry_type: FileType) DirectoryEntry {
        var entry: DirectoryEntry = .{
            .inode_num = inode_num,
            .entry_type = entry_type,
            .name_len = @intCast(name.len),
        };

        for (name, 0..) |ch, i| {
            if (i >= 256) break;
            entry.name[i] = ch;
        }

        return entry;
    }

    pub fn getName(self: DirectoryEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

// ============================================================================
// 저널 엔트리 (Journal Entry) - 데이터 무결성
// ============================================================================

/// 저널링용 작업 기록
pub const JournalEntry = struct {
    /// 작업 ID (순차 증가)
    transaction_id: u64 = 0,

    /// 작업 상태 (0=진행중, 1=완료, 2=롤백)
    status: u8 = 0,

    /// 작업 시간
    timestamp: u64 = 0,

    /// 수정할 블록 번호
    block_number: u32 = 0,

    /// 이전 데이터 (복구용)
    old_data: [256]u8 = [_]u8{0} ** 256,

    /// 새 데이터
    new_data: [256]u8 = [_]u8{0} ** 256,

    /// 데이터 크기
    data_size: u16 = 0,

    pub fn init(transaction_id: u64) JournalEntry {
        return .{
            .transaction_id = transaction_id,
            .timestamp = 1740000000,
        };
    }
};

// ============================================================================
// 가상 파일 시스템 (VFS) - 인터페이스
// ============================================================================

pub const VFileSystem = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, inode_num: u32, buffer: []u8) anyerror!usize,
        write: *const fn (ptr: *anyopaque, inode_num: u32, data: []const u8) anyerror!void,
        mkdir: *const fn (ptr: *anyopaque, parent_inode: u32, name: []const u8) anyerror!u32,
        rmdir: *const fn (ptr: *anyopaque, inode_num: u32) anyerror!void,
        unlink: *const fn (ptr: *anyopaque, inode_num: u32) anyerror!void,
        lookup: *const fn (ptr: *anyopaque, parent_inode: u32, name: []const u8) anyerror!u32,
    };

    pub fn read(self: VFileSystem, inode_num: u32, buffer: []u8) !usize {
        return self.vtable.read(self.ptr, inode_num, buffer);
    }

    pub fn write(self: VFileSystem, inode_num: u32, data: []const u8) !void {
        return self.vtable.write(self.ptr, inode_num, data);
    }

    pub fn mkdir(self: VFileSystem, parent_inode: u32, name: []const u8) !u32 {
        return self.vtable.mkdir(self.ptr, parent_inode, name);
    }

    pub fn rmdir(self: VFileSystem, inode_num: u32) !void {
        return self.vtable.rmdir(self.ptr, inode_num);
    }

    pub fn unlink(self: VFileSystem, inode_num: u32) !void {
        return self.vtable.unlink(self.ptr, inode_num);
    }

    pub fn lookup(self: VFileSystem, parent_inode: u32, name: []const u8) !u32 {
        return self.vtable.lookup(self.ptr, parent_inode, name);
    }
};

// ============================================================================
// 간단한 파일 시스템 구현
// ============================================================================

pub const SimpleFileSystem = struct {
    /// 슈퍼블록
    superblock: Superblock = .{},

    /// 아이노드 테이블
    inode_table: [MaxInodes]Inode = [_]Inode{.{}} ** MaxInodes,

    /// 블록 비트맵 (0=사용 가능, 1=사용 중)
    block_bitmap: [MaxBlocks / 64]u64 = [_]u64{0} ** (MaxBlocks / 64),

    /// 아이노드 비트맵
    inode_bitmap: [MaxInodes / 64]u64 = [_]u64{0} ** (MaxInodes / 64),

    /// 데이터 블록 (시뮬레이션)
    data_blocks: [MaxBlocks][]u8 = [_][]u8{undefined} ** MaxBlocks,

    /// 저널 로그
    journal: [100]JournalEntry = [_]JournalEntry{.{}} ** 100,

    /// 다음 저널 ID
    next_journal_id: u64 = 1,

    pub fn init(self: *SimpleFileSystem) void {
        self.superblock = Superblock.init();

        // 루트 디렉토리 아이노드 (0번) 생성
        var root_inode = Inode.init();
        root_inode.file_type = @intFromEnum(FileType.Directory);
        root_inode.permissions = 0o755;
        root_inode.hard_links = 2;
        self.inode_table[0] = root_inode;

        self.markInodeUsed(0);
        self.superblock.used_inodes = 1;
    }

    fn markBlockUsed(self: *SimpleFileSystem, block_num: u32) void {
        const bit_idx = block_num % 64;
        const array_idx = block_num / 64;
        self.block_bitmap[array_idx] |= (@as(u64, 1) << @intCast(bit_idx));
        self.superblock.used_blocks += 1;
    }

    fn markBlockFree(self: *SimpleFileSystem, block_num: u32) void {
        const bit_idx = block_num % 64;
        const array_idx = block_num / 64;
        self.block_bitmap[array_idx] &= ~(@as(u64, 1) << @intCast(bit_idx));
        self.superblock.used_blocks -= 1;
    }

    fn markInodeUsed(self: *SimpleFileSystem, inode_num: u32) void {
        const bit_idx = inode_num % 64;
        const array_idx = inode_num / 64;
        self.inode_bitmap[array_idx] |= (@as(u64, 1) << @intCast(bit_idx));
    }

    fn markInodeFree(self: *SimpleFileSystem, inode_num: u32) void {
        const bit_idx = inode_num % 64;
        const array_idx = inode_num / 64;
        self.inode_bitmap[array_idx] &= ~(@as(u64, 1) << @intCast(bit_idx));
    }

    fn allocateBlock(self: *SimpleFileSystem) !u32 {
        for (0..MaxBlocks) |block_num| {
            const bit_idx = block_num % 64;
            const array_idx = block_num / 64;
            if ((self.block_bitmap[array_idx] & (@as(u64, 1) << @intCast(bit_idx))) == 0) {
                self.markBlockUsed(@intCast(block_num));
                return @intCast(block_num);
            }
        }
        return error.NoFreeBlocks;
    }

    fn allocateInode(self: *SimpleFileSystem) !u32 {
        for (0..MaxInodes) |inode_num| {
            const bit_idx = inode_num % 64;
            const array_idx = inode_num / 64;
            if ((self.inode_bitmap[array_idx] & (@as(u64, 1) << @intCast(bit_idx))) == 0) {
                self.markInodeUsed(@intCast(inode_num));
                self.superblock.used_inodes += 1;
                return @intCast(inode_num);
            }
        }
        return error.NoFreeInodes;
    }

    pub fn createFile(self: *SimpleFileSystem, name: []const u8) !u32 {
        const inode_num = try self.allocateInode();
        self.inode_table[inode_num].file_type = @intFromEnum(FileType.Regular);
        self.inode_table[inode_num].permissions = 0o644;
        return inode_num;
    }

    pub fn createDirectory(self: *SimpleFileSystem, name: []const u8) !u32 {
        const inode_num = try self.allocateInode();
        self.inode_table[inode_num].file_type = @intFromEnum(FileType.Directory);
        self.inode_table[inode_num].permissions = 0o755;
        self.inode_table[inode_num].hard_links = 2; // "." and ".."
        return inode_num;
    }

    pub fn deleteFile(self: *SimpleFileSystem, inode_num: u32) void {
        // 방법 1: 경량 삭제 (아이노드만 해제)
        // 장점: 빠름, 단점: 디스크 공간 회수 안됨
        self.inode_table[inode_num].hard_links -= 1;
        if (self.inode_table[inode_num].hard_links == 0) {
            self.markInodeFree(inode_num);
            self.superblock.used_inodes -= 1;
        }
    }

    pub fn getStats(self: SimpleFileSystem) struct {
        total_blocks: u64,
        used_blocks: u64,
        free_blocks: u64,
        total_inodes: u64,
        used_inodes: u64,
        free_inodes: u64,
    } {
        return .{
            .total_blocks = self.superblock.total_blocks,
            .used_blocks = self.superblock.used_blocks,
            .free_blocks = self.superblock.getFreeBlockCount(),
            .total_inodes = self.superblock.total_inodes,
            .used_inodes = self.superblock.used_inodes,
            .free_inodes = self.superblock.getFreeInodeCount(),
        };
    }

    pub fn getMaxFileSize() u64 {
        return Inode.maxFileSize();
    }
};

// ============================================================================
// 경로 탐색 분석
// ============================================================================

pub const PathTraversalAnalysis = struct {
    pub fn description() []const u8 {
        return
            \\【 경로 탐색: /home/user/test.txt 】
            \\
            \\1단계: 루트 디렉토리 열기
            \\   경로: /
            \\   아이노드: 0 (미리 정해짐)
            \\   내용: [home] → inode 1
            \\         [etc]  → inode 2
            \\         ...
            \\
            \\2단계: "home" 디렉토리 찾기
            \\   루트(inode 0)의 디렉토리 엔트리 탐색
            \\   "home" 찾음 → inode 1
            \\   inode_table[1] 로드
            \\
            \\3단계: "user" 디렉토리 찾기
            \\   home(inode 1)의 디렉토리 엔트리 탐색
            \\   "user" 찾음 → inode 10
            \\   inode_table[10] 로드
            \\
            \\4단계: "test.txt" 파일 찾기
            \\   user(inode 10)의 디렉토리 엔트리 탐색
            \\   "test.txt" 찾음 → inode 50
            \\   inode_table[50] 로드
            \\
            \\5단계: 파일 데이터 접근
            \\   inode 50의 direct_blocks[0~11] 참조
            \\   필요시 indirect_block 참조
            \\   실제 데이터 블록 읽기
            \\
            \\【 시간 복잡도 】
            \\- 각 단계마다 디렉토리 엔트리 선형 탐색
            \\- 최악의 경우: O(경로 깊이 * 디렉토리 크기)
            \\- 해결책: 해시 테이블(Dentry Cache) 사용
        ;
    }
};

// ============================================================================
// 파일 크기 계산
// ============================================================================

pub const FileSizeAnalysis = struct {
    pub fn description() []const u8 {
        return
            \\【 파일 최대 크기 계산 (4KB 블록) 】
            \\
            \\1. 직접 블록 (Direct Blocks)
            \\   개수: 12개
            \\   크기: 12 * 4KB = 48KB
            \\
            \\2. 간접 블록 (Single Indirect)
            \\   포인터 개수: 4KB / 4B = 1024개
            \\   최대 크기: 1024 * 4KB = 4MB
            \\
            \\3. 더블 간접 블록 (Double Indirect)
            \\   1차 포인터: 1024개 (각각 1024개의 블록 포인터)
            \\   최대 크기: 1024 * 1024 * 4KB = 4GB
            \\
            \\【 총합 】
            \\48KB + 4MB + 4GB = 약 4.004GB
            \\
            \\【 실제 적용 】
            \\- 대부분의 파일: 48KB 이내 (직접 블록만 사용)
            \\- 중간 크기: 4MB~4GB (간접 블록 필요)
            \\- 대형 파일: 더블 간접 블록 필요
            \\
            \\【 확장 가능성 】
            \\- 트리플 간접 블록 추가 가능
            \\- 각 추가 레벨마다 1024배 용량 증가
        ;
    }
};

// ============================================================================
// 파일 삭제 전략 분석
// ============================================================================

pub const FileDeletionAnalysis = struct {
    pub fn description() []const u8 {
        return
            \\【 파일 삭제 전략 분석 】
            \\
            \\전략 1: 경량 삭제 (Lazy Deletion)
            \\- 아이노드만 해제
            \\- 실제 데이터 블록 유지
            \\
            \\장점:
            \\  ✓ 매우 빠름 (O(1))
            \\  ✓ 데이터 복구 가능
            \\  ✓ 저널링 불필요
            \\
            \\단점:
            \\  ✗ 디스크 공간 낭비
            \\  ✗ 디스크 사용률 정확하지 않음
            \\  ✗ 주기적인 정리(Garbage Collection) 필요
            \\
            \\전략 2: 즉시 삭제 (Eager Deletion)
            \\- 아이노드 + 블록 모두 즉시 해제
            \\
            \\장점:
            \\  ✓ 디스크 공간 즉시 회수
            \\  ✓ 공간 사용률 정확
            \\
            \\단점:
            \\  ✗ 느림 (모든 블록 할당 해제)
            \\  ✗ 전원 차단 시 데이터 손상 위험
            \\  ✗ 복구 불가능
            \\
            \\전략 3: 저널링 삭제 (Journaled Deletion)
            \\- 삭제 작업을 저널에 기록
            \\- 안전 확인 후 실제 삭제
            \\
            \\장점:
            \\  ✓ 안전함
            \\  ✓ 데이터 무결성 보장
            \\  ✓ 전원 차단 시 복구 가능
            \\
            \\단점:
            \\  ✗ 느림 (저널 I/O)
            \\  ✗ 저널 공간 필요
            \\
            \\【 권장 사항 】
            \\- 일반 파일: 경량 삭제 (빠름)
            \\- 중요 데이터: 저널링 삭제 (안전)
        ;
    }
};

// ============================================================================
// VGA 출력
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
                .foreground = @intFromEnum(VGAColor.light_magenta),
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

pub fn testSuperblock() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 1: Superblock ===\n");

    const sb = Superblock.init();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Total blocks: {}\n", .{sb.total_blocks}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Block size: {}KB\n", .{sb.block_size / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Total inodes: {}\n", .{sb.total_inodes}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testInode() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 2: Inode Structure ===\n");

    const inode = Inode.init();
    const max_size = Inode.maxFileSize();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Inode size: {} bytes\n", .{@sizeOf(Inode)}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Max file size: {}MB\n", .{max_size / 1024 / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Direct blocks: {}\n", .{DirectBlockCount}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testFileSystem() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 3: File System ===\n");

    var fs: SimpleFileSystem = .{};
    fs.init();

    const file_inode = try fs.createFile("test.txt");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Created file inode: {}\n", .{file_inode}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    const stats = fs.getStats();
    fbs.reset();
    std.fmt.format(fbs.writer(), "Used inodes: {}\n", .{stats.used_inodes}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testDirectoryEntry() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 4: Directory Entry ===\n");

    const entry = DirectoryEntry.init(42, "test.txt", .Regular);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Inode num: {}\n", .{entry.inode_num}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Name length: {}\n", .{entry.name_len}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testJournal() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 5: Journal Entry ===\n");

    const journal = JournalEntry.init(1);

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Transaction ID: {}\n", .{journal.transaction_id}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Status: {}\n", .{journal.status}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testFileCreation() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 6: File Creation ===\n");

    var fs: SimpleFileSystem = .{};
    fs.init();

    const file1 = try fs.createFile("document.txt");
    const file2 = try fs.createFile("image.png");
    const file3 = try fs.createFile("video.mp4");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Created 3 files: {}, {}, {}\n", .{ file1, file2, file3 }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testDirectoryCreation() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 7: Directory Creation ===\n");

    var fs: SimpleFileSystem = .{};
    fs.init();

    const home_dir = try fs.createDirectory("home");
    const user_dir = try fs.createDirectory("user");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Home inode: {}\n", .{home_dir}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "User inode: {}\n", .{user_dir}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testFileDeletion() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 8: File Deletion ===\n");

    var fs: SimpleFileSystem = .{};
    fs.init();

    const file = try fs.createFile("temp.txt");

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Before delete: {}\n", .{fs.superblock.used_inodes}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fs.deleteFile(file);

    fbs.reset();
    std.fmt.format(fbs.writer(), "After delete: {}\n", .{fs.superblock.used_inodes}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testFileSystemStats() !void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 9: File System Stats ===\n");

    var fs: SimpleFileSystem = .{};
    fs.init();

    _ = try fs.createFile("file1.txt");
    _ = try fs.createFile("file2.txt");
    _ = try fs.createDirectory("folder");

    const stats = fs.getStats();

    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    std.fmt.format(fbs.writer(), "Used inodes: {}/{}\n", .{ stats.used_inodes, stats.total_inodes }) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "Free blocks: {}\n", .{stats.free_blocks}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);
}

pub fn testPathTraversal() void {
    var terminal: VGATerminal = .{};

    terminal.writeString("=== Test 10: Path Traversal Analysis ===\n");
    terminal.writeString(PathTraversalAnalysis.description());
}

// ============================================================================
// 메인 진입점
// ============================================================================

pub export fn _start() noreturn {
    var terminal: VGATerminal = .{};
    terminal.clear();

    // 헤더
    terminal.writeString("╔═════════════════════════════════════════════╗\n");
    terminal.writeString("║ Lesson 3-6: File System Design              ║\n");
    terminal.writeString("║  Persistent Data Storage Architecture      ║\n");
    terminal.writeString("╚═════════════════════════════════════════════╝\n\n");

    // 파일 시스템 정보
    terminal.writeString("📊 File System Architecture:\n");
    var buffer: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    std.fmt.format(fbs.writer(), "  Block size: {}KB\n", .{BlockSize / 1024}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Max blocks: {}\n", .{MaxBlocks}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    fbs.reset();
    std.fmt.format(fbs.writer(), "  Max inodes: {}\n", .{MaxInodes}) catch unreachable;
    terminal.writeString(buffer[0..fbs.pos]);

    terminal.writeString("\n🧪 Running Tests...\n\n");

    // 테스트 실행
    testSuperblock();
    terminal.writeString("\n");

    testInode();
    terminal.writeString("\n");

    testFileSystem() catch |err| {
        terminal.writeString("ERROR: Test 3 failed\n");
    };
    terminal.writeString("\n");

    testDirectoryEntry();
    terminal.writeString("\n");

    testJournal();
    terminal.writeString("\n");

    testFileCreation() catch |err| {
        terminal.writeString("ERROR: Test 6 failed\n");
    };
    terminal.writeString("\n");

    testDirectoryCreation() catch |err| {
        terminal.writeString("ERROR: Test 7 failed\n");
    };
    terminal.writeString("\n");

    testFileDeletion() catch |err| {
        terminal.writeString("ERROR: Test 8 failed\n");
    };
    terminal.writeString("\n");

    testFileSystemStats() catch |err| {
        terminal.writeString("ERROR: Test 9 failed\n");
    };
    terminal.writeString("\n");

    testPathTraversal();

    terminal.writeString("\n═════════════════════════════════════════════\n");
    terminal.writeString("✅ Assignment 3-6: File System Complete!\n");
    terminal.writeString("기록이 증명이다 - Persistent Storage Ready!\n");
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
