const std = @import("std");
const libfuse = @import("libfusec");
const Logger = @import("log.zig").Logger;
const supervisor = @import("supervisor.zig");

const networking = @import("networking/lib.zig");

const net = std.Io.net;

pub fn main(init: std.process.Init) void {

    var log_file = std.Io.Dir.openFileAbsolute(init.io, "/tmp/log", .{ .mode = .write_only }) catch |err| {
        std.log.err("Unable to open file /tmp/log: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    const logger: Logger = .{
        .file = &log_file,
        .io = init.io,
        .secondary = @constCast(&std.Io.File.stdout()),
        .level = .Debug
    };

    logger.log("Hermes", .Info, "Hermes is starting...", .{});

    const ip_list = networking.getIp(init.arena.allocator()) catch |err| {
        logger.log("Ip", .Error, "Error while getting Ip: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    var backlog: [10]networking.Msg.NewConnMsg = undefined;
    var error_backlog: [2]supervisor.CriticalError = undefined;
    var queue: std.Io.Queue(networking.Msg.NewConnMsg) = .init(&backlog);
    var error_queue: std.Io.Queue(supervisor.CriticalError) = .init(&error_backlog);

    var group: std.Io.Group = .init;

    _ = init.io.async(supervisor.supervisor, .{init.io, &logger, &error_queue, &group});

    group.async(init.io, networking.listenBroadcast, .{
        0,
        init.io,
        ip_list,
        &queue,
        &error_queue,
        &logger
    });

    group.async(init.io, networking.listenTcp, .{
        1,
        init.io,
        &error_queue,
        &logger
    });

    group.async(init.io, networking.advertize, .{
        2,
        init.io,
        &error_queue,
        &logger
    });

     while(true) {
        const newConn = queue.getOne(init.io) catch |err| {
            logger.log("Queue", .Error, "Error while reading from queue: {s}", .{@errorName(err)});
            std.process.exit(1);
        };

        if (networking.ownIp == 0) continue;

        networking.advertising = false;

        if (newConn.ip > networking.ownIp) {
            logger.log("TCP", .Info, "Connecting to: {d}.{d}.{d}.{d}:{d}", .{
                (newConn.ip & (0xFF)),
                (newConn.ip & (0xFF << 8)) >> 8,
                (newConn.ip & (0xFF << 16)) >> 16,
                (newConn.ip & (0xFF << 24)) >> 24,
                newConn.port
            });

            const new_addr: net.IpAddress = .{ 
                .ip4 = .{ 
                    .bytes = .{  
                        @intCast(newConn.ip & (0xFF)),
                        @intCast((newConn.ip & (0xFF << 8)) >> 8),
                        @intCast((newConn.ip & (0xFF << 16)) >> 16),
                        @intCast((newConn.ip & (0xFF << 24)) >> 24),
                    },

                    .port = newConn.port
                }
            };

            _ = new_addr.connect(init.io, .{ .mode = .stream, .protocol = .tcp }) catch |err| {
                logger.log("TCP", .Error, "Error wihle connecting to server: {s}", .{@errorName(err)});
                std.process.exit(1);
            };

        }
     }

}
