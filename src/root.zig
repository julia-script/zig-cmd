//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const expect = @import("expect").expect;

test {
    _ = @import("cmd.zig");
    _ = @import("strings.zig");
}
