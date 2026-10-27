const action = @import("../action.zig");
const cmpt = @import("../cmpt.zig");
const input = @import("../../core/input.zig");
const math = @import("../../core/math.zig");

pub const Leader = struct {
    /// The side the leader is facing.
    facing: math.Side = .right,
    /// A queue of directions for followers.
    queue: []math.Side = &.{},

    pub fn walk(self: *Leader, pos: *cmpt.Pos) void {
        switch (self.facing) {
            .left => pos.pos.x -= 16,
            .right => pos.pos.x += 16,
            .top => pos.pos.y -= 16,
            .bottom => pos.pos.y += 16,
        }

        if (self.queue.len > 0) {
            @memmove(self.queue[1..], self.queue[0 .. self.queue.len - 1]);
            self.queue[0] = self.facing;
        }
    }

    pub fn respond(
        ctx: struct { action_map: action.Map },
        leader: *Leader,
        pos: *cmpt.Pos,
    ) void {
        leader.facing =
            if (ctx.action_map.isActive(.left))
                .left
            else if (ctx.action_map.isActive(.right))
                .right
            else if (ctx.action_map.isActive(.up))
                .top
            else if (ctx.action_map.isActive(.down))
                .bottom
            else
                return;

        leader.walk(pos);
    }
};
