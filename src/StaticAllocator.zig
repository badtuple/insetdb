//! StaticAllocator is created on program startup, allocates all heap memory
//! needed, then locks so that no further memory can be allocated.
//!
//! The lifecycle is managed via an internal state machine. During the `init`
//! state alloc and resize can be called. The state then transitions to `static`
//! where memory can be used but not resized. Finally, the state transitions to
//! `deinit` where memory is freed. The state machine can only progress forward:
//! init -> static -> deinit.
const StaticAllocator = @This();

// NOTE: Tigerbeetle's implementation allows free to be called during `init`
// to allow easy errdefer. It still switches to `deinit` when this happens,
// but it feels less explicit to me. I'm going to see how long I can stand
// keeping the clear lifecycle. Their choice seems perfectly fine, but
// considering the point of the project I want to be as strict as I can.
// Perhaps the fact that this isn't a server lets me simplify things a bit.
//
// NOTE: Tigerbeetle has each component reserve their memory in the init phase.
// This seems clean when there's many different components. Since our lifecycle
// is simpler I wonder if we can just calculate everything from parameters up
// front and enforce a _single_ call to alloc for the whole program. This would
// reduce trampolining in and out of the struct quite a bit during init. I'm
// going to keep their setup for now since we're so early that I could be
// misunderstanding how many components I'll need. But I would love to
// simplify that control flow if possible. In my head, the main function would
// read like a book.

const std = @import("std");
const assert = std.debug.assert;

parent_allocator: std.mem.Allocator,
state: State,

const State = enum {
    init,
    static,
    deinit,
};

pub fn init(parent_allocator: std.mem.Allocator) StaticAllocator {
    return .{
        .parent_allocator = parent_allocator,
        .state = .init,
    };
}

pub fn deinit(self: *StaticAllocator) void {
    assert(self.state == .deinit);
    self.* = undefined;
}

pub fn transition_to_static(self: *StaticAllocator) void {
    assert(self.state == .init);
    self.state = .static;
}

pub fn transition_to_deinit(self: *StaticAllocator) void {
    assert(self.state == .static);
    self.state = .deinit;
}

pub fn allocator(self: *StaticAllocator) std.mem.Allocator {
    // TODO: assert
    return .{ .ptr = self, .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    } };
}

fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    assert(self.state == .init);

    return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
}

fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    assert(self.state == .init);

    return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
}

fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    assert(self.state == .init);

    return self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
}

fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    assert(self.state == .deinit);

    return self.parent_allocator.rawFree(buf, buf_align, ret_addr);
}
