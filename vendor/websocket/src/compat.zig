const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

var fallback_threaded: std.Io.Threaded = .init_single_threaded;
var process_environ: ?std.process.Environ = null;

pub fn io() std.Io {
    if (builtin.is_test) return std.testing.io;
    return fallback_threaded.io();
}

pub fn initProcessMinimal(init: std.process.Init.Minimal) void {
    process_environ = init.environ;
}

pub fn currentEnviron() std.process.Environ {
    return environ();
}

fn environ() std.process.Environ {
    if (process_environ) |env| return env;
    if (builtin.is_test) return std.testing.environ;
    return .empty;
}

pub const process = struct {
    pub const GetEnvVarOwnedError = error{
        EnvironmentVariableNotFound,
    } || Allocator.Error || error{ InvalidWtf8, Unexpected };

    pub fn getEnvVarOwned(allocator: Allocator, name: []const u8) GetEnvVarOwnedError![]u8 {
        return environ().getAlloc(allocator, name) catch |err| switch (err) {
            error.EnvironmentVariableMissing => error.EnvironmentVariableNotFound,
            else => |e| e,
        };
    }
};

pub const time = struct {
    fn nowNanoseconds() i128 {
        return switch (builtin.os.tag) {
            .windows => blk: {
                const epoch_ns = std.time.epoch.windows * std.time.ns_per_s;
                break :blk @as(i128, std.os.windows.ntdll.RtlGetSystemTimePrecise()) * 100 + epoch_ns;
            },
            .wasi => blk: {
                var ts: std.os.wasi.timestamp_t = undefined;
                if (std.os.wasi.clock_time_get(.REALTIME, 1, &ts) == .SUCCESS) {
                    break :blk @intCast(ts);
                }
                break :blk 0;
            },
            else => blk: {
                var ts: std.posix.timespec = undefined;
                switch (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts))) {
                    .SUCCESS => break :blk @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec,
                    else => break :blk 0,
                }
            },
        };
    }

    pub fn timestamp() i64 {
        return @intCast(@divTrunc(nowNanoseconds(), std.time.ns_per_s));
    }

    pub fn milliTimestamp() i64 {
        return @intCast(@divTrunc(nowNanoseconds(), std.time.ns_per_ms));
    }

    pub fn nanoTimestamp() i128 {
        return nowNanoseconds();
    }
};

pub const thread = struct {
    pub fn sleep(nanoseconds: u64) void {
        std.Io.sleep(io(), .fromNanoseconds(@intCast(nanoseconds)), .awake) catch {};
    }
};

pub const crypto = struct {
    pub const random = struct {
        pub fn bytes(buffer: []u8) void {
            std.Io.randomSecure(io(), buffer) catch std.Io.random(io(), buffer);
        }
    };
};

