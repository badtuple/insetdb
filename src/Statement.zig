const std = @import("std");
const assert = std.debug.assert;
const ascii = std.ascii;

const Statement = @This();
type: Type,

const Type = enum {
    insert,
    select,
};

const PrepareError = error{
    unrecognized_statement,
};

/// Prepare the Statement from raw input.
pub fn prepare(self: *Statement, input: []const u8) PrepareError!void {
    assert(input.len > 0);

    if (std.ascii.startsWithIgnoreCase(input, "insert")) {
        self.*.type = .insert;
    } else if (std.ascii.startsWithIgnoreCase(input, "select")) {
        self.*.type = .select;
    } else {
        return PrepareError.unrecognized_statement;
    }
}
