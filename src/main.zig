const std = @import("std");
const libfuse = @import("libfusec");
const Logger = @import("log.zig").Logger;
const supervisor = @import("supervisor.zig");

const networking = @import("networking/lib.zig");

const net = std.Io.net;

pub fn main(init: std.process.Init) void {

    var threaded = std.Io.Threaded.init(init.gpa, .{ .async_limit = std.Io.Limit.limited(10) });
    defer threaded.deinit();
    const io = threaded.io();

    var log_file = std.Io.Dir.openFileAbsolute(io, "/tmp/log", .{ .mode = .write_only }) catch |err| blk: {
        break :blk std.Io.Dir.createFileAbsolute(io, "/tmp/log", .{ .truncate = false }) catch |err2| {
            std.log.err("Unable to open file /tmp/log: {s} or create it: {s}", .{@errorName(err), @errorName(err2)});
            std.process.exit(1);
        };
    };

    var logger: Logger = .{
        .file = &log_file,
        .io = io,
        .secondary = @constCast(&std.Io.File.stdout()),
        .level = .Debug,
        .mutex = std.Io.Mutex.init,
    };

    logger.log("Hermes", .Info, "Hermes is starting...", .{}) catch return;

    const ip_list = networking.getIp(init.arena.allocator()) catch |err| {
        logger.log("Ip", .Error, "Error while getting Ip: {s}", .{@errorName(err)}) catch return;
        std.process.exit(1);
    };

    var backlog: [10]networking.Msg.NewConnMsg = undefined;
    var error_backlog: [2]supervisor.CriticalError = undefined;
    var queue: std.Io.Queue(networking.Msg.NewConnMsg) = .init(&backlog);
    var error_queue: std.Io.Queue(supervisor.CriticalError) = .init(&error_backlog);

    var group: std.Io.Group = .init;

    _ = io.async(supervisor.supervisor, .{io, &logger, &error_queue, &group});

    group.async(io, networking.listenBroadcast, .{
        0,
        io,
        ip_list,
        &queue,
        &error_queue,
        &logger
    });

    group.async(io, networking.listenTcp, .{
        1,
        io,
        &error_queue,
        &logger
    });


    group.async(io, networking.advertize, .{
        2,
        io,
        &error_queue,
        &logger
    });

    group.async(io, networking.handshakeTcp, .{
        3,
        io,
        &queue,
        &logger
    });

    group.await(io) catch return;
}
