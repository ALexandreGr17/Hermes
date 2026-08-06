const std = @import("std");
const Logger = @import("log.zig").Logger;

pub const CriticalError = struct {
    worker: usize,
    err: anyerror
};

pub fn supervisor(io: std.Io, logger: *Logger, error_queue: *std.Io.Queue(CriticalError), group: *std.Io.Group) !void {
    const first_error = try error_queue.getOne(io);
    logger.log("Supervisor", .Error, "Stoping porcess for error {s} by {}", .{@errorName(first_error.err), first_error.worker}) catch {
        return std.Io.Cancelable.Canceled;
    };

    group.cancel(io);
    return first_error.err;
}
