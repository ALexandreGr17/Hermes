const std = @import("std");
const net = std.Io.net;

fn listenBroadcast(io: std.Io) !void {
    const address = try net.IpAddress.parseIp4("0.0.0.0", 5005);

    const socket = try address.bind(io, .{.protocol = .udp, .mode = .dgram});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    while (true) {
        var buffer: [8]u8 = undefined;
        var conn = try socket.receive(io, &buffer);

        const size: u64 = std.mem.readInt(u64, &buffer, .little);

        const buffer2 = try allocator.alloc(u8, size);

        conn = try socket.receive(io, buffer2);

        std.debug.print("received: {s}\n", .{buffer2});
        std.debug.print("data: {s}\n", .{conn.data});
    }
}


fn sendBrodcast(io: std.Io, dest: *const net.IpAddress, socket: net.Socket, data: []const u8) !void {
    const size: u64 = @intCast(data.len);
    var size_msg: [8]u8 = undefined;
    std.mem.writeInt(u64, &size_msg, size, .little);

    try socket.send(io, dest, &size_msg);
    try socket.send(io, dest, data);
}

pub fn main(init: std.process.Init) void {
     _ = init.io.async(listenBroadcast, .{ init.io });

    const address = net.IpAddress.parseIp4("0.0.0.0", 4444) catch |err| {
        std.log.err("Error when parsing address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    const braodcast = net.IpAddress.parseIp4("255.255.255.255", 5005) catch |err| {
        std.log.err("Error when parsing address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    const socket = address.bind(init.io, .{.protocol = .udp, .mode = .dgram, .allow_broadcast = true}) catch |err| {
        std.log.err("Error when binding address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    sendBrodcast(init.io, &braodcast, socket, "Hello world!") catch |err| {
        std.log.err("Error when sending data: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
}
