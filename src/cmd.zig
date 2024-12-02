const std = @import("std");
const expect = @import("expect").expect;
const strings = @import("strings.zig");
const IterArgv = @import("IterArgv.zig");

pub const Meta = struct {
    pub const Option = struct {
        description: ?[]const u8 = null,
        short_alias: ?u8 = null,
        display_name: ?[]const u8 = null,
        is_argument: bool = false,
        hide_from_help: bool = false,
        display_options: bool = true,
    };

    pub fn Program(comptime T: type) type {
        const parent_fields = std.meta.fields(T);
        comptime var fields: [parent_fields.len + 2]std.builtin.Type.StructField = undefined;
        const DEFAULT_VALUE: ?Meta.Option = null;
        inline for (parent_fields, 0..) |field, i| {
            fields[i] = .{
                .name = field.name,
                .type = ?Meta.Option,
                .default_value = @as(*const anyopaque, @ptrCast(&DEFAULT_VALUE)),
                .is_comptime = false,
                .alignment = @alignOf(?Meta.Option),
            };
        }
        fields[parent_fields.len] = .{
            .name = "help",
            .type = ?Meta.Option,
            .default_value = @as(*const anyopaque, @ptrCast(&DEFAULT_VALUE)),
            .is_comptime = false,
            .alignment = @alignOf(?Meta.Option),
        };

        fields[parent_fields.len + 1] = .{
            .name = "version",
            .type = ?Meta.Option,
            .default_value = @as(*const anyopaque, @ptrCast(&DEFAULT_VALUE)),
            .is_comptime = false,
            .alignment = @alignOf(?Meta.Option),
        };

        const OptionsProp: type = @Type(.{ .@"struct" = .{
            .fields = &fields,
            .is_tuple = false,
            .layout = .auto,
            .decls = &.{},
        } });

        return struct {
            name: []const u8,
            version: ?[]const u8 = null,
            description: ?[]const u8 = null,
            arg_name: ?[]const u8 = null,
            options: OptionsProp = .{},
            commands: []const type = &.{},
        };
    }

    pub fn Commands(comptime T: anytype) type {
        _ = T; // autofix
        return struct {
            // sub: Meta.Program(T),
        };
    }
};

fn getMetadataField(comptime T: type, comptime F: type, comptime field: []const u8) ?F {
    comptime {
        if (@hasDecl(T, "metadata")) {
            const metadata = T.metadata;
            return @field(metadata, field);
        }
        return null;
    }
}
pub fn getMetadata(comptime T: type) ?Meta.Program(T) {
    comptime {
        if (@hasDecl(T, "metadata")) {
            return T.metadata;
        }
        return null;
    }
}
fn Unwrap(T: type) type {
    switch (@typeInfo(T)) {
        .optional => |o| return o.child,
        else => return T,
    }
}
fn isOptional(T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => true,
        else => false,
    };
}

inline fn get(T: type, value: anytype, comptime path: anytype) ?Unwrap(T) {
    comptime {
        const unwrapped = blk: {
            if (isOptional(@TypeOf(value))) {
                if (value) |v| {
                    break :blk v;
                }
                return null;
            }
            break :blk value;
        };

        const field_name, const rest = blk: {
            const field_name_end = std.mem.indexOfScalar(u8, path, '.');
            if (field_name_end) |end| {
                break :blk .{ path[0..end], path[end + 1 ..] };
            }
            return @field(unwrapped, path);
        };
        return get(T, @field(unwrapped, field_name), rest);
    }
}
test "get" {
    const S = struct {
        a: ?struct {
            b: []const u8,
        },
    };

    try expect(get([]const u8, S{
        .a = .{
            .b = "abc",
        },
    }, "a.b").?).toBeEqualString("abc");

    try expect(get([]const u8, S{
        .a = null,
    }, "a.b")).toBeNull();

    try expect(get([]const u8, @as(?S, null), "a.b")).toBeNull();
}

