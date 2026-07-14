const std = @import("std");
const net = std.Io.net;
pub const Msg = @import("msg.zig");

const c = @cImport({
    @cInclude("ifaddrs.h");
    @cInclude("arpa/inet.h");
    @cInclude("netinet/in.h");
    @cInclude("sys/socket.h");
});

pub var ownIp: u32 = 0;
pub var advertising: bool = true;

pub const listenBroadcast = @import("udp.zig").listenBroadcast;
pub const advertize = @import("udp.zig").advertize;

pub const listenTcp = @import("tcp.zig").listenTcp;


pub fn IpAddressToString(addr: *const net.IpAddress, buffer: []u8) !void {
    @memset(buffer, 0);
    _ = try std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{
        addr.ip4.bytes[0],
        addr.ip4.bytes[1],
        addr.ip4.bytes[2],
        addr.ip4.bytes[3],
    });
}

pub fn getIp(gpa: std.mem.Allocator) !std.ArrayList(u32) {

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
