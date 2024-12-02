//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const cmd = @import("cmd.zig");
export const program = cmd.program;

test {
    _ = @import("cmd.zig");
    _ = @import("strings.zig");
}
