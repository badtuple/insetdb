const std = @import("std");
const Io = std.Io;

const assert = std.debug.assert;

/// constants is a list of all compiletime known configuration and constants.
/// This is used to calculate needed startup resources, assert relations between
/// constants, and serve as a place to document the values themselves.
///
/// NOTE: Tigerbeetle actually pulls in non-comptime config to a similar struct
/// to calculate everything and treats them as constants for the lifetime of the
/// program. This is cool. The eventual library nature of insetdb may mean our
/// architecture is slightly different, and even if it's not I'd argue
/// "constants" is sort of a terrible name for something that calculates values
/// on startup. But philosophically it makes sense. Everything is comptime known
/// for us for now, so I'm just going to use the same `constants` name they use.
/// But I feel like I'll deviate from this pattern pretty quick and collapse it
/// into a Config.
const constants = struct {
    const KiB = 1 << 10;
    const MiB = 1 << 20;

    comptime {
        assert(KiB == 1024);
        assert(MiB == 1024 * KiB);
    }

    /// repl_buffer_size is the maximum amount that can be input into the repl.
    /// Realistically this is more than anyone would input manually. But it is
    /// currently our only input method.
    ///
    /// SQLite's SQLITE_LIMIT_SQL_LENGTH is a Gigabyte (1_000_000_000 bytes.)
    /// That feels excessive, but people do some wacky stuff. Clearly we'll have
    /// to do some research on standard sizes and what's reasonable as things
    /// progress. This is also relatively easy to expose as a library param
    /// with some max upper limit.
    pub const repl_buffer_size = 4 * MiB;
};

/// StaticAllocator is created on program startup, allocates all heap memory
/// needed, then locks so that no further memory can be allocated.
///
/// The lifecycle is managed via an internal state machine. During the `init`
/// state alloc and resize can be called. The state then transitions to `static`
/// where memory can be used but not resized. Finally, the state transitions to
/// `deinit` where memory is freed. The state machine can only progress forward:
/// init -> static -> deinit.
///
/// NOTE: Tigerbeetle's implementation allows free to be called during `init`
/// to allow easy errdefer. It still switches to `deinit` when this happens,
/// but it feels less explicit to me. I'm going to see how long I can stand
/// keeping the clear lifecycle. Their choice seems perfectly fine, but
/// considering the point of the project I want to be as strict as I can.
/// Perhaps the fact that this isn't a server lets me simplify things a bit.
///
/// NOTE: Tigerbeetle has each component reserve their memory in the init phase.
/// This seems clean when there's many different components. Since our lifecycle
/// is simpler I wonder if we can just calculate everything from parameters up
/// front and enforce a _single_ call to alloc for the whole program. This would
/// reduce trampolining in and out of the struct quite a bit during init. I'm
/// going to keep their setup for now since we're so early that I could be
/// misunderstanding how many components I'll need. But I would love to
/// simplify that control flow if possible. In my head, the main function would
/// read like a book.
const StaticAllocator = struct {
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
};

const Repl = struct {
    io: Io,
    allocator: std.mem.Allocator,

    buf: [constants.repl_buffer_size]u8,
    stdin: std.Io.File,
    stdout: std.Io.File,
    stdin_reader: std.Io.File.Reader,

    // Used to signal that the repl should close.
    event_loop_done: bool,

    fn init(self: *Repl, io: Io, allocator: std.mem.Allocator) void {
        self.* = .{
            .io = io,
            .allocator = allocator,

            .buf = undefined,
            .stdin = std.Io.File.stdin(),
            .stdout = std.Io.File.stdout(),
            // Set below, once `buf`'s address is stable.
            .stdin_reader = undefined,

            .event_loop_done = false,
        };

        self.stdin_reader = self.stdin.reader(io, &self.buf);
    }

    fn print_prompt(self: *Repl) !void {
        try self.stdout.writeStreamingAll(self.io, "> ");
    }

    fn print(self: *Repl, output: []const u8) !void {
        try self.stdout.writeStreamingAll(self.io, output);
    }

    /// read_input returns the next line of input excluding the delimiter. A
    /// `null` return signals end-of-stream (e.g. the user pressed Ctrl-D).
    fn read_input(self: *Repl) !?[]u8 {
        return try self.stdin_reader.interface.takeDelimiter('\n');
    }

    fn shutdown(self: *Repl) void {
        // TODO: Cleanup. Leaving for when we have stuff to cleanup. For
        // instance persisting repl history.

        self.event_loop_done = true;
    }
};

pub fn main(init: std.process.Init) !void {
    var alloc = StaticAllocator.init(init.gpa);
    const gpa = alloc.allocator();

    // Initialize all components.
    var repl: Repl = undefined;
    repl.init(init.io, gpa);

    // Freeze allocator.
    alloc.transition_to_static();
    defer {
        alloc.transition_to_deinit();
        alloc.deinit();
    }

    // NOTE: The NASA Power of Ten says to "assert" loops that are explicitly
    // unbounded such as event loops. For a repl, I'm not sure how they expect
    // us to "assert" that in a literal sense. Looking at TigerBeetle as a
    // reference, their repl contains a "event_loop_done" condition used as a
    // flag from their state machine. I don't think this would count as an
    // assertion. Weird to start off the project explicitly breaking a rule, but
    // it does seem like this is considered an exception. The only thing I can
    // think to do is put a limit on the number of queries you can exec from a
    // repl instance. I'll leave as is and see if I can think of something that
    // would ensure there is no runaway infinite loop that'd lock up. Perhaps
    // a tick counter that ensures work was done for each tick increment? At
    // least then we could identify a logic bug causing a busy loop.
    while (!repl.event_loop_done) {
        try repl.print_prompt();
        const input = try repl.read_input() orelse {
            // End-of-stream. Treating it as an explicit exit.
            repl.shutdown();
            continue;
        };

        if (input.len == 0) {
            continue;
        }

        if (std.mem.eql(u8, input, ".exit")) {
            repl.shutdown();
        } else {
            try repl.print("unrecognized command\n");
        }
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
