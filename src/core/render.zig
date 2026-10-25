//! Rendering.

const builtin = @import("builtin");
const loop = @import("loop.zig");
const math = @import("math.zig");
const Png = @import("../util/Png.zig");
const shd_desc_basic = @import("shd_desc_basic");
const sokol = @import("sokol");
const std = @import("std");

/// A palette of colors.
pub const Palette = struct {
    _gpu_view: sokol.gfx.View,

    pub const Color = packed struct(u8) {
        /// The hue of the color.
        hue: Hue,
        /// The brightness of the color.
        val: u4,

        pub const Hue = enum(u4) {
            neutral,
            red,
            yellow,
            green,
            blue,
            purple,
        };
    };

    pub fn deinit(self: *Palette) void {
        sokol.gfx.destroyView(self._gpu_view);

        if (builtin.optimize.runtimeSafety())
            self._gpu_view = .{ .id = sokol.gfx.invalid_id };
    }
};

/// A spritesheet.
pub const Sheet = struct {
    _gpu_view: sokol.gfx.View,

    pub fn deinit(self: *Sheet) void {
        sokol.gfx.destroyView(self._gpu_view);

        if (builtin.optimize.runtimeSafety())
            self._gpu_view = .{ .id = sokol.gfx.invalid_id };
    }

    pub fn load(gpa: std.mem.Allocator, io: std.Io, name: []const u8) !Sheet {
        const path = try std.mem.concat(gpa, u8, &.{ "res/spr/", name, ".png" });
        defer gpa.free(path);

        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        var file_buf: [32]u8 = undefined;
        var file_reader = file.reader(io, &file_buf);

        const png = try Png.read(gpa, &file_reader.interface);
        defer gpa.free(png.data);

        const gpu_img = sokol.gfx.makeImage(.{
            .type = ._2D,
            .width = @intCast(png.width),
            .height = @intCast(png.height),
            .usage = .{ .immutable = true, .write_unsealed = true },
        });

        sokol.gfx.writeImageUnsealed(.{
            .src = .{ .data = .{ .ptr = png.data.ptr, .size = png.data.len } },
            .dst = .{ .image = gpu_img },
            .size = .{
                .width = @intCast(png.width),
                .height = @intCast(png.height),
            },
        });

        sokol.gfx.sealImage(gpu_img);

        const gpu_view = sokol.gfx.makeView(.{
            .texture = .{ .image = gpu_img },
        });

        return .{ ._gpu_view = gpu_view };
    }
};