pub const net = struct {
    const IoNet = std.Io.net;
    const posix = std.posix;

    pub const has_unix_sockets = false;

    pub const Stream = struct {
        handle: Handle,

        pub const Handle = IoNet.Socket.Handle;
        pub const Reader = IoNet.Stream.Reader;
        pub const Writer = IoNet.Stream.Writer;
        pub const ReadError = if (builtin.os.tag == .windows) Reader.Error else posix.ReadError;
        pub const WriteError = IoNet.Stream.Writer.Error;

        fn toInner(self: Stream) IoNet.Stream {
            return .{
                .socket = .{
                    .handle = self.handle,
                    .address = .{ .ip4 = .loopback(0) },
                },
            };
        }

        pub fn close(self: Stream) void {
            self.toInner().close(io());
        }

        pub fn reader(self: Stream, buffer: []u8) Reader {
            return self.toInner().reader(io(), buffer);
        }

        pub fn writer(self: Stream, buffer: []u8) Writer {
            return self.toInner().writer(io(), buffer);
        }

        pub fn read(self: Stream, buffer: []u8) ReadError!usize {
            if (buffer.len == 0) return 0;
            if (comptime builtin.os.tag == .windows) {
                var data = [_][]u8{buffer};
                return io().vtable.netRead(io().userdata, self.handle, &data);
            }
            return posix.read(self.handle, buffer);
        }

        pub fn readAtLeast(self: Stream, buffer: []u8, len: usize) ReadError!usize {
            std.debug.assert(len <= buffer.len);
            var index: usize = 0;
            while (index < len) {
                const amt = try self.read(buffer[index..]);
                if (amt == 0) break;
                index += amt;
            }
            return index;
        }

        pub fn write(self: Stream, bytes: []const u8) WriteError!usize {
            var stream_writer = self.toInner().writer(io(), &[_]u8{});
            stream_writer.interface.writeAll(bytes) catch |err| switch (err) {
                error.WriteFailed => return stream_writer.err orelse error.Unexpected,
            };
            return bytes.len;
        }

        pub fn writeAll(self: Stream, bytes: []const u8) WriteError!void {
            var stream_writer = self.toInner().writer(io(), &[_]u8{});
            stream_writer.interface.writeAll(bytes) catch |err| switch (err) {
                error.WriteFailed => return stream_writer.err orelse error.Unexpected,
            };
        }

        pub fn shutdown(self: Stream, how: IoNet.ShutdownHow) IoNet.ShutdownError!void {
            try self.toInner().shutdown(io(), how);
        }
    };

    pub const Ip4Address = extern struct {
        sa: posix.sockaddr.in,

        pub fn getPort(self: Ip4Address) u16 {
            return std.mem.bigToNative(u16, self.sa.port);
        }

        pub fn setPort(self: *Ip4Address, port: u16) void {
            self.sa.port = std.mem.nativeToBig(u16, port);
        }

        pub fn getOsSockLen(self: Ip4Address) posix.socklen_t {
            _ = self;
            return @sizeOf(posix.sockaddr.in);
        }
    };

    pub const Ip6Address = extern struct {
        sa: posix.sockaddr.in6,

        pub fn getPort(self: Ip6Address) u16 {
            return std.mem.bigToNative(u16, self.sa.port);
        }

        pub fn setPort(self: *Ip6Address, port: u16) void {
            self.sa.port = std.mem.nativeToBig(u16, port);
        }

        pub fn getOsSockLen(self: Ip6Address) posix.socklen_t {
            _ = self;
            return @sizeOf(posix.sockaddr.in6);
        }
    };

    fn ip4FromCurrent(ip4: IoNet.Ip4Address) Ip4Address {
        return .{
            .sa = .{
                .port = std.mem.nativeToBig(u16, ip4.port),
                .addr = @as(*align(1) const u32, @ptrCast(&ip4.bytes)).*,
            },
        };
    }

    fn ip4ToCurrent(ip4: Ip4Address) IoNet.Ip4Address {
        return .{
            .bytes = @bitCast(ip4.sa.addr),
            .port = ip4.getPort(),
        };
    }

    fn ip6FromCurrent(ip6: IoNet.Ip6Address) Ip6Address {
        return .{
            .sa = .{
                .port = std.mem.nativeToBig(u16, ip6.port),
                .flowinfo = ip6.flow,
                .addr = ip6.bytes,
                .scope_id = ip6.interface.index,
            },
        };
    }

    fn ip6ToCurrent(ip6: Ip6Address) IoNet.Ip6Address {
        return .{
            .port = ip6.getPort(),
            .bytes = ip6.sa.addr,
            .flow = ip6.sa.flowinfo,
            .interface = .{ .index = ip6.sa.scope_id },
        };
    }

    fn setNonBlocking(handle: IoNet.Socket.Handle, enabled: bool) !void {
        if (comptime builtin.os.tag == .windows) return;

        const flags: u32 = blk: {
            const rc = posix.system.fcntl(handle, posix.F.GETFL, @as(c_int, 0));
            switch (posix.errno(rc)) {
                .SUCCESS => break :blk @intCast(rc),
                else => |err| return posix.unexpectedErrno(err),
            }
        };

        const nonblocking = @as(u32, @bitCast(posix.O{ .NONBLOCK = true }));
        const next_flags = if (enabled) flags | nonblocking else flags & ~nonblocking;
        switch (posix.errno(posix.system.fcntl(handle, posix.F.SETFL, next_flags))) {
            .SUCCESS => {},
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    pub const Address = extern union {
        any: posix.sockaddr,
        in: Ip4Address,
        in6: Ip6Address,

        fn fromCurrent(addr: IoNet.IpAddress) Address {
            return switch (addr) {
                .ip4 => |ip4| .{ .in = ip4FromCurrent(ip4) },
                .ip6 => |ip6| .{ .in6 = ip6FromCurrent(ip6) },
            };
        }

        pub fn parseIp4(name: []const u8, port: u16) !Address {
            return fromCurrent(try IoNet.IpAddress.parseIp4(name, port));
        }

        pub fn parseIp6(name: []const u8, port: u16) !Address {
            return fromCurrent(try IoNet.IpAddress.parseIp6(name, port));
        }

        pub fn parseIp(name: []const u8, port: u16) !Address {
            return fromCurrent(try IoNet.IpAddress.parse(name, port));
        }

        pub fn initUnix(_: []const u8) !Address {
            return error.UnixSocketsNotSupported;
        }

        pub fn resolveIp(name: []const u8, port: u16) !Address {
            return fromCurrent(try IoNet.IpAddress.resolve(io(), name, port));
        }

        pub fn toCurrent(self: Address) IoNet.IpAddress {
            return switch (self.any.family) {
                posix.AF.INET => .{ .ip4 = ip4ToCurrent(self.in) },
                posix.AF.INET6 => .{ .ip6 = ip6ToCurrent(self.in6) },
                else => unreachable,
            };
        }

        pub fn format(self: Address, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try self.toCurrent().format(writer);
        }

        pub fn getOsSockLen(self: Address) posix.socklen_t {
            return switch (self.any.family) {
                posix.AF.INET => self.in.getOsSockLen(),
                posix.AF.INET6 => self.in6.getOsSockLen(),
                else => @sizeOf(posix.sockaddr),
            };
        }

        pub const ListenOptions = struct {
            reuse_address: bool = false,
            force_nonblocking: bool = false,
        };

        pub fn listen(self: Address, options: ListenOptions) !Server {
            const current = self.toCurrent();
            const server = try current.listen(io(), .{
                .reuse_address = options.reuse_address,
                .mode = .stream,
                .protocol = .tcp,
            });
            try setNonBlocking(server.socket.handle, options.force_nonblocking);

            return .{
                .listen_address = Address.fromCurrent(server.socket.address),
                .stream = .{ .handle = server.socket.handle },
            };
        }
    };

    pub const Server = struct {
        listen_address: Address,
        stream: Stream,

        pub const Connection = struct {
            stream: Stream,
            address: Address,
        };

        pub fn deinit(self: *Server) void {
            self.stream.close();
            self.* = undefined;
        }

        pub const AcceptError = IoNet.Server.AcceptError;

        pub fn accept(self: *Server) AcceptError!Connection {
            const accept_options: IoNet.Server.AcceptOptions = if (comptime IoNet.Server.AcceptOptions == void) {} else .{ .mode = .stream, .protocol = .tcp };
            var server: IoNet.Server = .{
                .socket = .{
                    .handle = self.stream.handle,
                    .address = self.listen_address.toCurrent(),
                },
                .options = accept_options,
            };
            const stream = try server.accept(io());
            try setNonBlocking(stream.socket.handle, false);
            return .{
                .stream = .{ .handle = stream.socket.handle },
                .address = Address.fromCurrent(stream.socket.address),
            };
        }
    };

    pub const AddressList = struct {
        arena: std.heap.ArenaAllocator,
        addrs: []Address,
        canon_name: ?[]u8 = null,

        pub fn deinit(self: *AddressList) void {
            var arena = self.arena;
            arena.deinit();
        }
    };

    pub const GetAddressListError = Allocator.Error || error{
        TemporaryNameServerFailure,
        NameServerFailure,
        AddressFamilyNotSupported,
        UnknownHostName,
        ServiceUnavailable,
        Unexpected,
        SystemResources,
    };

    pub fn tcpConnectToAddress(address: Address) !Stream {
        const stream = try address.toCurrent().connect(io(), .{
            .mode = .stream,
            .protocol = .tcp,
        });
        try setNonBlocking(stream.socket.handle, false);
        return .{ .handle = stream.socket.handle };
    }

    pub fn tcpConnectToAddresses(addresses: []const Address) !Stream {
        var last_err: ?anyerror = null;
        for (addresses) |address| {
            return tcpConnectToAddress(address) catch |err| {
                last_err = err;
                continue;
            };
        }
        return last_err orelse error.UnknownHostName;
    }

    pub fn tcpConnectToHost(allocator: Allocator, host: []const u8, port: u16) !Stream {
        const addresses = try getAddressList(allocator, host, port);
        defer addresses.deinit();
        if (addresses.addrs.len == 0) return error.UnknownHostName;
        return tcpConnectToAddresses(addresses.addrs);
    }

    pub fn getAddressList(gpa: Allocator, name: []const u8, port: u16) GetAddressListError!*AddressList {
        const result = blk: {
            var arena = std.heap.ArenaAllocator.init(gpa);
            errdefer arena.deinit();

            const list = try arena.allocator().create(AddressList);
            list.* = .{
                .arena = arena,
                .addrs = undefined,
                .canon_name = null,
            };
            break :blk list;
        };
        errdefer result.deinit();

        const arena = result.arena.allocator();

        if (Address.resolveIp(name, port)) |addr| {
            result.addrs = try arena.dupe(Address, &.{addr});
            return result;
        } else |_| {}

        if (comptime builtin.os.tag == .windows) {
            const host_name = IoNet.HostName.init(name) catch return error.UnknownHostName;
            var canonical_name_buffer: [IoNet.HostName.max_len]u8 = undefined;
            var lookup_buffer: [32]IoNet.HostName.LookupResult = undefined;
            var lookup_queue: std.Io.Queue(IoNet.HostName.LookupResult) = .init(&lookup_buffer);
            var lookup_future = io().async(IoNet.HostName.lookup, .{
                host_name,
                io(),
                &lookup_queue,
                .{
                    .port = port,
                    .canonical_name_buffer = &canonical_name_buffer,
                },
            });
            defer lookup_future.cancel(io()) catch {};

            var addrs: std.ArrayList(Address) = .empty;
            defer addrs.deinit(arena);

            while (lookup_queue.getOne(io())) |lookup_result| switch (lookup_result) {
                .address => |address| try addrs.append(arena, Address.fromCurrent(address)),
                .canonical_name => |canonical_name| {
                    result.canon_name = try arena.dupe(u8, canonical_name.bytes);
                },
            } else |err| switch (err) {
                error.Canceled => return error.Unexpected,
                error.Closed => {
                    lookup_future.await(io()) catch |lookup_err| switch (lookup_err) {
                        error.UnknownHostName, error.NoAddressReturned => return error.UnknownHostName,
                        error.NameServerFailure => return error.NameServerFailure,
                        error.AddressFamilyUnsupported => return error.AddressFamilyNotSupported,
                        error.SystemResources => return error.SystemResources,
                        error.NetworkDown, error.DetectingNetworkConfigurationFailed => return error.ServiceUnavailable,
                        error.ResolvConfParseFailed,
                        error.InvalidDnsARecord,
                        error.InvalidDnsAAAARecord,
                        error.InvalidDnsCnameRecord,
                        error.Canceled,
                        => return error.Unexpected,
                        else => return error.Unexpected,
                    };
                },
            }

            result.addrs = try addrs.toOwnedSlice(arena);
            if (result.addrs.len == 0) return error.UnknownHostName;
            return result;
        }

        var name_buffer: [IoNet.HostName.max_len:0]u8 = undefined;
        @memcpy(name_buffer[0..name.len], name);
        name_buffer[name.len] = 0;
        const name_c = name_buffer[0..name.len :0];

        var port_buffer: [8]u8 = undefined;
        const port_c = std.fmt.bufPrintZ(&port_buffer, "{d}", .{port}) catch unreachable;

        const hints: posix.addrinfo = .{
            .flags = .{ .CANONNAME = false, .NUMERICSERV = true },
            .family = posix.AF.UNSPEC,
            .socktype = posix.SOCK.STREAM,
            .protocol = posix.IPPROTO.TCP,
            .canonname = null,
            .addr = null,
            .addrlen = 0,
            .next = null,
        };
        var res: ?*posix.addrinfo = null;
        switch (posix.system.getaddrinfo(name_c.ptr, port_c.ptr, &hints, &res)) {
            @as(posix.system.EAI, @enumFromInt(0)) => {},
            .ADDRFAMILY, .FAMILY => return error.AddressFamilyNotSupported,
            .AGAIN => return error.TemporaryNameServerFailure,
            .FAIL => return error.NameServerFailure,
            .MEMORY => return error.SystemResources,
            .NODATA, .NONAME => return error.UnknownHostName,
            else => return error.Unexpected,
        }
        defer if (res) |some| posix.system.freeaddrinfo(some);

        var addrs: std.ArrayList(Address) = .empty;
        defer addrs.deinit(arena);

        var it = res;
        while (it) |info| : (it = info.next) {
            const addr = info.addr orelse continue;
            switch (addr.family) {
                posix.AF.INET => try addrs.append(arena, .{ .in = .{ .sa = @as(*const posix.sockaddr.in, @ptrCast(@alignCast(addr))).* } }),
                posix.AF.INET6 => try addrs.append(arena, .{ .in6 = .{ .sa = @as(*const posix.sockaddr.in6, @ptrCast(@alignCast(addr))).* } }),
                else => {},
            }
        }

        result.addrs = try addrs.toOwnedSlice(arena);
        return result;
    }
};

pub const sync = struct {
    pub const Mutex = struct {
        inner: std.Io.Mutex = .init,

        pub fn tryLock(self: *Mutex) bool {
            return self.inner.tryLock();
        }

        pub fn lock(self: *Mutex) void {
            self.inner.lockUncancelable(io());
        }

        pub fn unlock(self: *Mutex) void {
            self.inner.unlock(io());
        }
    };

    pub const Condition = struct {
        inner: std.Io.Condition = .init,

        pub fn wait(self: *Condition, mutex: *Mutex) void {
            self.inner.waitUncancelable(io(), &mutex.inner);
        }

        pub fn signal(self: *Condition) void {
            self.inner.signal(io());
        }

        pub fn broadcast(self: *Condition) void {
            self.inner.broadcast(io());
        }
    };
};
