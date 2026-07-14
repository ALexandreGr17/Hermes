const std = @import("std");
const net = std.Io.net;
const IpAddressToString = @import("lib.zig").IpAddressToString;
const CriticalError = @import("../supervisor.zig").CriticalError;
const Logger = @import("../log.zig").Logger;

pub fn listenTcp(id: usize, io: std.Io, error_queue: *std.Io.Queue(CriticalError), logger: *const Logger) std.Io.Cancelable!void {
    const addr = net.IpAddress.parseIp4("192.168.1.52", 4445) catch |err| {
        logger.log("TCP listen", .Error, "Error while parsing address 192.168.1.52:4445: {s}", .{@errorName(err)});
        error_queue.putOne(io, .{ .err = err, .worker = id }) catch {
            return std.Io.Cancelable.Canceled;
        };
        return std.Io.Cancelable.Canceled;
    };

    var socket_server = addr.listen(io, .{ .mode = .stream, .protocol = .tcp,}) catch |err| switch (err) {
        std.Io.Cancelable.Canceled => {
            return std.Io.Cancelable.Canceled;
        },

        else => {
            logger.log("TCP listen", .Error, "Error while listening to address 192.168.1.52:4445: {s}", .{@errorName(err)});
            error_queue.putOne(io, .{ .err = err, .worker = id }) catch {
                return std.Io.Cancelable.Canceled;
            };
            return std.Io.Cancelable.Canceled;
        },
    };

    acceptLoop: while (true) {
        const client_socket = socket_server.accept(io) catch |err| switch (err) {
            std.Io.Cancelable.Canceled => {
                return std.Io.Cancelable.Canceled;
            },
            else => {
                logger.log("TCP listen", .Warning, "Failed to accept on socket: {s}", .{@errorName(err)});
                try io.sleep(std.Io.Duration.fromMilliseconds(500), .awake);
                continue :acceptLoop;
            },
        };
        var ipstr: [15]u8 = undefined;
        IpAddressToString(&client_socket.socket.address, &ipstr) catch |err| {
            logger.log("TCP listen", .Warning, "Error while formating an address {s}", .{@errorName(err)});
        };

        logger.log("TCP listen", .Info, "New Connection from: {s}:{d}\n", .{ipstr, client_socket.socket.address.getPort()});
    }

}
