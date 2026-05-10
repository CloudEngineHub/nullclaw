const std = @import("std");
const compat = @import("compat");

pub const buffer = @import("buffer.zig");

pub const proto = @import("proto.zig");
pub const OpCode = proto.OpCode;
pub const Message = proto.Message;
pub const MessageType = Message.Type;
pub const MessageTextType = Message.TextType;

pub const Client = @import("client/client.zig").Client;

pub const server = @import("server/server.zig");
pub const testing = @import("testing.zig");

pub const Conn = server.Conn;
pub const Config = server.Config;
pub const Server = server.Server;
pub const blockingMode = server.blockingMode;
pub const Handshake = @import("server/handshake.zig").Handshake;

pub const Compression = struct {
    write_threshold: ?usize = null,
    retain_write_buffer: bool = true,
    // don't know how to support these in the current compatibility branch. So, for now
    // we'll always require these to be true
    // client_no_context_takeover: bool = false,
    // server_no_context_takeover: bool = false,
};

pub fn bufferProvider(allocator: std.mem.Allocator, config: buffer.Config) !buffer.Provider {
    return buffer.Provider.init(allocator, config);
}

pub fn frameText(comptime msg: []const u8) [proto.calculateFrameLen(msg)]u8 {
    return proto.frame(.text, msg);
}

pub fn frameBin(comptime msg: []const u8) [proto.calculateFrameLen(msg)]u8 {
    return proto.frame(.binary, msg);
}

comptime {
    std.testing.refAllDecls(@This());
}

const t = @import("t.zig");
test "frameText" {
    {
        const framed = frameText("");
        try t.expectString(&[_]u8{ 129, 0 }, &framed);
    }

    {
        // short
        const framed = frameText("hello");
        try t.expectString(&[_]u8{ 129, 5, 'h', 'e', 'l', 'l', 'o' }, &framed);
    }

    {
        const msg = "A" ** 130;
        const framed = frameText(msg);

        try t.expectEqual(134, framed.len);

        // text type
        try t.expectEqual(129, framed[0]);

        // 2 byte length marker
        try t.expectEqual(126, framed[1]);

        try t.expectEqual(0, framed[2]);
        try t.expectEqual(130, framed[3]);

        // payload
        for (framed[4..]) |f| {
            try t.expectEqual('A', f);
        }
    }
}

test "frameBin" {
    {
        // short
        const framed = frameBin("hello");
        try t.expectString(&[_]u8{ 130, 5, 'h', 'e', 'l', 'l', 'o' }, &framed);
    }

    {
        const msg = "A" ** 130;
        const framed = frameBin(msg);

        try t.expectEqual(134, framed.len);

        // text type
        try t.expectEqual(130, framed[0]);

        // 2 byte length marker
        try t.expectEqual(126, framed[1]);

        try t.expectEqual(0, framed[2]);
        try t.expectEqual(130, framed[3]);

        // payload
        for (framed[4..]) |f| {
            try t.expectEqual('A', f);
        }
    }
}

test "compat net.Server.accept returns peer address" {
    var address = try compat.net.Address.parseIp("127.0.0.1", 0);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    const client = try compat.net.tcpConnectToAddress(listener.listen_address);
    defer client.close();

    var accepted = try listener.accept();
    defer accepted.stream.close();

    var client_address: compat.net.Address = undefined;
    var client_address_len: std.posix.socklen_t = @sizeOf(compat.net.Address);
    switch (std.posix.errno(std.posix.system.getsockname(client.handle, &client_address.any, &client_address_len))) {
        .SUCCESS => {},
        else => |err| return std.posix.unexpectedErrno(err),
    }

    try t.expectEqual(client_address.any.family, accepted.address.any.family);
    try t.expectEqual(client_address.in.sa.addr, accepted.address.in.sa.addr);
    try t.expectEqual(client_address.in.getPort(), accepted.address.in.getPort());
    try std.testing.expect(client_address.in.getPort() != listener.listen_address.in.getPort());
}

test "compat net.tcpConnectToAddresses falls back to a working address" {
    var address = try compat.net.Address.parseIp("127.0.0.1", 0);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    const addresses = [_]compat.net.Address{
        try compat.net.Address.parseIp("::1", listener.listen_address.in.getPort()),
        listener.listen_address,
    };

    const client = try compat.net.tcpConnectToAddresses(&addresses);
    defer client.close();

    var accepted = try listener.accept();
    defer accepted.stream.close();
}
