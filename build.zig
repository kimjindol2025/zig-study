const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================================
    // 메인 프로그램 (1-1)
    // ============================================================================

    const exe = b.addExecutable(.{
        .name = "zig-study",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the main program (1-1)");
    run_step.dependOn(&run_cmd.step);

    // ============================================================================
    // Lesson 1-2: 변수, 상수, 타입 시스템
    // ============================================================================

    const lesson_1_2 = b.addExecutable(.{
        .name = "lesson-1-2",
        .root_source_file = b.path("src/lesson_1_2.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_2);

    const run_lesson_1_2 = b.addRunArtifact(lesson_1_2);
    run_lesson_1_2.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_2.addArgs(args);
    }

    const run_lesson_1_2_step = b.step("run-1-2", "Run Lesson 1-2 (변수와 타입)");
    run_lesson_1_2_step.dependOn(&run_lesson_1_2.step);

    // ============================================================================
    // Lesson 1-3: 제어문 - if, while, for, switch
    // ============================================================================

    const lesson_1_3 = b.addExecutable(.{
        .name = "lesson-1-3",
        .root_source_file = b.path("src/lesson_1_3.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_3);

    const run_lesson_1_3 = b.addRunArtifact(lesson_1_3);
    run_lesson_1_3.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_3.addArgs(args);
    }

    const run_lesson_1_3_step = b.step("run-1-3", "Run Lesson 1-3 (제어문)");
    run_lesson_1_3_step.dependOn(&run_lesson_1_3.step);

    // ============================================================================
    // Lesson 1-4: 함수와 에러 핸들링
    // ============================================================================

    const lesson_1_4 = b.addExecutable(.{
        .name = "lesson-1-4",
        .root_source_file = b.path("src/lesson_1_4.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_4);

    const run_lesson_1_4 = b.addRunArtifact(lesson_1_4);
    run_lesson_1_4.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_4.addArgs(args);
    }

    const run_lesson_1_4_step = b.step("run-1-4", "Run Lesson 1-4 (함수와 에러)");
    run_lesson_1_4_step.dependOn(&run_lesson_1_4.step);

    // ============================================================================
    // Lesson 1-5: 구조체와 메서드
    // ============================================================================

    const lesson_1_5 = b.addExecutable(.{
        .name = "lesson-1-5",
        .root_source_file = b.path("src/lesson_1_5.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_5);

    const run_lesson_1_5 = b.addRunArtifact(lesson_1_5);
    run_lesson_1_5.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_5.addArgs(args);
    }

    const run_lesson_1_5_step = b.step("run-1-5", "Run Lesson 1-5 (구조체와 메서드)");
    run_lesson_1_5_step.dependOn(&run_lesson_1_5.step);

    // ============================================================================
    // Lesson 1-6: 포인터와 메모리 관리
    // ============================================================================

    const lesson_1_6 = b.addExecutable(.{
        .name = "lesson-1-6",
        .root_source_file = b.path("src/lesson_1_6.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_6);

    const run_lesson_1_6 = b.addRunArtifact(lesson_1_6);
    run_lesson_1_6.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_6.addArgs(args);
    }

    const run_lesson_1_6_step = b.step("run-1-6", "Run Lesson 1-6 (포인터와 메모리)");
    run_lesson_1_6_step.dependOn(&run_lesson_1_6.step);

    // ============================================================================
    // Lesson 1-7: 배열과 슬라이스
    // ============================================================================

    const lesson_1_7 = b.addExecutable(.{
        .name = "lesson-1-7",
        .root_source_file = b.path("src/lesson_1_7.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_7);

    const run_lesson_1_7 = b.addRunArtifact(lesson_1_7);
    run_lesson_1_7.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_7.addArgs(args);
    }

    const run_lesson_1_7_step = b.step("run-1-7", "Run Lesson 1-7 (배열과 슬라이스)");
    run_lesson_1_7_step.dependOn(&run_lesson_1_7.step);

    // ============================================================================
    // Lesson 1-8: 열거형과 태그된 공용체
    // ============================================================================

    const lesson_1_8 = b.addExecutable(.{
        .name = "lesson-1-8",
        .root_source_file = b.path("src/lesson_1_8.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_8);

    const run_lesson_1_8 = b.addRunArtifact(lesson_1_8);
    run_lesson_1_8.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_8.addArgs(args);
    }

    const run_lesson_1_8_step = b.step("run-1-8", "Run Lesson 1-8 (열거형과 태그된 공용체)");
    run_lesson_1_8_step.dependOn(&run_lesson_1_8.step);

    // ============================================================================
    // Lesson 1-9: 할당자(Allocators)
    // ============================================================================

    const lesson_1_9 = b.addExecutable(.{
        .name = "lesson-1-9",
        .root_source_file = b.path("src/lesson_1_9.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_9);

    const run_lesson_1_9 = b.addRunArtifact(lesson_1_9);
    run_lesson_1_9.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_9.addArgs(args);
    }

    const run_lesson_1_9_step = b.step("run-1-9", "Run Lesson 1-9 (할당자)");
    run_lesson_1_9_step.dependOn(&run_lesson_1_9.step);

    // ============================================================================
    // Lesson 1-10: Comptime
    // ============================================================================

    const lesson_1_10 = b.addExecutable(.{
        .name = "lesson-1-10",
        .root_source_file = b.path("src/lesson_1_10.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_10);

    const run_lesson_1_10 = b.addRunArtifact(lesson_1_10);
    run_lesson_1_10.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_10.addArgs(args);
    }

    const run_lesson_1_10_step = b.step("run-1-10", "Run Lesson 1-10 (Comptime)");
    run_lesson_1_10_step.dependOn(&run_lesson_1_10.step);

    // ============================================================================
    // Lesson 1-11: C 호환성
    // ============================================================================

    const lesson_1_11 = b.addExecutable(.{
        .name = "lesson-1-11",
        .root_source_file = b.path("src/lesson_1_11.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_11);

    const run_lesson_1_11 = b.addRunArtifact(lesson_1_11);
    run_lesson_1_11.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_11.addArgs(args);
    }

    const run_lesson_1_11_step = b.step("run-1-11", "Run Lesson 1-11 (C 호환성)");
    run_lesson_1_11_step.dependOn(&run_lesson_1_11.step);

    // ============================================================================
    // Lesson 1-12: 멀티스레딩과 원자적 연산
    // ============================================================================

    const lesson_1_12 = b.addExecutable(.{
        .name = "lesson-1-12",
        .root_source_file = b.path("src/lesson_1_12.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_12);

    const run_lesson_1_12 = b.addRunArtifact(lesson_1_12);
    run_lesson_1_12.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_12.addArgs(args);
    }

    const run_lesson_1_12_step = b.step("run-1-12", "Run Lesson 1-12 (멀티스레딩)");
    run_lesson_1_12_step.dependOn(&run_lesson_1_12.step);

    // ============================================================================
    // Lesson 1-13: 대규모 시스템 아키텍처
    // ============================================================================

    const lesson_1_13 = b.addExecutable(.{
        .name = "lesson-1-13",
        .root_source_file = b.path("src/lesson_1_13.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_1_13);

    const run_lesson_1_13 = b.addRunArtifact(lesson_1_13);
    run_lesson_1_13.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_1_13.addArgs(args);
    }

    const run_lesson_1_13_step = b.step("run-1-13", "Run Lesson 1-13 (대규모 시스템 아키텍처)");
    run_lesson_1_13_step.dependOn(&run_lesson_1_13.step);

    // ============================================================================
    // Lesson 2-1: 고성능 네트워크 프로그래밍 (TCP/UDP)
    // ============================================================================

    const lesson_2_1 = b.addExecutable(.{
        .name = "lesson-2-1",
        .root_source_file = b.path("src/lesson_2_1.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_1);

    const run_lesson_2_1 = b.addRunArtifact(lesson_2_1);
    run_lesson_2_1.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_1.addArgs(args);
    }

    const run_lesson_2_1_step = b.step("run-2-1", "Run Lesson 2-1 (고성능 네트워크 프로그래밍)");
    run_lesson_2_1_step.dependOn(&run_lesson_2_1.step);

    // ============================================================================
    // Lesson 2-2: 데이터베이스 연동 및 인터페이스 설계
    // ============================================================================

    const lesson_2_2 = b.addExecutable(.{
        .name = "lesson-2-2",
        .root_source_file = b.path("src/lesson_2_2.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_2);

    const run_lesson_2_2 = b.addRunArtifact(lesson_2_2);
    run_lesson_2_2.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_2.addArgs(args);
    }

    const run_lesson_2_2_step = b.step("run-2-2", "Run Lesson 2-2 (데이터베이스 연동)");
    run_lesson_2_2_step.dependOn(&run_lesson_2_2.step);

    // ============================================================================
    // Lesson 2-3: 캐싱 전략과 동시성 제어
    // ============================================================================

    const lesson_2_3 = b.addExecutable(.{
        .name = "lesson-2-3",
        .root_source_file = b.path("src/lesson_2_3.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_3);

    const run_lesson_2_3 = b.addRunArtifact(lesson_2_3);
    run_lesson_2_3.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_3.addArgs(args);
    }

    const run_lesson_2_3_step = b.step("run-2-3", "Run Lesson 2-3 (캐싱 전략)");
    run_lesson_2_3_step.dependOn(&run_lesson_2_3.step);

    // ============================================================================
    // Lesson 2-4: RESTful API 설계 및 JSON 직렬화
    // ============================================================================

    const lesson_2_4 = b.addExecutable(.{
        .name = "lesson-2-4",
        .root_source_file = b.path("src/lesson_2_4.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_4);

    const run_lesson_2_4 = b.addRunArtifact(lesson_2_4);
    run_lesson_2_4.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_4.addArgs(args);
    }

    const run_lesson_2_4_step = b.step("run-2-4", "Run Lesson 2-4 (RESTful API)");
    run_lesson_2_4_step.dependOn(&run_lesson_2_4.step);

    // ============================================================================
    // Lesson 2-5: 로깅 시스템 및 런타임 모니터링
    // ============================================================================

    const lesson_2_5 = b.addExecutable(.{
        .name = "lesson-2-5",
        .root_source_file = b.path("src/lesson_2_5.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_5);

    const run_lesson_2_5 = b.addRunArtifact(lesson_2_5);
    run_lesson_2_5.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_5.addArgs(args);
    }

    const run_lesson_2_5_step = b.step("run-2-5", "Run Lesson 2-5 (로깅 시스템 및 모니터링)");
    run_lesson_2_5_step.dependOn(&run_lesson_2_5.step);

    // ============================================================================
    // Lesson 2-6: 보안(Security) - 암호화와 인증 프로토콜
    // ============================================================================

    const lesson_2_6 = b.addExecutable(.{
        .name = "lesson-2-6",
        .root_source_file = b.path("src/lesson_2_6.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lesson_2_6);

    const run_lesson_2_6 = b.addRunArtifact(lesson_2_6);
    run_lesson_2_6.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lesson_2_6.addArgs(args);
    }

    const run_lesson_2_6_step = b.step("run-2-6", "Run Lesson 2-6 (보안 및 암호화 설계)");
    run_lesson_2_6_step.dependOn(&run_lesson_2_6.step);

    // ============================================================================
    // Lesson 3-1: 베어 메탈(Bare Metal) 입문
    // ============================================================================

    const freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
    });

    const lesson_3_1 = b.addExecutable(.{
        .name = "lesson-3-1",
        .root_source_file = b.path("src/lesson_3_1.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    // 표준 라이브러리 비활성화
    lesson_3_1.root_module.stack_protector = false;

    b.installArtifact(lesson_3_1);

    const run_lesson_3_1 = b.addRunArtifact(lesson_3_1);
    run_lesson_3_1.step.dependOn(b.getInstallStep());

    const run_lesson_3_1_step = b.step("run-3-1", "Run Lesson 3-1 (베어 메탈 부트로더)");
    run_lesson_3_1_step.dependOn(&run_lesson_3_1.step);

    // ============================================================================
    // Lesson 3-2: GDT 및 IDT 설계 (CPU 보호 메커니즘)
    // ============================================================================

    const lesson_3_2 = b.addExecutable(.{
        .name = "lesson-3-2",
        .root_source_file = b.path("src/lesson_3_2.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_2.root_module.stack_protector = false;

    b.installArtifact(lesson_3_2);

    const run_lesson_3_2 = b.addRunArtifact(lesson_3_2);
    run_lesson_3_2.step.dependOn(b.getInstallStep());

    const run_lesson_3_2_step = b.step("run-3-2", "Run Lesson 3-2 (GDT 및 IDT 설계)");
    run_lesson_3_2_step.dependOn(&run_lesson_3_2.step);

    // ============================================================================
    // Lesson 3-3: 물리 메모리 관리자(PMM) 및 비트맵 설계
    // ============================================================================

    const lesson_3_3 = b.addExecutable(.{
        .name = "lesson-3-3",
        .root_source_file = b.path("src/lesson_3_3.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_3.root_module.stack_protector = false;

    b.installArtifact(lesson_3_3);

    const run_lesson_3_3 = b.addRunArtifact(lesson_3_3);
    run_lesson_3_3.step.dependOn(b.getInstallStep());

    const run_lesson_3_3_step = b.step("run-3-3", "Run Lesson 3-3 (물리 메모리 관리자)");
    run_lesson_3_3_step.dependOn(&run_lesson_3_3.step);

    // ============================================================================
    // Lesson 3-4: 가상 메모리(Paging) 및 페이지 테이블 관리
    // ============================================================================

    const lesson_3_4 = b.addExecutable(.{
        .name = "lesson-3-4",
        .root_source_file = b.path("src/lesson_3_4.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_4.root_module.stack_protector = false;

    b.installArtifact(lesson_3_4);

    const run_lesson_3_4 = b.addRunArtifact(lesson_3_4);
    run_lesson_3_4.step.dependOn(b.getInstallStep());

    const run_lesson_3_4_step = b.step("run-3-4", "Run Lesson 3-4 (가상 메모리 및 페이징)");
    run_lesson_3_4_step.dependOn(&run_lesson_3_4.step);

    // ============================================================================
    // Lesson 3-5: 프로세스와 스레드 - 컨텍스트 스위칭
    // ============================================================================

    const lesson_3_5 = b.addExecutable(.{
        .name = "lesson-3-5",
        .root_source_file = b.path("src/lesson_3_5.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_5.root_module.stack_protector = false;

    b.installArtifact(lesson_3_5);

    const run_lesson_3_5 = b.addRunArtifact(lesson_3_5);
    run_lesson_3_5.step.dependOn(b.getInstallStep());

    const run_lesson_3_5_step = b.step("run-3-5", "Run Lesson 3-5 (프로세스와 스레드)");
    run_lesson_3_5_step.dependOn(&run_lesson_3_5.step);

    // ============================================================================
    // Lesson 3-6: 파일 시스템 - 데이터의 영속적 기록 설계
    // ============================================================================

    const lesson_3_6 = b.addExecutable(.{
        .name = "lesson-3-6",
        .root_source_file = b.path("src/lesson_3_6.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_6.root_module.stack_protector = false;

    b.installArtifact(lesson_3_6);

    const run_lesson_3_6 = b.addRunArtifact(lesson_3_6);
    run_lesson_3_6.step.dependOn(b.getInstallStep());

    const run_lesson_3_6_step = b.step("run-3-6", "Run Lesson 3-6 (파일 시스템 설계)");
    run_lesson_3_6_step.dependOn(&run_lesson_3_6.step);

    // ============================================================================
    // Lesson 3-7: 시스템 호출과 유저 모드(Ring 3) 진입
    // ============================================================================

    const lesson_3_7 = b.addExecutable(.{
        .name = "lesson-3-7",
        .root_source_file = b.path("src/lesson_3_7.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_7.root_module.stack_protector = false;

    b.installArtifact(lesson_3_7);

    const run_lesson_3_7 = b.addRunArtifact(lesson_3_7);
    run_lesson_3_7.step.dependOn(b.getInstallStep());

    const run_lesson_3_7_step = b.step("run-3-7", "Run Lesson 3-7 (시스템 호출 설계)");
    run_lesson_3_7_step.dependOn(&run_lesson_3_7.step);

    // ============================================================================
    // Lesson 3-8: 최종 프로젝트 - 마이크로커널 아키텍처 완성
    // ============================================================================

    const lesson_3_8 = b.addExecutable(.{
        .name = "lesson-3-8",
        .root_source_file = b.path("src/lesson_3_8.zig"),
        .target = freestanding_target,
        .optimize = .ReleaseSafe,
    });

    lesson_3_8.root_module.stack_protector = false;

    b.installArtifact(lesson_3_8);

    const run_lesson_3_8 = b.addRunArtifact(lesson_3_8);
    run_lesson_3_8.step.dependOn(b.getInstallStep());

    const run_lesson_3_8_step = b.step("run-3-8", "Run Lesson 3-8 (마이크로커널 완성)");
    run_lesson_3_8_step.dependOn(&run_lesson_3_8.step);

    // ============================================================================
    // 테스트
    // ============================================================================

    const tests = b.addTest(.{
        .root_source_file = b.path("src/lesson_1_12.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_test = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);
}
