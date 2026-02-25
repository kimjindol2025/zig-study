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
    // 테스트
    // ============================================================================

    const tests = b.addTest(.{
        .root_source_file = b.path("src/lesson_1_2.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_test = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);
}
