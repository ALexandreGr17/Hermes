const std = @import("std");
const net = std.Io.net;
const networking = @import("lib.zig");
const IpAddressToString = networking.IpAddressToString;
const NewConnMsg = networking.Msg.NewConnMsg;
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

pub fn handshakeTcp(io: std.Io, conn_queue: *std.Io.Queue(NewConnMsg), logger: *const Logger) !void {
     handshakeLoop: while(true) {
        const newConn = conn_queue.getOne(io) catch {
            return std.Io.Cancelable.Canceled;
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

            _ = new_addr.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch |err| switch (err) {
                std.Io.Cancelable.Canceled => {
                    return std.Io.Cancelable.Canceled;
                },

                else => {
                    var buffer: [15]u8 = undefined;
                    IpAddressToString(&new_addr, &buffer) catch {};
                    logger.log("TCP handshake", .Error , "Error while connecting to address {s}: {s}", .{buffer, @errorName(err)});
                    continue :handshakeLoop;
                },
            };

        }
     }
}
