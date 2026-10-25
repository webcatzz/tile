const Ctx = @import("logic/Ctx.zig");
const loop = @import("core/loop.zig");
const std = @import("std");

pub fn main(init: std.process.Init) void {
    loop.run(Ctx, init);
}
