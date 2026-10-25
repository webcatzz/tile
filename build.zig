const sokol = @import("sokol");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_mod = sokol_dep.module("sokol");

    const shd_mod = try sokol.shdc.createModule(b, "shader", sokol_mod, .{
        .shdc_dep = sokol_dep.builder.dependency("shdc", .{}),
        .input = "res/shd/basic.glsl",
        .output = "res/shd/basic.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl4 = true,
            .metal_macos = true,
            .wgsl = true,
        },
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shd_desc_basic", .module = shd_mod },
            .{ .name = "sokol", .module = sokol_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "tile",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // `run`

    const run_step = b.step("run", "Run the game");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    run_step.dependOn(&run_cmd.step);
}
