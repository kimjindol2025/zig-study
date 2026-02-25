/// src/main.zig - Zig 전공 101: 1-1. Hello, Zig!
///
/// Assignment 1-1: Hello, Zig (설치와 첫 컴파일)
///
/// 철학: "숨겨진 제어 흐름이 없다"
/// 모든 메모리 할당과 오류 처리는 명시적이어야 한다.

const std = @import("std");

pub fn main() !void {
    // 표준 출력 스트림 가져오기
    const stdout = std.io.getStdOut().writer();

    // 학번: CLU-2026-ZIG-001 (가상의 ID)
    const student_id = "CLU-2026-ZIG-001";

    // 프로그램 시작
    try stdout.print("🎓 Zig 전공 과정 시작!\n", .{});
    try stdout.print("학번: {s}\n", .{student_id});
    try stdout.print("📝 Assignment 1-1: Hello, Zig! (설치와 첫 컴파일)\n", .{});
    try stdout.print("\n", .{});

    // 프로그램 메인 메시지
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});
    try stdout.print("Hello, Zig Graduate School!\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});
    try stdout.print("\n", .{});

    // 학습 내용
    try stdout.print("📚 오늘의 학습:\n", .{});
    try stdout.print("  1️⃣ 환경 구축 (Laboratory Setup)\n", .{});
    try stdout.print("     - zig version으로 설치 확인\n", .{});
    try stdout.print("     - Zig 0.11.0 이상 권장\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("  2️⃣ 프로젝트 초기화 (Project Initialization)\n", .{});
    try stdout.print("     - zig init으로 프로젝트 구조 생성\n", .{});
    try stdout.print("     - build.zig: Zig 전용 빌드 스크립트\n", .{});
    try stdout.print("     - src/main.zig: 메인 진입점\n", .{});
    try stdout.print("     - src/root.zig: 라이브러리 루트\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("  3️⃣ Hello World 분석\n", .{});
    try stdout.print("     - const std = @import(\"std\")\n", .{});
    try stdout.print("     - pub fn main() !void\n", .{});
    try stdout.print("     - try stdout.print() 패턴\n", .{});
    try stdout.print("     - \"!\"는 오류 가능성 표시\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("🔬 전공 심화: comptime의 마법\n", .{});
    try stdout.print("  - 컴파일 시점에 코드 실행\n", .{});
    try stdout.print("  - 제네릭 구현 (복잡한 문법 없음)\n", .{});
    try stdout.print("  - 타입 생성 및 논리 결정\n", .{});
    try stdout.print("\n", .{});

    // 성공 메시지
    try stdout.print("✅ 프로그램 실행 성공!\n", .{});
    try stdout.print("기록이 증명이다 - Zig 학습을 시작합니다.\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("🚀 다음 단계 (1-2):\n", .{});
    try stdout.print("   변수, 상수, 그리고 엄격한 타입 시스템\n", .{});
    try stdout.print("   Zig가 var와 const를 까다롭게 구분하는 이유\n", .{});
}

// ============================================================================
// 테스트: 프로그램이 컴파일 되는지 확인
// ============================================================================

test "program compiles" {
    // 이 테스트는 프로그램이 컴파일되는지 확인합니다.
    const compiles = true;
    try std.testing.expect(compiles);
}
