const std = @import("std");
const assert = std.debug.assert;
const ascii = std.ascii;

const Statement = @This();
type: Type,
state: State = .unprepared,

const Type = enum {
    insert,
    select,
};

const State = enum {
    unprepared,
    prepared,
};

const PrepareError = error{
    unrecognized_statement,
};

/// Prepare the Statement from raw input.
pub fn prepare(self: *Statement, input: []const u8) PrepareError!void {
    assert(input.len > 0);
    assert(self.state == .unprepared);

    if (std.ascii.startsWithIgnoreCase(input, "insert")) {
        self.type = .insert;
    } else if (std.ascii.startsWithIgnoreCase(input, "select")) {
        self.type = .select;
    } else {
        return PrepareError.unrecognized_statement;
    }

    self.state = .prepared;
    assert(self.state == .prepared);
}
