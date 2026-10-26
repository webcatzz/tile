//! Game state.

const action = @import("action.zig");
const cmpt = @import("cmpt.zig");
const ecs = @import("ecs.zig");
const input = @import("../core/input.zig");
const render = @import("../core/render.zig");
const std = @import("std");

const Ctx = @This();

world: ecs.World,
action_map: action.Map = .{},
sheet: render.Sheet,
render_queue: render.Queue,

const width = 200;
const height = 150;

pub fn init(gpa: std.mem.Allocator, io: std.Io) !Ctx {
    var world: ecs.World = .init();
    errdefer world.deinit();

    world.registerComponent(cmpt.Pos);
    world.registerComponent(cmpt.party.Leader);
    world.registerComponent(cmpt.Sprite);

    const sheet: render.Sheet = try .load(gpa, io, "char");
    errdefer sheet.deinit();

    const render_queue: render.Queue = try .init();
    errdefer render_queue.deinit();

    const entity = world.new(&.{ cmpt.Pos, cmpt.Sprite, cmpt.party.Leader });
    world.set(entity, cmpt.Pos, .{});
    world.set(entity, cmpt.Sprite, .{ .sheet = sheet, .src = .{ .x = 0, .y = 0, .w = 16, .h = 16 } });
    world.set(entity, cmpt.party.Leader, .{});

    return .{
        .world = world,
        .sheet = sheet,
        .render_queue = render_queue,
    };
}

pub fn deinit(self: *Ctx, _: std.mem.Allocator) void {
    self.world.deinit();
    self.sheet.deinit();
    self.render_queue.deinit();
    self.* = undefined;
}

pub fn iter(self: *Ctx) !void {
    try self.render_queue.switchScale(1 / @as(f32, width), 1 / @as(f32, height));

    try self.world.run(cmpt.Sprite.draw, .{ .render_queue = &self.render_queue });

    self.render_queue.commit();
}

pub fn respond(self: *Ctx, comptime event_type: input.event.Type, event: input.event.of(event_type)) !void {
    self.action_map.record(event_type, event);

    switch (event_type) {
        .button => {
            try self.world.run(cmpt.party.Leader.respond, .{ .action_map = self.action_map });
        },
        else => {},
    }
}
