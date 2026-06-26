//! constants is a list of all compiletime known configuration and constants.
//! This is used to calculate needed startup resources, assert relations between
//! constants, and serve as a place to document the values themselves.

// NOTE: Tigerbeetle actually pulls in non-comptime config to a similar struct
// to calculate everything and treats them as constants for the lifetime of the
// program. This is cool. The eventual library nature of insetdb may mean our
// architecture is slightly different, and even if it's not I'd argue
// "constants" is sort of a terrible name for something that calculates values
// on startup. But philosophically it makes sense. Everything is comptime known
// for us for now, so I'm just going to use the same `constants` name they use.
// But I feel like I'll deviate from this pattern pretty quick and collapse it
// into a Config.

const std = @import("std");
const assert = std.debug.assert;

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
comptime {
    // ensure repl_buffer_size is a power of 2 and not 0
    assert(repl_buffer_size & (repl_buffer_size - 1) == 0);
    assert(repl_buffer_size > 0);
}
