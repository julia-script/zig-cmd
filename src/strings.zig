const std = @import("std");
const expect = @import("expect").expect;
const assert = std.debug.assert;
const CharClass = enum {
    upper,
    lower,
    digit,
    other,
    pub fn getClass(c: u8) CharClass {
        switch (c) {
            'A'...'Z' => return .upper,
            'a'...'z' => return .lower,
            '0'...'9' => return .digit,
            else => return .other,
        }
    }
};
const IterCaseParts = struct {
    input: []const u8,
    index: usize = 0,
    const Self = @This();
    pub fn getCurrentClass(self: *Self) CharClass {
        return CharClass.getClass(self.input[self.index]);
    }
    pub fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.input.len) return null;

        while (self.index < self.input.len and self.getCurrentClass() == .other) {
            self.index += 1;
        }
        if (self.index >= self.input.len) return null;
        const start = self.index;
        const char_class = self.getCurrentClass();

        self.index += 1;

        if (self.index >= self.input.len) return self.input[start..];

        const following_char_class = self.getCurrentClass();

        const expected_class = blk: {
            if (char_class == following_char_class) break :blk char_class;
            if (char_class == .upper and following_char_class == .lower) break :blk .lower;
            break :blk char_class;
        };

        while (self.index < self.input.len and self.getCurrentClass() == expected_class) {
            self.index += 1;
        }
        // std.debug.print("char_class: {s} following_char_class: {s} expected_class: {s}\n", .{ @tagName(char_class), @tagName(following_char_class), @tagName(expected_class) });
        if (start == self.index) return null;
        return self.input[start..self.index];
    }
};

test "IterCasePart" {
    var iter = IterCaseParts{ .input = "hello-world" };
    // _ = iter.next();
    // _ = iter.next();
    // _ = iter.next();

    try expect(iter.next().?).toBeEqualString("hello");
    try expect(iter.next().?).toBeEqualString("world");
    try expect(iter.next()).toBeNull();

    iter = IterCaseParts{ .input = "--foo-bar--" };
    try expect(iter.next().?).toBeEqualString("foo");
    try expect(iter.next().?).toBeEqualString("bar");
    try expect(iter.next()).toBeNull();

    iter = IterCaseParts{ .input = "__FOO_BAR__" };
    try expect(iter.next().?).toBeEqualString("FOO");
    try expect(iter.next().?).toBeEqualString("BAR");
    try expect(iter.next()).toBeNull();

    iter = IterCaseParts{ .input = "fooBarBaz" };
    try expect(iter.next().?).toBeEqualString("foo");
    try expect(iter.next().?).toBeEqualString("Bar");
    try expect(iter.next().?).toBeEqualString("Baz");
    try expect(iter.next()).toBeNull();
    iter = IterCaseParts{ .input = "foo-bar--.baz" };
    try expect(iter.next().?).toBeEqualString("foo");
    try expect(iter.next().?).toBeEqualString("bar");
    try expect(iter.next().?).toBeEqualString("baz");
    try expect(iter.next()).toBeNull();
}

fn toUpperCase(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - 'a' + 'A' else c;
}

fn toLowerCase(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c - 'A' + 'a' else c;
}

pub fn toUpperCamelCase(input: []const u8, buf: []u8) ![]const u8 {
    // std.debug.print("{s}\n", .{input});
    var iter = IterCaseParts{ .input = input };
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= buf.len) return error.BufferTooSmall;
        buf[i] = toUpperCase(part[0]);
        i += 1;
        for (part[1..]) |c| {
            if (i >= buf.len) return error.BufferTooSmall;
            buf[i] = toLowerCase(c);
            i += 1;
        }
    }
    return buf[0..i];
}

test "toUpperCamelCase" {
    var buf: [128]u8 = undefined;
    try expect(try toUpperCamelCase("hello-world", &buf)).toBeEqualString("HelloWorld");
    try expect(try toUpperCamelCase("foo-bar--.baz", &buf)).toBeEqualString("FooBarBaz");
    try expect(try toUpperCamelCase("foo_bar_baz", &buf)).toBeEqualString("FooBarBaz");
    try expect(try toUpperCamelCase("fooBarBaz", &buf)).toBeEqualString("FooBarBaz");
    try expect(try toUpperCamelCase("foo-bar--.baz", &buf)).toBeEqualString("FooBarBaz");
}

pub fn toCamelCase(writer: std.io.AnyWriter, input: []const u8) !void {
    var iter = IterCaseParts{ .input = input };
    var i: usize = 0;

    while (iter.next()) |part| {
        if (i > 0) {
            try writer.writeByte(toUpperCase(part[0]));
        } else {
            try writer.writeByte(toUpperCase(part[0]));
        }
        i += 1;

        for (part[1..]) |c| {
            try writer.writeByte(toLowerCase(c));
            i += 1;
        }
    }
}
pub fn toCamelCaseBuf(input: []const u8, buf: []u8) ![]const u8 {
    var iter = IterCaseParts{ .input = input };
    var i: usize = 0;

    while (iter.next()) |part| {
        if (i >= buf.len) return error.BufferTooSmall;
        if (i > 0) {
            buf[i] = toUpperCase(part[0]);
        } else {
            buf[i] = toLowerCase(part[0]);
        }
        i += 1;
        if (i >= buf.len) return error.BufferTooSmall;

        for (part[1..]) |c| {
            buf[i] = toLowerCase(c);

            i += 1;
        }
    }
    return buf[0..i];
}

