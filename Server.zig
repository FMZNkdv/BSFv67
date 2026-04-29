const std = @import("std");
const Message = @import("Gate/Message.zig");
const Logger = @import("Core/Logger.zig");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .logFn = struct {
        fn f(
            comptime _: std.log.Level,
            comptime _: @TypeOf(.enum_literal),
            comptime _: []const u8,
            _: anytype,
        ) void {}
    }.f,
};

const ClientCtx = struct {
    conn: std.net.Server.Connection,
    allocator: std.mem.Allocator,
};

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }

    const addr = try std.net.Address.parseIp4("0.0.0.0", 9339);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    Logger.banner();
    Logger.serverInfo("Listening on {d}", .{9339});

    while (true) {
        const conn = server.accept() catch |err| {
            Logger.serverInfo("accept() failed  {any}", .{err});
            continue;
        };

        const ctx = std.heap.page_allocator.create(ClientCtx) catch {
            conn.stream.close();
            continue;
        };
        ctx.* = .{ .conn = conn, .allocator = std.heap.page_allocator };

        const t = std.Thread.spawn(.{}, clientLoop, .{ctx}) catch |err| {
            Logger.serverInfo("Thread spawn failed  {any}", .{err});
            conn.stream.close();
            std.heap.page_allocator.destroy(ctx);
            continue;
        };
        t.detach();
    }
}

fn readExact(stream: std.net.Stream, dest: []u8) !void {
    var total: usize = 0;
    while (total < dest.len) {
        const n: usize = if (builtin.os.tag == .windows) blk: {
            const windows = std.os.windows;
            var bufs = [1]windows.ws2_32.WSABUF{.{
                .len = @intCast(dest.len - total),
                .buf = dest[total..].ptr,
            }};
            var received: u32 = 0;
            var flags: u32 = 0;
            const rc = windows.ws2_32.WSARecv(stream.handle, &bufs, 1, &received, &flags, null, null);
            if (rc == windows.ws2_32.SOCKET_ERROR) return error.ConnectionResetByPeer;
            break :blk received;
        } else try std.posix.recv(stream.handle, dest[total..], 0);

        if (n == 0) return error.EndOfStream;
        total += n;
    }
}

fn clientLoop(ctx: *ClientCtx) void {
    defer {
        ctx.conn.stream.close();
        ctx.allocator.destroy(ctx);
    }

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    Logger.setAddr(ctx.conn.address);
    Logger.connect();

    const stream = ctx.conn.stream;
    var header: [7]u8 = undefined;

    while (true) {
        readExact(stream, &header) catch |err| {
            if (err == error.EndOfStream or err == error.ConnectionResetByPeer) {
                Logger.disconnect();
            } else {
                Logger.clientErr("Read failed  {any}", .{err});
            }
            break;
        };

        const msgId: u16 = std.mem.readInt(u16, header[0..2], .big);
        const msgLen: usize =
            (@as(usize, header[2]) << 16) |
            (@as(usize, header[3]) << 8) |
            @as(usize, header[4]);
        const msgVer: u16 = std.mem.readInt(u16, header[5..7], .big);
        _ = msgVer;

        const payload = alloc.alloc(u8, msgLen) catch {
            Logger.clientErr("Out of memory for {d} bytes", .{msgLen});
            break;
        };

        if (msgLen > 0) {
            readExact(stream, payload) catch |err| {
                if (err == error.EndOfStream or err == error.ConnectionResetByPeer) {
                    Logger.disconnect();
                } else {
                    Logger.clientErr("Payload read failed  {any}", .{err});
                }
                break;
            };
        }

        Logger.packetIn(msgId, Logger.packetName(msgId), msgLen);

        Message.dispatch(alloc, msgId, payload, stream) catch |err| {
            Logger.clientErr("Dispatch failed on {d}  {any}", .{ msgId, err });
        };
    }
}
