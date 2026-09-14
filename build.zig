const std = @import("std");

fn buildAndRunCodegen(b: *std.Build, comptime name: []const u8) std.Build.LazyPath {
    const tool = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/" ++ name ++ ".zig"),
            .target = b.graph.host,
        }),
    });
    const tool_step = b.addRunArtifact(tool);
    return tool_step.addOutputFileArg(name ++ "_output.zig");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "thorn",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hash_tables", .module = b.createModule(.{
                    .root_source_file = buildAndRunCodegen(b, "generate_hashes"),
                }) },
                .{ .name = "pext_tables", .module = b.createModule(.{
                    .root_source_file = buildAndRunCodegen(b, "generate_pext"),
                }) },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