/// A queue of rendering operations.
pub const Queue = struct {
    cmd_buf: std.ArrayList(Command),
    vtx_buf: std.ArrayList(Vertex),
    _gpu_vtx_buf: sokol.gfx.Buffer,
    _gpu_sampler: sokol.gfx.Sampler,
    _gpu_pipeline: sokol.gfx.Pipeline,

    _current_gpu_view: sokol.gfx.View,

    /// Returns a new rendering queue.
    ///
    /// The queue is owned by the caller and should be freed by calling
    /// `deinit`.
    pub fn init() !Queue {
        const vtx_buf = sokol.gfx.makeBuffer(.{
            .usage = .{ .vertex_buffer = true, .write_transient = true },
            .size = @sizeOf(Vertex),
        });

        const sampler = sokol.gfx.makeSampler(.{});

        const shader = sokol.gfx.makeShader(shd_desc_basic.basicShaderDesc(sokol.gfx.queryBackend()));

        const pipeline = sokol.gfx.makePipeline(.{
            .shader = shader,
            .layout = init: {
                var layout: sokol.gfx.VertexLayoutState = .{};
                layout.attrs[shd_desc_basic.ATTR_basic_vert_pos] = .{ .format = .FLOAT2 };
                layout.attrs[shd_desc_basic.ATTR_basic_vert_uv] = .{ .format = .FLOAT2 };
                break :init layout;
            },
        });

        return .{
            .cmd_buf = .empty,
            .vtx_buf = .empty,
            ._gpu_vtx_buf = vtx_buf,
            ._gpu_sampler = sampler,
            ._gpu_pipeline = pipeline,

            ._current_gpu_view = .{ .id = sokol.gfx.invalid_id },
        };
    }

    /// Frees the queue.
    ///
    /// The queue should not be used after calling this function.
    pub fn deinit(self: *Queue) void {
        self.cmd_buf.deinit(loop.gpa);
        self.vtx_buf.deinit(loop.gpa);
        sokol.gfx.destroyBuffer(self._gpu_vtx_buf);
        sokol.gfx.destroySampler(self._gpu_sampler);
        sokol.gfx.destroyPipeline(self._gpu_pipeline);
        self.* = undefined;
    }

    /// Sets the scale multiplier used for subsequent drawing operations.
    pub fn switchScale(self: *Queue, x: f32, y: f32) !void {
        try self.cmd_buf.append(loop.gpa, .{ .switch_scale = .{ .x = x, .y = y } });
    }

    /// Sets the spritesheet used for subsequent drawing operations.
    pub fn switchSheet(self: *Queue, sheet: Sheet) !void {
        if (std.meta.eql(sheet._gpu_view, self._current_gpu_view)) return;
        self._current_gpu_view = sheet._gpu_view;
        try self.cmd_buf.append(loop.gpa, .{ .switch_sheet = sheet._gpu_view });
    }

    /// Queues the given vertices to be drawn.
    pub fn drawVertices(self: *Queue, vertices: []const Vertex) !void {
        if (vertices.len > self.vtx_buf.capacity - self.vtx_buf.items.len) {
            try self.vtx_buf.ensureTotalCapacity(loop.gpa, self.vtx_buf.items.len + vertices.len);

            const gpu_vtx_buf = sokol.gfx.makeBuffer(.{
                .usage = .{ .vertex_buffer = true, .write_transient = true },
                .size = self.vtx_buf.capacity * @sizeOf(Vertex),
            });
            sokol.gfx.destroyBuffer(self._gpu_vtx_buf);
            self._gpu_vtx_buf = gpu_vtx_buf;
        }
        try self.vtx_buf.appendSlice(loop.gpa, vertices);

        if (self.cmd_buf.lastPtr()) |last_cmd|
            if (last_cmd.* == .draw) {
                last_cmd.draw += @intCast(vertices.len);
                return;
            };
        try self.cmd_buf.append(loop.gpa, .{ .draw = @intCast(vertices.len) });
    }

    /// Queues the given rectangle to be drawn to fill `dst`.
    pub fn drawRect(self: *Queue, src: math.Rect(f32), dst: math.Rect(f32)) !void {
        const vertices: [4]Vertex = .{
            .{ .x = dst.x, .y = dst.y, .u = src.x, .v = src.y },
            .{ .x = dst.x + dst.w, .y = dst.y, .u = src.x + src.w, .v = src.y },
            .{ .x = dst.x, .y = dst.y + dst.h, .u = src.x, .v = src.y + src.h },
            .{ .x = dst.x + dst.w, .y = dst.y + dst.h, .u = src.x + src.w, .v = src.y + src.h },
        };

        try self.drawVertices(&.{
            vertices[0],
            vertices[1],
            vertices[3],
            vertices[0],
            vertices[3],
            vertices[2],
        });
    }

    /// Queues the given rectangle to be drawn at the given position.
    pub fn drawRectPos(self: *Queue, src: math.Rect(f32), pos: math.Vec2(f32)) !void {
        try self.drawRect(src, .{ .x = pos.x, .y = pos.y, .w = src.w, .h = src.h });
    }

    /// Submits all queued operations to be rendered and clears the queue.
    pub fn commit(self: *Queue) void {
        sokol.gfx.writeBufferTransient(.{
            .src = .{ .data = .{
                .ptr = self.vtx_buf.items.ptr,
                .size = self.vtx_buf.items.len * @sizeOf(Vertex),
            } },
            .dst = .{ .buffer = self._gpu_vtx_buf },
        });

        sokol.gfx.beginPass(.{
            .swapchain = sokol.glue.swapchain(),
            .action = init: {
                var pass_action: sokol.gfx.PassAction = .{};
                pass_action.colors[0].load_action = .CLEAR;
                pass_action.colors[0].clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
                break :init pass_action;
            },
        });
        sokol.gfx.applyPipeline(self._gpu_pipeline);

        var bindings: sokol.gfx.Bindings = .{};
        bindings.vertex_buffers[0] = self._gpu_vtx_buf;
        bindings.samplers[shd_desc_basic.SMP_smp] = self._gpu_sampler;

        var vtx_i: u32 = 0;
        for (self.cmd_buf.items) |cmd|
            switch (cmd) {
                .draw => |vtx_count| {
                    sokol.gfx.draw(vtx_i, vtx_count, 1);
                    vtx_i += vtx_count;
                },

                .switch_scale => |scale| {
                    sokol.gfx.applyUniforms(shd_desc_basic.UB_vert_uniform, .{
                        .ptr = &shd_desc_basic.VertUniform{ .scale_mult = .{ scale.x, scale.y } },
                        .size = @sizeOf(shd_desc_basic.VertUniform),
                    });
                },

                .switch_sheet => |view| {
                    bindings.views[shd_desc_basic.VIEW_tex] = view;
                    sokol.gfx.applyBindings(bindings);
                },
            };

        sokol.gfx.endPass();
        sokol.gfx.commit();

        self.cmd_buf.clearRetainingCapacity();
        self.vtx_buf.clearRetainingCapacity();
        self._current_gpu_view = .{ .id = sokol.gfx.invalid_id };
    }
};

/// A rendering command.
const Command = union(enum) {
    draw: u32,
    switch_scale: math.Vec2(f32),
    switch_sheet: sokol.gfx.View,
};

/// A chunk of data passed to the vertex shader.
///
/// Should be kept in sync with the shader implementation.
const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
};

/// Returns the width of the rendering viewport, in pixels.
pub fn width() u32 {
    return @intCast(sokol.app.width());
}

/// Returns the height of the rendering viewport, in pixels.
pub fn height() u32 {
    return @intCast(sokol.app.height());
}

/// Returns the width of the rendering viewport, in pixels.
pub fn widthf() f32 {
    return sokol.app.widthf();
}

/// Returns the height of the rendering viewport, in pixels.
pub fn heightf() f32 {
    return sokol.app.heightf();
}
