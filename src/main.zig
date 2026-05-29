const std = @import("std");
const net = std.Io.net;

const SIGNATURE: [4]u8 = [4]u8{'H', 'E', 'R', 'M'};

const AdvertismentMsg = extern struct {
    signature: [4]u8 = [_]u8{'H', 'E', 'R', 'M'},
    port: u16,
};

const NewConnMsg = struct {
    port: u16,
    ip: u32
};

var advertising: bool = true;
var ownIp: u32 = 0;

fn advertize(io: std.Io) void {
    const address = net.IpAddress.parseIp4("0.0.0.0", 4444) catch |err| {
        std.log.err("Error when parsing address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    const braodcast = net.IpAddress.parseIp4("255.255.255.255", 5005) catch |err| {
        std.log.err("Error when parsing address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    const socket = address.bind(io, .{.protocol = .udp, .mode = .dgram, .allow_broadcast = true}) catch |err| {
        std.log.err("Error when binding address: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    var msg = AdvertismentMsg{
        .port = 4444,
    };

    const data: *[@sizeOf(AdvertismentMsg)]u8 = @ptrCast(@alignCast(&msg));

    msg.port = 4445;

    while (advertising) {
        socket.send(io, &braodcast, data) catch |err| {
            std.log.err("Error while sending: {s}", .{@errorName(err)});
            std.process.exit(1);
        };
        io.sleep(std.Io.Duration.fromMilliseconds(500), .awake) catch {
            break;
        };
    }
    socket.close(io);
}

fn listenBroadcast(io: std.Io, ip_list: std.ArrayList(u32), queue: *std.Io.Queue(NewConnMsg)) !void {
    const address = try net.IpAddress.parseIp4("0.0.0.0", 5005);

    const socket = try address.bind(io, .{.protocol = .udp, .mode = .dgram});

     listenLoop: while (true) {
        var buffer: [@sizeOf(AdvertismentMsg)]u8 align(@alignOf(AdvertismentMsg)) = undefined;

        const conn = try socket.receive(io, &buffer);
        const ip: u32 = std.mem.readInt(u32, &conn.from.ip4.bytes, .native);

        const msg: *AdvertismentMsg = @ptrCast(@alignCast(&buffer));

        if (!std.mem.eql(u8, &SIGNATURE, &msg.signature)) continue :listenLoop;

        for (ip_list.items) |test_ip| {
            if (test_ip == ip) {
                ownIp = ip;
                continue :listenLoop;
            }
        }



        std.log.info("recived from: {d}.{d}.{d}.{d} ", .{conn.from.ip4.bytes[0], conn.from.ip4.bytes[1], conn.from.ip4.bytes[2], conn.from.ip4.bytes[3]});
        std.log.info("port: {d}\n", .{msg.port});

        try queue.putOne(io, .{ .ip = ip, .port = msg.port });
    }
}

fn IpAddressToString(addr: *const net.IpAddress, buffer: []u8) ![]u8 {
    _ = try std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{
        addr.ip4.bytes[0],
        addr.ip4.bytes[1],
        addr.ip4.bytes[2],
        addr.ip4.bytes[3],
    });
    return buffer;
}

pub fn listenTcp(io: std.Io) !void {
    const addr = try net.IpAddress.parseIp4("127.0.0.1", 4444);

    var socket_server = try addr.listen(io, .{ .mode = .stream, .protocol = .tcp,});

    while (true) {
        const client_socket = try socket_server.accept(io);
        var ipstr: [15]u8 = undefined;
        std.log.info("New connection from: {s}:{d}\n", .{
            try IpAddressToString(&client_socket.socket.address, &ipstr),
            client_socket.socket.address.getPort(),
        });
    }

}

const c = @cImport({
    @cInclude("ifaddrs.h");
    @cInclude("arpa/inet.h");
    @cInclude("netinet/in.h");
    @cInclude("sys/socket.h");
});

fn getIp(gpa: std.mem.Allocator) !std.ArrayList(u32) {

    var array = try std.ArrayList(u32).initCapacity(gpa, 10);
    errdefer array.deinit(gpa);
    var ifaddr: ?*c.struct_ifaddrs = null;

    if (c.getifaddrs(&ifaddr) != 0) {
        return error.GetIfAddrFailed;
    }

    defer c.freeifaddrs(ifaddr);

    var current = ifaddr;

    while (current != null) {
        const ifa =  current.?;

        if (ifa.ifa_addr != null and ifa.ifa_addr.*.sa_family == c.AF_INET) {
            const addr: *c.struct_sockaddr_in = @ptrCast(@alignCast(ifa.ifa_addr));
            const ip = addr.sin_addr.s_addr;
            try array.appendBounded(ip);

        }

        current = ifa.ifa_next;
    }


    return array;

}

pub fn main(init: std.process.Init) void {

    const ip_list = getIp(init.arena.allocator()) catch |err| {
        std.log.err("Error when getting Ip: {s}", .{@errorName(err)});
        std.process.exit(1);
    };

    var backlog: [10]NewConnMsg = undefined;
    var queue: std.Io.Queue(NewConnMsg) = .init(&backlog);

     _ = init.io.async(listenBroadcast, .{ init.io, ip_list, &queue });
     _ = init.io.async(listenTcp, .{ init.io });
     _ = init.io.async(advertize, .{ init.io});

     while(true) {
        const newConn = queue.getOne(init.io) catch |err| {
            std.log.err("Error while reading from queue: {s}", .{@errorName(err)});
            std.process.exit(1);
        };

        if (ownIp == 0) continue;
        
        advertising = false;

        if (newConn.ip > ownIp) {
            std.log.info("Connecting to: {d}.{d}.{d}.{d}:{d}", .{
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
                std.log.err("Error wihle connecting to server: {s}", .{@errorName(err)});
                std.process.exit(1);
            };

        }
     }

}
