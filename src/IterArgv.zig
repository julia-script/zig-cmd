const std = @import("std");
const expect = @import("expect").expect;
pub const OsArg = [*:0]const u8;

argv: []const OsArg,
i: usize = 0,
peeked: ?Entry = null,

const Self = @This();

pub const Entry = struct {
    key: []const u8,
    value: []const u8,
    kind: Kind,
    pub const Kind = enum {
        short_flag,
        long_flag,
        value,

        pub fn fromArg(arg: OsArg) Kind {
            if (arg[0] == '-') {
                if (arg[1] == '-' and std.ascii.isAlphabetic(arg[2])) return .long_flag;
                if (std.ascii.isAlphabetic(arg[1])) return .short_flag;
            }
            return .value;
        }
    };
};

pub fn init(argv: []const OsArg) Self {
    var iter = Self{ .argv = argv };
    _ = iter.next();
    return iter;
}

pub fn next(self: *@This()) ?Entry {
    const current = self.peeked;

    self.peeked = if (self.i >= self.argv.len) null else blk: {
        const arg = self.argv[self.i];

        const kind = Entry.Kind.fromArg(arg);
        const slice = arg[0..std.mem.indexOfSentinel(u8, 0, arg)];
        const key = switch (kind) {
            .short_flag, .long_flag => slice[0 .. std.mem.indexOfScalar(u8, slice, '=') orelse slice.len],
            .value => "",
        };

        const value: []const u8 = switch (kind) {
            .short_flag,
            .long_flag,
            => arg: {
                if (key.len < slice.len) {
                    break :arg slice[key.len + 1 ..];
                }
                const next_i = self.i + 1;
                if (next_i >= self.argv.len or Entry.Kind.fromArg(self.argv[next_i]) != .value) break :arg "";
                self.i += 1;
                break :arg self.argv[next_i][0..std.mem.indexOfSentinel(u8, 0, self.argv[next_i])];
            },
            .value => slice,
        };

        self.i += 1;
        break :blk Entry{
            .key = key,
            .value = value,
            .kind = kind,
        };
    };
    return current;
}

test "IterArgv" {
    var iter = Self.init(&.{ "foo", "--bar", "baz", "-a", "-b", "1,2,3,4", "-b=2" });
    try expect(iter.peeked.?.kind).toBe(.value);
    try expect(iter.peeked.?.key).toBeEqualString("");
    try expect(iter.peeked.?.value).toBeEqualString("foo");
    _ = iter.next();

    try expect(iter.peeked.?.kind).toBe(.long_flag);
    try expect(iter.peeked.?.key).toBeEqualString("--bar");
    try expect(iter.peeked.?.value).toBeEqualString("baz");

    _ = iter.next();
    try expect(iter.peeked.?.kind).toBe(.short_flag);
    try expect(iter.peeked.?.key).toBeEqualString("-a");
    try expect(iter.peeked.?.value).toBeEqualString("");

    _ = iter.next();
    try expect(iter.peeked.?.kind).toBe(.short_flag);
    try expect(iter.peeked.?.key).toBeEqualString("-b");
    try expect(iter.peeked.?.value).toBeEqualString("1,2,3,4");

    _ = iter.next();
    try expect(iter.peeked.?.kind).toBe(.short_flag);
    try expect(iter.peeked.?.key).toBeEqualString("-b");
    try expect(iter.peeked.?.value).toBeEqualString("2");

    _ = iter.next();
    try expect(iter.peeked).toBeNull();
}