const FormattedOption = struct {
    is_argument: bool = false,
    type: type,
    default_value: ?*const anyopaque = null,
    is_required: bool,
    arg_name: []const u8,
    field_name: []const u8,
    alias: ?[]const u8 = null,
    hide_from_help: bool = false,

    description: []const u8,
    default_value_help: []const u8 = "",

    // help_args_column: []const u8,
    help_type: []const u8,
    options: []const []const u8,
    display_options: bool = true,
};

fn formatTypeInner(comptime T: type) []const u8 {
    comptime {
        const info = @typeInfo(T);
        switch (info) {
            .optional => |optional| return formatTypeInner(optional.child),
            .pointer => |ptr| {
                switch (T) {
                    []const u8 => return "string",
                    else => return ".." ++ formatTypeInner(ptr.child),
                }
            },

            .array => |_| return "array",
            .@"enum" => {
                const name = @typeName(T);
                const i = std.mem.lastIndexOfScalar(u8, name, '.') orelse 0;
                var b: [name.len]u8 = undefined;
                const short_name = strings.toKebabCaseBuf(name[i + 1 ..], &b) catch unreachable;
                return short_name;
            },
            .int, .float => return "number",
            else => return @typeName(T),
        }
    }
}
inline fn formatType(comptime T: type, has_default: bool) []const u8 {
    comptime {
        const Unwrapped = Unwrap(T);

        if (has_default or std.meta.activeTag(@typeInfo(T)) == .optional) {
            return "[" ++ formatTypeInner(Unwrapped)[0..] ++ "]";
        }
        return "<" ++ formatTypeInner(Unwrapped)[0..] ++ ">";
    }
}

test "formatType" {
    try expect(formatType([]const u8, false)).toBeEqualString("<string>");
    try expect(formatType([]const u8, true)).toBeEqualString("[string]");
    try expect(formatType(?[]const u8, true)).toBeEqualString("[string]");
    try expect(formatType(bool, false)).toBeEqualString("<bool>");
    try expect(formatType(bool, true)).toBeEqualString("[bool]");
    try expect(formatType(u8, false)).toBeEqualString("<number>");
    try expect(formatType(u8, true)).toBeEqualString("[number]");
}
fn normalizeToStringSlice(comptime val: anytype) []const u8 {
    const T = @TypeOf(val);
    const type_info = @typeInfo(T);
    // @compileLog(type_info);
    switch (T) {
        []const u8 => return val,
        [:0]u8 => return val[0..],
        else => {},
    }

    switch (type_info) {
        .pointer => {
            return normalizeToStringSlice(val.*);
        },
        .array => |arr| {
            if (arr.child != u8) {
                @compileError("Not a string: " ++ @typeName(T));
            }

            return val[0..];
        },
        else => {},
    }
    @compileError("Not a string: " ++ @typeName(T));
}

inline fn formatDefault(comptime val: anytype) []const u8 {
    const T = @TypeOf(val);

    switch (@typeInfo(T)) {
        .optional => return if (val) |v| formatDefault(v) else "null",
        .bool => return if (val) "true" else "false",
        .@"enum" => {
            const name = @tagName(val);
            var buf: [name.len]u8 = undefined;
            return "'" ++ (strings.toKebabCaseBuf(name, &buf) catch unreachable) ++ "'";
        },

        .array => |arr| {
            if (arr.child != u8) {
                return std.fmt.comptimePrint("{any}", .{val});
            }
            return std.fmt.comptimePrint("\"{s}\"", .{val[0..]});
        },
        .pointer => |ptr| {
            switch (T) {
                []const u8 => return "\"" ++ val[0..] ++ "\"",
                else => {
                    switch (ptr.child) {
                        u8 => return std.fmt.comptimePrint("{s}", .{val}),
                        else => {},
                    }
                    switch (@typeInfo(ptr.child)) {
                        .int, .float, .comptime_int, .comptime_float => return std.fmt.comptimePrint("{d}", .{val}),
                        .pointer => return formatDefault(val.*),
                        else => return @typeName(T),
                    }
                },
            }
        },
        .int, .float, .comptime_int, .comptime_float => return std.fmt.comptimePrint("{d}", .{val}),
        else => return std.fmt.comptimePrint("{any}", .{val}),
    }
}

