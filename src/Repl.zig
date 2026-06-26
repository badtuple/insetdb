const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const constants = @import("constants.zig");

const Repl = @This();

io: Io,
allocator: std.mem.Allocator,

buf: []u8,
stdin: std.Io.File,
stdout: std.Io.File,
stdin_reader: std.Io.File.Reader,

// Used to signal that the repl should close.
event_loop_done: bool,

pub fn init(self: *Repl, io: Io, allocator: std.mem.Allocator) !void {
    self.* = .{
        .io = io,
        .allocator = allocator,

        .buf = try allocator.alloc(u8, constants.repl_buffer_size),
        .stdin = std.Io.File.stdin(),
        .stdout = std.Io.File.stdout(),
        // Set below, once `buf` is stored on `self`.
        .stdin_reader = undefined,

        .event_loop_done = false,
    };

    self.stdin_reader = self.stdin.reader(io, self.buf);

    assert(self.buf.len == constants.repl_buffer_size);
    assert(self.event_loop_done == false);
}

pub fn deinit(self: *Repl) void {
    self.allocator.free(self.buf);
    self.* = undefined;
}

pub fn print_prompt(self: *Repl) !void {
    try self.stdout.writeStreamingAll(self.io, "> ");
}

pub fn print(self: *Repl, output: []const u8) !void {
    try self.stdout.writeStreamingAll(self.io, output);
}

/// read_input returns the next line of input excluding the delimiter. A
/// `null` return signals end-of-stream (e.g. the user pressed Ctrl-D).
pub fn read_input(self: *Repl) !?[]u8 {
    return try self.stdin_reader.interface.takeDelimiter('\n');
}

pub fn shutdown(self: *Repl) void {
    assert(!self.event_loop_done); // Only call shutdown once.

    self.event_loop_done = true;
}
