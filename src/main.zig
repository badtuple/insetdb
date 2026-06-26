const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const StaticAllocator = @import("StaticAllocator.zig");
const Repl = @import("Repl.zig");
const constants = @import("constants.zig");

pub fn main(init: std.process.Init) !void {
    var alloc = StaticAllocator.init(init.gpa);
    const gpa = alloc.allocator();

    // Initialize all components.
    var repl: Repl = undefined;
    try repl.init(init.io, gpa);

    // Freeze allocator.
    alloc.transition_to_static();
    defer {
        alloc.transition_to_deinit();
        repl.deinit();
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
