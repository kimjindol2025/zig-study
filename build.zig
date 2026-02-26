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
    // 테스트
    // ============================================================================

    const tests = b.addTest(.{
        .root_source_file = b.path("src/lesson_1_7.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_test = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);
}
