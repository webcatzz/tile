const cmpt = @import("../cmpt.zig");
const math = @import("../../core/math.zig");
const render = @import("../../core/render.zig");

const Sprite = @This();

sheet: render.Sheet,
src: math.Rect(f32),

pub fn draw(
    ctx: struct { render_queue: *render.Queue },
    sprite: Sprite,
    pos: cmpt.Pos,
) !void {
    try ctx.render_queue.switchSheet(sprite.sheet);
    try ctx.render_queue.drawRectPos(sprite.src, pos.pos);
}