test "formatDefault" {
    try expect(formatDefault(true)).toBeEqualString("true");
    try expect(formatDefault(false)).toBeEqualString("false");
    try expect(formatDefault(1)).toBeEqualString("1");
    try expect(formatDefault(1.0)).toBeEqualString("1");
    // try expect(formatDefault("abc")).toBeEqualString("\"abc\"");
}
pub fn program(comptime T: type) type {
    comptime {
        const metadata = getMetadata(T);
        const fields = std.meta.fields(T);

        const formatted_options: []const FormattedOption, const formatted_arguments: []const FormattedOption = blk: {
            const has_version = metadata != null and metadata.?.version != null and metadata.?.version.?.len > 0;
            var options: [fields.len + if (has_version) 2 else 1]FormattedOption = undefined;
            var arguments: [fields.len]FormattedOption = undefined;
            var options_index: usize = 0;
            var arguments_index: usize = 0;
            for (fields) |field| {
                var buf: [field.name.len]u8 = undefined;
                const arg_name = strings.toKebabCaseBuf(field.name, &buf) catch unreachable;

                const alias: ?[1]u8, const is_argument, const description, const hide_from_help, const display_name, const display_options = meta: {
                    if (metadata) |m| {
                        if (@field(m.options, field.name)) |opt| {
                            break :meta .{
                                if (opt.short_alias) |a| [1]u8{a} else null,
                                opt.is_argument,
                                opt.description orelse "",
                                opt.hide_from_help,
                                opt.display_name,
                                opt.display_options,
                            };
                        }
                    }
                    break :meta .{
                        null,
                        false,
                        "",
                        false,
                        null,
                        true,
                    };
                };

                const formatted = FormattedOption{
                    .is_argument = is_argument,
                    .type = field.type,
                    .default_value = field.default_value,
                    .is_required = field.default_value == null and std.meta.activeTag(@typeInfo(field.type)) != .optional,

                    .field_name = field.name,
                    .arg_name = arg_name,
                    .alias = if (alias) |a| &a else null,
                    .description = description,
                    .hide_from_help = hide_from_help,
                    .help_type = type: {
                        if (display_name) |name| {
                            break :type name;
                        }
                        break :type formatType(field.type, field.default_value != null);
                    },
                    .options = options: {
                        switch (@typeInfo(field.type)) {
                            .@"enum" => |info| {
                                var opt: [info.fields.len][]const u8 = undefined;
                                for (info.fields, 0..) |f, j| {
                                    var options_buf: [f.name.len]u8 = undefined;
                                    const name = strings.toKebabCaseBuf(f.name, &options_buf) catch unreachable;
                                    opt[j] = name;
                                }
                                const final_options = opt[0..].*;
                                break :options &final_options;
                            },
                            else => {},
                        }
                        break :options &.{};
                    },
                    .display_options = display_options,
                    .default_value_help = default_value_help: {
                        if (field.default_value) |v| {
                            const res: T = undefined;
                            const O = @TypeOf(&@field(res, field.name));
                            const default_value = @as(O, @ptrCast(@alignCast(@constCast(v)))).*;
                            break :default_value_help formatDefault(default_value);
                        }
                        break :default_value_help "";
                    },
                };

                if (is_argument) {
                    arguments[arguments_index] = formatted;

                    if (arguments_index > 0 and formatted.is_required and !arguments[arguments_index - 1].is_required) {
                        @compileError("Required arguments can't follow optional arguments: " ++ formatted.arg_name);
                    }
                    arguments_index += 1;
                } else {
                    options[options_index] = formatted;
                    options_index += 1;
                }
            }

            const help_meta = if (metadata) |m| m.options.help else null;
            const version_meta = if (metadata) |m| m.options.version else null;
            options[options_index] = FormattedOption{
                .is_argument = false,
                .type = bool,
                .default_value = null,
                .hide_from_help = if (help_meta) |h| h.hide_from_help else false,
                .help_type = formatType(?bool, true),
                .options = &.{},
                .is_required = false,
                .arg_name = if (help_meta) |h| h.arg_name orelse "help" else "help",
                .field_name = "help",
                .description = if (help_meta) |h| h.description orelse "display help information" else "display help information",
                .alias = if (help_meta) |h| h.short_alias else "h",
            };
            options_index += 1;
            if (has_version) {
                options[options_index] = FormattedOption{
                    .is_argument = false,
                    .type = bool,
                    .default_value = null,
                    .hide_from_help = if (version_meta) |v| v.hide_from_help else false,
                    .help_type = formatType(?bool, true),
                    .options = &.{},
                    .is_required = false,
                    .arg_name = if (version_meta) |v| v.arg_name orelse "version" else "version",
                    .field_name = "version",
                    .description = if (version_meta) |v| v.description orelse "output the version number" else "output the version number",
                    .alias = if (version_meta) |v| v.short_alias else "v",
                };
                options_index += 1;
            }
            const final_options = options[0..options_index].*;
            const final_arguments = arguments[0..arguments_index].*;

            break :blk .{ &final_options, &final_arguments };
        };
        return struct {
            pub const name = blk: {
                if (metadata) |m| break :blk m.name;
                break :blk "";
            };
            fn printUsage(writer: std.io.AnyWriter) !void {
                _ = writer; // autofix
            }
            const PadDirection = enum {
                left,
                right,
            };
            inline fn pad(comptime direction: PadDirection, comptime s: []const u8, comptime n: usize) []const u8 {
                return switch (direction) {
                    .right => s ++ " " ** (n - s.len),
                    .left => " " ** (n - s.len) ++ s,
                };
            }

            pub fn printError(writer: std.io.AnyWriter, comptime message: []const u8, options: CallOptions) !void {
                // const tty_config = std.io.tty.detectConfig(writer);
                // try tty_config.setColor(writer, .red);
                // try tty_config.setColor(writer, .bold);
                try writer.writeAll("Error:\n");
                // try tty_config.setColor(writer, .reset);
                try writer.writeAll(message ++ "\n");
                try writer.writeAll("\n");
                try printHelp(writer, options);
            }
            pub fn printHelp(writer: std.io.AnyWriter, options: CallOptions) !void {
                _ = options; // autofix
                const gutter = " " ** 2;

                const args_type_width, const args_col_width, const alias_column_width = comptime blk: {
                    var max_args: usize = 0;
                    var max_type: usize = 0;
                    var max_alias: usize = 0;
                    for (formatted_options ++ formatted_arguments) |option| {
                        if (option.hide_from_help) continue;

                        max_args = @max(max_args, option.arg_name.len);
                        max_type = @max(max_type, option.help_type.len);
                        if (option.alias) |alias| {
                            max_alias = @max(max_alias, alias.len);
                        }
                    }
                    break :blk .{ max_type, max_args, max_alias };
                };

                // Usage
                try writer.writeAll("Usage: ");
                if (metadata) |m| {
                    try writer.writeAll(m.name);
                }

                inline for (formatted_arguments) |option| {
                    if (option.is_required) {
                        try writer.writeAll(" <" ++ option.arg_name ++ ">");
                    } else {
                        try writer.writeAll(" [" ++ option.arg_name ++ "]");
                    }
                }
                if (formatted_options.len > 0) {
                    try writer.writeAll(" [options]");
                }
                try writer.writeAll("\n\n");
                if (metadata) |m| if (m.description) |desc| {
                    try writer.writeAll(desc ++ "\n");
                };

                // Arguments
                var printed_arguments_header = false;
                inline for (formatted_arguments) |option| {
                    if (option.hide_from_help) continue;
                    if (!printed_arguments_header) {
                        try writer.writeAll("\nArguments:\n");
                        printed_arguments_header = true;
                    }
                    const first_part = " " ++ pad(
                        .right,
                        option.arg_name,
                        (if (alias_column_width > 0) alias_column_width + 3 else 0) + args_col_width + 2,
                    ) ++ gutter;
                    try writer.writeAll(first_part);
                    try writer.writeAll(pad(.right, option.help_type, args_type_width) ++ gutter);

                    const description = desc: {
                        const default = if (option.default_value_help.len > 0) "(default: " ++ option.default_value_help ++ ")" else "";
                        if (default.len > 0 and option.description.len > 0) {
                            break :desc option.description ++ " " ++ default;
                        }

                        break :desc option.description ++ default;
                    };
                    for (description) |c| {
                        if (c == '\n') {
                            try writer.writeAll("\n" ++ gutter ++ " " ** (first_part.len + args_type_width));
                        } else {
                            try writer.writeByte(c);
                        }
                    }

                    try writer.writeAll("\n");
                }

                // Options
                var printed_options_header = false;

                inline for (formatted_options) |option| {
                    if (option.hide_from_help) continue;
                    if (!printed_options_header) {
                        try writer.writeAll("\nOptions:\n");
                        printed_options_header = true;
                    }

                    const alias_s = if (option.alias) |a| "-" ++ a ++ ", " else "";
                    // "-a, "
                    const alias_col = if (alias_column_width > 0) pad(.left, alias_s, alias_column_width + 3) else "";
                    // "--arg"
                    const args_col = pad(.right, "--" ++ option.arg_name, args_col_width + 2);

                    const type_col = pad(.right, option.help_type, args_type_width);
                    const first_part = " " ++ alias_col ++ args_col ++ gutter ++ type_col ++ gutter;

                    try writer.writeAll(first_part);
                    // const default = blk: {
                    //     if (option.default_value) |v| {
                    //         const res: T = undefined;
                    //         const O = @TypeOf(&@field(res, option.field_name));
                    //         const default_value = @as(O, @ptrCast(@alignCast(@constCast(v)))).*;
                    //         break :blk "(default: " ++ formatDefault(default_value) ++ ")";
                    //     }
                    //     break :blk "";
                    // };
                    const description = desc: {
                        const default = if (option.default_value_help.len > 0) "(default: " ++ option.default_value_help ++ ")" else "";
                        if (default.len > 0 and option.description.len > 0) {
                            break :desc option.description ++ " " ++ default;
                        }

                        break :desc option.description ++ default;
                    };
                    for (description) |c| {
                        if (c == '\n') {
                            try writer.writeAll("\n" ++ " " ** (first_part.len));
                        } else {
                            try writer.writeByte(c);
                        }
                    }
                    if (option.options.len > 0 and option.display_options) {
                        if (description.len > 0) try writer.writeAll("\n" ++ " " ** (first_part.len));
                        try writer.writeAll("Options: ");
                        inline for (option.options, 0..) |opt, i| {
                            try writer.writeAll("'" ++ opt ++ "'");
                            if (i < option.options.len - 1) {
                                try writer.writeAll(" | ");
                            }
                        }
                    }
                    try writer.writeAll("\n");
                }
            }

            fn build(allocator: std.mem.Allocator, argv: []IterArgv.OsArg, comptime options: CallOptions) !T {
                _ = options; // autofix
                var res: T = undefined;

                const map = comptime blk: {
                    var entries: [formatted_options.len * 2]struct { []const u8 } = undefined;

                    var i: usize = 0;
                    for (formatted_options) |option| {
                        if (option.is_argument) {
                            continue;
                        }
                        entries[i] = .{"--" ++ option.arg_name};

                        i += 1;
                        if (option.alias) |alias| {
                            entries[i] = .{"-" ++ alias};
                            i += 1;
                        }
                    }
                    const map = std.StaticStringMap(void).initComptime(entries[0..i]);
                    break :blk map;
                };

                var iter = IterArgv.init(argv);
                inline for (formatted_arguments) |argument| {
                    if (iter.peeked) |entry| {
                        if (entry.kind != .value) {
                            if (argument.is_required) {
                                @panic("Missing required argument: " ++ argument.arg_name);
                            }
                        } else {
                            _ = iter.next();
                            if (comptime !std.mem.eql(u8, argument.arg_name, "help") and !std.mem.eql(u8, argument.arg_name, "version")) @field(res, argument.field_name) = try parseValue(allocator, argument.type, entry.value);
                        }
                    }
                }
                var values = [_]?[]const u8{null} ** map.kvs.len;

                if (values.len > 0) while (iter.peeked) |entry| {
                    if (entry.kind == .value) {
                        return error.UnexpectedArgument;
                    }
                    if (map.getIndex(entry.key)) |index| {
                        values[index] = entry.value;
                    } else {
                        // TODO: panic if unexpected flag?
                    }

                    _ = iter.next();
                };

                inline for (formatted_options) |option| {
                    const value: ?[]const u8 = blk: {
                        const long_index = map.getIndex("--" ++ option.arg_name) orelse unreachable;
                        const long = values[long_index];
                        if (long) |v| break :blk v;
                        if (option.alias) |alias| {
                            const short_index = map.getIndex("-" ++ alias) orelse unreachable;
                            const short = values[short_index];
                            break :blk short;
                        }
                        if (option.default_value == null and option.type == bool) {
                            break :blk "";
                        }
                        break :blk null;
                    };

                    if (value) |v| {
                        if (comptime !std.mem.eql(u8, option.arg_name, "help") and !std.mem.eql(u8, option.arg_name, "version")) @field(res, option.field_name) = try parseValue(allocator, option.type, v);
                    } else {
                        const info = @typeInfo(option.type);
                        if (option.default_value) |default_value| {
                            const O = @TypeOf(&@field(res, option.field_name));
                            @field(res, option.field_name) = @as(O, @ptrCast(@alignCast(@constCast(default_value)))).*;
                        } else if (comptime std.meta.activeTag(info) == .optional) {
                            @field(res, option.field_name) = @as(option.type, null);
                        } else {
                            if (comptime !std.mem.eql(u8, option.arg_name, "help") and !std.mem.eql(u8, option.arg_name, "version")) @panic("No value provided for required option " ++ option.arg_name);
                        }
                    }
                }

                return res;
            }
            pub fn parseValue(allocator: std.mem.Allocator, comptime F: type, value: []const u8) !F {
                const U = Unwrap(F);
                switch (U) {
                    bool => {
                        if (std.mem.eql(u8, value, "")) return true;
                        if (std.ascii.eqlIgnoreCase(value, "true")) return true;
                        if (std.ascii.eqlIgnoreCase(value, "false")) return false;

                        return error.invalid_value;
                    },
                    []const u8 => {
                        return value;
                    },
                    else => {},
                }

                const info: std.builtin.Type = @typeInfo(U);

                switch (info) {
                    .float => return try std.fmt.parseFloat(F, value),
                    .int => return try std.fmt.parseInt(
                        F,
                        value[0 .. std.mem.indexOfScalar(u8, value, '.') orelse value.len],
                        10,
                    ),
                    .@"enum" => return std.meta.stringToEnum(F, value) orelse return error.invalid_value,
                    .array => |arr| {
                        var iter = std.mem.splitScalar(u8, value, ',');
                        const out: [arr.len]F = undefined;
                        for (out) |*item| {
                            if (iter.next()) |v| {
                                item.* = try parseValue(arr.child, v);
                            } else {
                                return error.invalid_value;
                            }
                        }
                        return out;
                    },

                    .pointer => |ptr| {
                        switch (ptr.size) {
                            .Slice => {
                                var iter = std.mem.splitScalar(u8, value, ',');
                                var out = std.ArrayList(ptr.child).init(allocator);
                                while (iter.next()) |item| {
                                    const v = try parseValue(allocator, ptr.child, item);
                                    try out.append(v);
                                }
                                return out.toOwnedSlice();
                            },

                            else => {},
                        }
                    },
                    else => {},
                }
                return error.unimplemented;
            }

            pub const CallOptions = struct {
                stdout_writer: std.io.AnyWriter = std.io.getStdOut().writer().any(),
                stderr_writer: std.io.AnyWriter = std.io.getStdErr().writer().any(),
                no_color: ?bool = null,
            };
            pub fn call(allocator: std.mem.Allocator, argv: []IterArgv.OsArg, comptime options: CallOptions) !void {
                if (argv.len == 0) {
                    @panic("No command provided");
                }

                var arg_iter = IterArgv.init(argv[1..]);
                if (argv[1..].len == 0) {
                    try printHelp(options.stderr_writer, options);
                    return;
                }

                if (metadata) |m| if (arg_iter.peeked) |command| {
                    if (command.kind == .value) {
                        inline for (m.commands) |cmd| {
                            if (std.mem.eql(u8, command.value, cmd.name)) {
                                return cmd.call(allocator, argv[1..], options);
                            }
                        }
                    }
                };
                while (arg_iter.next()) |entry| {
                    if (entry.kind == .value) continue;

                    if (std.mem.eql(u8, "--help", entry.key) or std.mem.eql(u8, "-h", entry.key)) {
                        try printHelp(options.stderr_writer, options);
                        return;
                    }
                    if (metadata) |m| if (m.version) |v| if (v.len > 1) {
                        if (std.mem.eql(u8, "--version", entry.key) or std.mem.eql(u8, "-v", entry.key)) {
                            try options.stderr_writer.print("{s}\n", .{v});
                            return;
                        }
                    };
                }

                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const res = try build(arena.allocator(), argv[1..], options);

                T.run(res) catch |err| {
                    switch (err) {
                        error.UnexpectedArgument => try printError(options.stderr_writer, "Unexpected argument", options),
                        else => try printError(options.stderr_writer, @errorName(err), options),
                    }
                };
            }
        };
    }
}