test "toCamelCaseBuf" {
    var buf: [128]u8 = undefined;
    try expect(try toCamelCaseBuf("hello-world", &buf)).toBeEqualString("helloWorld");
    try expect(try toCamelCaseBuf("foo-bar-baz", &buf)).toBeEqualString("fooBarBaz");
    try expect(try toCamelCaseBuf("foo_bar_baz", &buf)).toBeEqualString("fooBarBaz");
    try expect(try toCamelCaseBuf("fooBarBaz", &buf)).toBeEqualString("fooBarBaz");
}

pub fn toSnakeCase(input: []const u8, buf: []u8) ![]const u8 {
    var iter = IterCaseParts{ .input = input };
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= buf.len) return error.BufferTooSmall;
        if (i > 0) {
            buf[i] = '_';
            i += 1;
        }
        buf[i] = toLowerCase(part[0]);
        i += 1;
        for (part[1..]) |c| {
            if (i >= buf.len) return error.BufferTooSmall;
            buf[i] = toLowerCase(c);
            i += 1;
        }
    }
    return buf[0..i];
}

test "toSnakeCase" {
    var buf: [128]u8 = undefined;
    try expect(try toSnakeCase("hello-world", &buf)).toBeEqualString("hello_world");
    try expect(try toSnakeCase("foo-bar-baz", &buf)).toBeEqualString("foo_bar_baz");
    try expect(try toSnakeCase("foo_bar_baz", &buf)).toBeEqualString("foo_bar_baz");
    try expect(try toSnakeCase("fooBarBaz", &buf)).toBeEqualString("foo_bar_baz");
}

pub fn toKebabCase(writer: std.io.AnyWriter, input: []const u8) !void {
    var iter = IterCaseParts{ .input = input };
    if (iter.next()) |part| {
        for (part) |c| {
            try writer.writeByte(toLowerCase(c));
        }
    }
    while (iter.next()) |part| {
        try writer.writeByte('-');
        for (part) |c| {
            try writer.writeByte(toLowerCase(c));
        }
    }
}

pub fn toKebabCaseBuf(input: []const u8, buf: []u8) ![]const u8 {
    var iter = IterCaseParts{ .input = input };
    var i: usize = 0;
    if (iter.next()) |part| {
        for (part) |c| {
            buf[i] = toLowerCase(c);
            i += 1;
        }
    }
    while (iter.next()) |part| {
        buf[i] = '-';
        i += 1;
        for (part) |c| {
            buf[i] = toLowerCase(c);
            i += 1;
        }
    }
    const final = buf[0..i].*;
    return &final;
}

pub fn at(T: type, s: []const T, index: isize) ?T {
    const len: isize = @intCast(s.len);
    if (index >= len) return null;
    if (index < 0 and -index <= len) {
        return s[@intCast(len + index)];
    }
    return s[@intCast(index)];
}

test "at" {
    try expect(at(u8, "hello", 1).?).toBe('e');
    try expect(at(u8, "hello", -1).?).toBe('o');
}

// const PatternAst = struct {
//     const Self = @This();
//     const Node = union(enum) {
//         literal: u8,
//         empty: void,
//         alternative: struct {
//             lhs: *Node,
//             rhs: *Node,
//         },
//         disjunction: struct {
//             lhs: *Node,
//             rhs: *Node,
//         },
//         capturing: struct {
//             node: *Node,
//             backwards: bool,
//         },
//         lookahead: struct {
//             node: *Node,
//             backwards: bool,
//             lookaround_sense: bool,
//         },
//         utf8_dot: void,
//         start: void,
//         end: void,
//     };

//     pos: usize = 0,
//     source: []const u8,
//     mode: Mode = .perl,
//     allow_lookbehind: bool = false,
//     allow_lenient: bool = false,
//     // current: u8,
//     const Mode = enum {
//         perl,
//     };
//     pub fn getToken(self: *Self) ?u8 {
//         if (self.pos >= self.source.len) return null;
//         return self.source[self.pos];
//     }

