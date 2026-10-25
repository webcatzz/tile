//! Game state.

const input = @import("../core/input.zig");
const render = @import("../core/render.zig");
const std = @import("std");

const Ctx = @This();

sheet: render.Sheet,
render_queue: render.Queue,

const width = 200;
const height = 150;

pub fn init(gpa: std.mem.Allocator, io: std.Io) !Ctx {
    const sheet: render.Sheet = try .load(gpa, io, "char");
    errdefer sheet.deinit();

    const render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    return .{
        .sheet = sheet,
        .render_queue = try .init(),
    };
}

pub fn deinit(self: *Ctx, gpa: std.mem.Allocator) void {
    _ = gpa;
    self.sheet.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *Ctx) !void {
    try self.render_queue.switchScale(1 / @as(f32, width), 1 / @as(f32, height));
    try self.render_queue.switchSheet(self.sheet);
    try self.render_queue.drawRectPos(
        .{ .x = 0, .y = 0, .w = width, .h = height },
        .zero,
    );
    self.render_queue.commit();
}

pub fn respond(self: *Ctx, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    _ = self;
    _ = event;
}
