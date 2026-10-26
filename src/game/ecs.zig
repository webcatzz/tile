const std = @import("std");
const zflecs = @import("zflecs");

/// A unique ID representing an entity.
const Entity = struct { _inner: zflecs.entity_t };

pub const World = struct {
    world: *zflecs.world_t,

    /// Returns a new world.
    ///
    /// The world is owned by the caller and should be freed by calling
    /// `deinit`.
    pub fn init() World {
        return .{ .world = zflecs.init() };
    }

    /// Frees the world.
    ///
    /// The world should not be used after calling this function.
    pub fn deinit(self: *World) void {
        _ = zflecs.fini(self.world);
        self.* = undefined;
    }

    /// Registers `T` as a component type.
    pub fn registerComponent(self: *World, comptime T: type) void {
        zflecs.COMPONENT(self.world, T);
    }

    /// Returns a new entity with the given components.
    pub fn new(self: *World, comptime cmpts: []const type) Entity {
        var add: [cmpts.len:0]zflecs.id_t = undefined;
        inline for (cmpts, 0..) |cmpt, i|
            add[i] = zflecs.id(cmpt);

        return .{
            ._inner = zflecs.entity_init(self.world, &.{
                .add = &add,
            }),
        };
    }

    /// Sets the given component on the given entity.
    pub fn set(self: *World, entity: Entity, comptime T: type, v: T) void {
        _ = zflecs.set(self.world, entity._inner, T, v);
    }

    /// Runs the given system in the world.
    ///
    /// `Sys` should be a function of the following form:
    ///
    /// ```
    /// fn (ctx: @TypeOf(ctx), cmpt1: Cmpt1, cmpt2: Cmpt2, ...) !void
    /// ```
    ///
    /// Specifically, its first parameter should always be its context (even if
    /// `void`), and the following parameters should always be components.
    pub fn run(
        self: *World,
        comptime sys: anytype,
        ctx: (@typeInfo(@TypeOf(sys)).@"fn".param_types[0] orelse @compileError("System parameters should not be generic")),
    ) !void {
        const fn_info = @typeInfo(@TypeOf(sys)).@"fn";

        // Constructs list of components invoked by the system

        const cmpts, const cmpts_is_ptr = comptime init: {
            var cmpts: [fn_info.param_types.len - 1]type = undefined;
            var cmpts_is_ptr: [cmpts.len]bool = undefined;

            for (fn_info.param_types[1..], 0..) |maybe_ptype, i| {
                const ptype = maybe_ptype orelse
                    @compileError("System parameters should not be generic");
                switch (@typeInfo(ptype)) {
                    .pointer => |ptr_info| {
                        cmpts[i] = ptr_info.child;
                        cmpts_is_ptr[i] = true;
                    },
                    else => {
                        cmpts[i] = ptype;
                        cmpts_is_ptr[i] = false;
                    },
                }
            }

            break :init .{ cmpts, cmpts_is_ptr };
        };

        // Constructs tuple types used during iteration

        const Fields = comptime init: {
            var field_types: [cmpts.len]type = undefined;
            for (&field_types, cmpts) |*field_type, cmpt|
                field_type.* = []cmpt;
            break :init @Tuple(&field_types);
        };

        const Args = comptime init: {
            var field_types: [cmpts.len + 1]type = undefined;
            field_types[0] = @TypeOf(ctx);
            for (field_types[1..], cmpts, cmpts_is_ptr) |*field_type, cmpt, cmpt_is_ptr|
                field_type.* = if (cmpt_is_ptr) *cmpt else cmpt;
            break :init @Tuple(&field_types);
        };

        // Starts query

        var query_desc: zflecs.query_desc_t = .{};
        inline for (cmpts, 0..) |Cmpt, i|
            query_desc.terms[i].id = zflecs.id(Cmpt);

        const query = try zflecs.query_init(self.world, &query_desc);
        var query_iter = zflecs.query_iter(self.world, query);

        while (zflecs.query_next(&query_iter)) {
            // Collects component lists

            var fields: Fields = undefined;
            inline for (cmpts, 0..) |Cmpt, i|
                fields[i] = zflecs.field(&query_iter, Cmpt, i).?;

            for (0..query_iter.count()) |i| {
                // Collects system arguments

                var args: Args = undefined;
                args[0] = ctx;
                inline for (fields, cmpts_is_ptr, 0..) |field, cmpt_is_ptr, cmpt_i|
                    args[cmpt_i + 1] = if (cmpt_is_ptr)
                        &field[i]
                    else
                        field[i];

                // Calls system

                const ret = @typeInfo(@typeInfo(@TypeOf(sys)).@"fn".return_type orelse
                    @compileError("System return type should not be generic"));
                switch (ret) {
                    .void => @call(.auto, sys, args),
                    .error_union => try @call(.auto, sys, args),
                    else => @compileError("System return type should be `void` or `!void`"),
                }
            }
        }

        zflecs.query_fini(query);
    }
};