//     pub fn consumeToken(self: *Self) void {
//         self.pos += 1;
//     }
//     pub fn accept(self: *Self, token: u8) bool {
//         if (self.getToken() != token) return false;
//         self.consumeToken();
//         return true;
//     }
//     pub fn parseTerm(self: *Self) !Node {
//         _ = self; // autofix
//         return error.unimplemented;
//     }
//     pub fn parseAtom(self: *Self) ?Node {
//         if (self.accept('(')) {
//             var capturing = true;
//             var lookaround = false;
//             var lookaround_sense = false;
//             var lookahead = true;
//             if (self.accept('?')) {
//                 if (self.mode == .perl and self.accept('#')) {
//                     const saved_pos = self.pos;
//                     while (!self.accept(')')) {
//                         if (self.getToken() == null) {
//                             self.pos = saved_pos - 1;
//                             @compileError("Missing end of (?#...) comment");
//                         }
//                         self.accept(self.getToken() orelse unreachable);
//                     }
//                     self.accept(')');
//                     return .{ .empty = {} };
//                 }
//                 if (self.accept('<')) {
//                     if (!self.allow_lookbehind) {
//                         @compileError("Lookbehind not available in " ++ @tagName(self.mode) ++ " mode");
//                     }
//                     lookahead = false;
//                 }
//                 if (self.accept('=')) {
//                     lookaround = true;
//                     lookaround_sense = true;
//                 } else if (self.accept('!')) {
//                     lookaround = true;
//                     lookaround_sense = false;
//                 } else {
//                     try self.expect(':');
//                 }

//                 if (!lookahead and !lookaround) {
//                     @compileError("(?< must be followed by = or !");
//                 }
//                 capturing = false;
//             }
//             var node: Node = undefined;
//             if (!capturing) {
//                 const old_direction = self.backwards;
//                 if (lookaround) self.backwards = !lookahead;
//                 node = self.parseDisjunction();
//                 self.backwards = old_direction;
//             } else {
//                 node = self.parseDisjunction();
//             }

//             if (capturing) node = .{ .capturing = .{ .node = node, .backwards = self.backwards } };
//             if (lookaround) node = .{ .lookahead = .{ .node = node, .backwards = self.backwards, .lookaround_sense = lookaround_sense } };
//             self.expect(')');
//             return node;
//         }
//         var current = self.getToken();
//         if (current == null or current == ')' or current == '|') return null;

//         if (self.accept('.')) return .{ .utf8_dot = {} };
//         if (self.accept('\\')) return self.parseEscape();
//         if (self.accept('[')) return self.parseCharClass();
//         if (self.accept('*') or self.accept('?') or self.accept('+')) @compileError("Unexpected quantifier");

//         current = self.getToken();

//         if ((current == '{' or current == '}') and !self.allow_lenient) @compileError("Literal { and } must be escaped in " ++ @tagName(self.mode) ++ " mode");

//         self.checkForNull();
//         const ast = .{ .literal = current.? };
//     }
//     pub fn checkForNull(self: *Self) void {
//         _ = self; // autofix
//         @compileError("unimplemented");
//     }
//     pub fn parseEscape(self: *Self) Node {
//         _ = self; // autofix
//         @compileError("unimplemented");
//     }
//     pub fn parseCharClass(self: *Self) Node {
//         _ = self; // autofix
//         @compileError("unimplemented");
//     }
//     pub fn expect(self: *Self, token: u8) void {
//         if (self.getToken() != token) {
//             @compileError("Unexpected token: " ++ @tagName(self.getToken()));
//         }
//         self.consumeToken();
//     }
//     pub fn parseAlternative(self: *Self) Node {
//         if (self.accept('^')) return .{ .start = {} };
//         if (self.accept('$')) return .{ .end = {} };

//         @compileError("unimplemented");
//         // const node = self.parseLiteral();
//         // return self.accept('|');
//     }
//     pub fn parseDisjunction(self: *Self) Node {
//         const node = self.parseAlternative();
//         _ = node; // autofix
//         return self.accept('|');
//     }
//     pub fn from(p: []const u8) Self {
//         var i: usize = 0;
//         while (i < p.len) {
//             // const c = p[i];
//             // var is_disjunction = false;
//             // var is_alternative = false;

//             // const next_c = at(u8, p, i + 1);

//             // _ = c; // autofix
//             i += 1;
//         }
//         return .{ .root = undefined };
//     }
// };
// fn Pattern(comptime p: []const u8) type {
//     _ = p; // autofix
//     return struct {
//         const Self = @This();

//         pub inline fn match(string: []const u8) bool {
//             _ = string; // autofix

//             // comptime var p_index: usize = 0;
//             // while (p_index < p.len) {
//             //     const p_char = p[p_index];
//             //     _ = p_char; // autofix

//             //     const next_p_char = at(u8, p, p_index + 1) orelse 0;
//             //     _ = next_p_char; // autofix
//             // }
//             return false;
//         }
//         // pub inline fn match(self: *Self, c: ?u8) bool {
//         //     _ = self; // autofix
//         //     _ = c; // autofix
//         //     return false;
//         // }
//     };
// }
// // pub fn match(comptime pattern: []const u8, s: []const u8) bool {
// //     comptime var p_index: usize = 0;
// //     while (p_index < pattern.len) {
// //         const p = pattern[p_index];
// //         _ = p; // autofix
// //         const next_p = at(u8, pattern, p_index + 1) orelse 0;

// //         _ = next_p; // autofix
// //     }

// //     _ = s; // autofix
// //     return false;
// // }

// test "match" {
//     // try expect(match(u8, "hello"));
// }
