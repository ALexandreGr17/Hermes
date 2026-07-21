const std = @import("std");
const net = std.Io.net;
const Logger = @import("../log.zig").Logger;
const NewConnMsg = @import("msg.zig").NewConnMsg;
const AdvertismentMsg = @import("msg.zig").AdvertismentMsg;
const SIGNATURE = @import("msg.zig").SIGNATURE;
const CriticalError = @import("../supervisor.zig").CriticalError;
const networking = @import("lib.zig");

pub fn listenBroadcast(id: usize, io: std.Io, ip_list: std.ArrayList(u32), queue: *std.Io.Queue(NewConnMsg), error_queue: *std.Io.Queue(CriticalError),logger: *const Logger) std.Io.Cancelable!void {
    const address = net.IpAddress.parseIp4("0.0.0.0", 5005) catch |err| {
        logger.log("UDP listen", .Error, "Error while creating address struct {s}", .{@errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch return std.Io.Cancelable.Canceled;
        return std.Io.Cancelable.Canceled;
    };

    const socket = address.bind(io, .{.protocol = .udp, .mode = .dgram}) catch |err| {
        logger.log("UDP listen", .Error, "Error while binding to port {}: {s}", .{5005, @errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch return std.Io.Cancelable.Canceled;
        return std.Io.Cancelable.Canceled;
    };

    logger.log("UDP listen", .Info, "Listening on port: {}", .{5005});

     listenLoop: while (true) {
        var buffer: [@sizeOf(AdvertismentMsg)]u8 align(@alignOf(AdvertismentMsg)) = undefined;

        const conn = socket.receive(io, &buffer) catch |err| switch (err) {
            std.Io.Cancelable.Canceled => {
                return std.Io.Cancelable.Canceled;
            },

            else => {
                logger.log("UDP listen", .Error, "Error while receiving from the socket: {s}", .{@errorName(err)});
                continue :listenLoop;
            },
        };
        const ip: u32 = std.mem.readInt(u32, &conn.from.ip4.bytes, .native);

        const msg: *AdvertismentMsg = @ptrCast(@alignCast(&buffer));

        if (!std.mem.eql(u8, &SIGNATURE, &msg.signature)) continue :listenLoop;

        for (ip_list.items) |test_ip| {
            if (test_ip == ip) {
                networking.ownIp = ip;
                continue :listenLoop;
            }
        }


        logger.log("UPD listen", .Info, "Recived advertisment from {d}.{d}.{d}.{d}:{d}", .{
            conn.from.ip4.bytes[0], 
            conn.from.ip4.bytes[1], 
            conn.from.ip4.bytes[2], 
            conn.from.ip4.bytes[3],
            msg.port
        });

        queue.putOne(io, .{ .ip = ip, .port = msg.port }) catch return std.Io.Cancelable.Canceled;
    }
}


pub fn advertize(id: usize, io: std.Io, error_queue: *std.Io.Queue(CriticalError),logger: *const Logger) !void {
    const address = net.IpAddress.parseIp4("0.0.0.0", 4444) catch |err| {
        logger.log("UDP Advertisment", .Error, "Error when parsing address 0.0.0.0:4444: {s}", .{@errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch return std.Io.Cancelable.Canceled;
        return std.Io.Cancelable.Canceled;
    };
    const braodcast = net.IpAddress.parseIp4("255.255.255.255", 5005) catch |err| {
        logger.log("UDP Advertisment", .Error, "Error when parsing address 255.255.255.255:5005: {s}", .{@errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch return std.Io.Cancelable.Canceled;
        return std.Io.Cancelable.Canceled;
    };

    const socket = address.bind(io, .{.protocol = .udp, .mode = .dgram, .allow_broadcast = true}) catch |err| {
        logger.log("UDP Advertisment", .Error, "Error when binding address 0.0.0.0:4444: {s}", .{@errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch return std.Io.Cancelable.Canceled;
        return std.Io.Cancelable.Canceled;
    };

    var msg = AdvertismentMsg{
        .port = 4444,
    };

    const data: *[@sizeOf(AdvertismentMsg)]u8 = @ptrCast(@alignCast(&msg));
    logger.log("UDP Advertisment", .Info, "Starting advertisment", .{});
    while (networking.advertising) {
        socket.send(io, &braodcast, data) catch |err| switch (err) {
            std.Io.Cancelable.Canceled => {
                return std.Io.Cancelable.Canceled;
            },

            else => {
                logger.log("UDP Advertisment", .Warning, "Error when sending on socket: {s}", .{@errorName(err)});
            }
        };
        try io.sleep(std.Io.Duration.fromMilliseconds(500), .awake);
    }
    socket.close(io);
}