test "program" {
    const A = program(struct {
        abc: ?[]const u8,

        pub const metadata: Meta.Program(@This()) = .{
            .name = "a",
            .description = "abc",
            .options = .{
                // .abc = Meta.Option{
                //     .display_name = "abc",
                // },
            },
        };

        pub fn run(self: @This()) !void {
            std.debug.print("A\n", .{});
            _ = self; // autofix
        }
    });
    const P = program(struct {
        arg: []const u8 = "def",
        arg_b: []const u8 = "def",
        foo_bool: bool = false,
        foo_maybe_bool: ?bool = null,
        foo_str: []const u8 = "def",
        foo_enum: Foo = .BAR,
        foo_n_list: []const usize = &.{ 1, 2, 3 },
        foo_f_list: []const f32 = &.{ 1.3, 2.0, 3.0 },
        foo_url: []const u8 = "https://example.com",

        const Foo = enum {
            BAR,
            BAZ,
        };

        pub const metadata: Meta.Program(@This()) = .{
            .name = "cli",
            .version = "0.0.1",
            .description = "abc",
            .options = .{
                .arg = Meta.Option{
                    .description = "Lorem ipsum dolor sit amet\nDolor sit amet",
                    .is_argument = true,
                    .display_name = "url",
                },
                .arg_b = Meta.Option{
                    .description = "Lorem ipsum dolor sit amet",
                    .is_argument = true,
                },
                .foo_bool = Meta.Option{
                    .description = "Lorem ipsum dolor sit amet",
                },
                .foo_str = Meta.Option{
                    .display_name = "str",
                    .short_alias = 'f',
                    .description = "Foo bar",
                },
            },
            .commands = &.{A},
        };

        pub fn run(self: @This()) !void {
            std.debug.print("P\n", .{});
            _ = self; // autofix
        }
    });

    var argv = [_]IterArgv.OsArg{ "a/b/c", "--foo-enum", "BAZ", "--foo-bar", "--bar", "-a", "--foo-n-list=1.3,2,3,4" };

    try P.call(std.testing.allocator, argv[0..], .{});
}
