const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});

pub const Logger = struct {
    const LogLevel = enum {
        Error,
        Warning,
        Info,
        Debug
    };

    level: LogLevel = .Info,
    file: *std.Io.File,
    secondary: ?*std.Io.File,
    io: std.Io,

    pub fn log(self: *const Logger, tag: []const u8, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) > @intFromEnum(self.level)) return;
        var buffer: [10]u8 = undefined;
        var writer = self.file.writer(self.io, &buffer);

        const t = c.time(null);
        var tm: c.struct_tm = undefined;
        _ = c.localtime_r(&t, &tm);
    

        const length = self.file.length(self.io) catch return;

        writer.seekTo(length) catch return;


        writer.interface.print(
            "{}-{}-{} {}:{}:{} ",
            .{
                tm.tm_year + 1900,
                tm.tm_mon + 1,
                tm.tm_mday,
                tm.tm_hour,
                tm.tm_min,
                tm.tm_sec,
            },
        ) catch return;
        writer.interface.print("[{s}] <{s}>: ", .{@tagName(level), tag}) catch return;
        writer.interface.print(fmt, args) catch return;
        
        writer.interface.print("\n", .{}) catch return;
        writer.end() catch return;

        if (self.secondary) |file| {
            writer = file.writer(self.io, &buffer);

            writer.interface.print(
                "{}-{}-{} {}:{}:{} ",
                .{
                    tm.tm_year + 1900,
                    tm.tm_mon + 1,
                    tm.tm_mday,
                    tm.tm_hour,
                    tm.tm_min,
                    tm.tm_sec,
                },
                ) catch return;
            writer.interface.print("[{s}] <{s}>: ", .{@tagName(level), tag}) catch return;
            writer.interface.print(fmt, args) catch return;

            writer.interface.print("\n", .{}) catch return;
            writer.end() catch return;
        }
    }
};
