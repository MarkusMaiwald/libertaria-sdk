//! Capsule Node Orchestrator
//! Binds L0 (Transport) and L1 (Identity) into a sovereign event loop.

const std = @import("std");
const config_mod = @import("config.zig");
const l0 = @import("l0_transport");
// access UTCP from l0 or utcp module directly
// build.zig imports "utcp" into capsule
const utcp_mod = @import("utcp");
// l1_identity module
const l1 = @import("l1_identity");
// qvl module
const qvl = @import("qvl");

const discovery_mod = @import("discovery.zig");
const peer_table_mod = @import("peer_table.zig");
const fed = @import("federation.zig");
const dht_mod = @import("dht.zig");
const storage_mod = @import("storage.zig");

const NodeConfig = config_mod.NodeConfig;
const UTCP = utcp_mod.UTCP;
const RiskGraph = qvl.types.RiskGraph;
const DiscoveryService = discovery_mod.DiscoveryService;
const PeerTable = peer_table_mod.PeerTable;
const PeerSession = fed.PeerSession;
const DhtService = dht_mod.DhtService;
const StorageService = storage_mod.StorageService;

pub const AddressContext = struct {
    pub fn hash(self: AddressContext, s: std.net.Address) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        const bytes = @as([*]const u8, @ptrCast(&s.any))[0..s.getOsSockLen()];
        h.update(bytes);
        return h.final();
    }
    pub fn eql(self: AddressContext, a: std.net.Address, b: std.net.Address) bool {
        _ = self;
        return a.eql(b);
    }
};

pub const CapsuleNode = struct {
    allocator: std.mem.Allocator,
    config: NodeConfig,

    // Subsystems
    utcp: UTCP,
    risk_graph: RiskGraph,
    discovery: DiscoveryService,
    peer_table: PeerTable,
    sessions: std.HashMap(std.net.Address, PeerSession, AddressContext, std.hash_map.default_max_load_percentage),
    dht: DhtService,
    storage: *StorageService,

    running: bool,

    pub fn init(allocator: std.mem.Allocator, config: NodeConfig) !*CapsuleNode {
        const self = try allocator.create(CapsuleNode);

        // Ensure data directory exists
        std.fs.cwd().makePath(config.data_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Initialize L0 (UTCP)
        const address = try std.net.Address.parseIp("0.0.0.0", config.port);
        const utcp_instance = try UTCP.init(allocator, address);

        // Initialize L1 (RiskGraph)
        const risk_graph = RiskGraph.init(allocator);

        // Initialize Discovery (mDNS)
        const discovery = try DiscoveryService.init(allocator, config.port);

        // Initialize DHT
        var node_id: dht_mod.NodeId = [_]u8{0} ** 32;
        // TODO: Generate real NodeID from Public Key
        std.mem.copyForwards(u8, node_id[0..4], "NODE");

        // Initialize Storage
        var db_path_buf: [256]u8 = undefined;
        const db_path = try std.fmt.bufPrint(&db_path_buf, "{s}/capsule.db", .{config.data_dir});
        const storage = try StorageService.init(allocator, db_path);

        self.* = CapsuleNode{
            .allocator = allocator,
            .config = config,
            .utcp = utcp_instance,
            .risk_graph = risk_graph,
            .discovery = discovery,
            .peer_table = PeerTable.init(allocator),
            .sessions = std.HashMap(std.net.Address, PeerSession, AddressContext, std.hash_map.default_max_load_percentage).init(allocator),
            .dht = DhtService.init(allocator, node_id),
            .storage = storage,
            .running = false,
        };

        // Pre-populate from storage
        const stored_peers = try storage.loadPeers(allocator);
        defer allocator.free(stored_peers);
        for (stored_peers) |peer| {
            try self.dht.routing_table.update(peer);
        }

        return self;
    }

    pub fn deinit(self: *CapsuleNode) void {
        self.utcp.deinit();
        self.risk_graph.deinit();
        self.discovery.deinit();
        self.peer_table.deinit();
        self.sessions.deinit();
        self.dht.deinit();
        self.storage.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *CapsuleNode) !void {
        self.running = true;
        std.log.info("CapsuleNode starting on port {d}...", .{self.config.port});
        std.log.info("Data directory: {s}", .{self.config.data_dir});

        // Setup polling
        var poll_fds = [_]std.posix.pollfd{
            .{
                .fd = self.utcp.fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
            .{
                .fd = self.discovery.fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const TICK_MS = 100; // 10Hz tick rate
        var last_tick = std.time.milliTimestamp();
        var discovery_timer: usize = 0;
        var dht_timer: usize = 0;

        while (self.running) {
            const ready_count = try std.posix.poll(&poll_fds, TICK_MS);

            if (ready_count > 0) {
                // 1. UTCP Traffic
                if (poll_fds[0].revents & std.posix.POLL.IN != 0) {
                    var buf: [1500]u8 = undefined;
                    if (self.utcp.receiveFrame(self.allocator, &buf)) |result| {
                        var frame = result.frame;
                        defer frame.deinit(self.allocator);

                        if (frame.header.service_type == fed.SERVICE_TYPE) {
                            try self.handleFederationMessage(result.sender, frame);
                        }
                    } else |err| {
                        if (err != error.WouldBlock) std.log.warn("UTCP receive error: {}", .{err});
                    }
                }

                // 2. Discovery Traffic
                if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
                    var m_buf: [2048]u8 = undefined;
                    var src_addr: std.posix.sockaddr = undefined;
                    var src_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
                    const bytes = std.posix.recvfrom(self.discovery.fd, &m_buf, 0, &src_addr, &src_len) catch |err| blk: {
                        if (err != error.WouldBlock) std.log.warn("Discovery recv error: {}", .{err});
                        break :blk @as(usize, 0);
                    };
                    if (bytes > 0) {
                        try self.discovery.handlePacket(&self.peer_table, m_buf[0..bytes], std.net.Address{ .any = src_addr });
                    }
                }
            }

            // 3. Periodic Ticks
            const now = std.time.milliTimestamp();
            if (now - last_tick >= TICK_MS) {
                try self.tick();
                last_tick = now;

                // Discovery cycle (every ~5s)
                discovery_timer += 1;
                if (discovery_timer >= 50) {
                    self.discovery.announce() catch {};
                    self.discovery.query() catch {};
                    discovery_timer = 0;
                }

                // DHT refresh (every ~60s)
                dht_timer += 1;
                if (dht_timer >= 600) {
                    try self.bootstrap();
                    dht_timer = 0;
                }
            }
        }
    }

    pub fn bootstrap(self: *CapsuleNode) !void {
        std.log.info("DHT: Refreshing routing table...", .{});
        // Start self-lookup to fill buckets
        // For now, just ping federated sessions
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.state == .Federated) {
                try self.sendFederationMessage(entry.key_ptr.*, .{
                    .dht_find_node = .{ .target_id = self.dht.routing_table.self_id },
                });
            }
        }
    }

    fn tick(self: *CapsuleNode) !void {
        self.peer_table.tick();

        // Initiate handshakes with discovered active peers
        self.peer_table.mutex.lock();
        defer self.peer_table.mutex.unlock();

        var it = self.peer_table.peers.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.is_active and !self.sessions.contains(entry.value_ptr.address)) {
                try self.connectToPeer(entry.value_ptr.address, entry.key_ptr.*);
            }
        }
    }

    pub fn stop(self: *CapsuleNode) void {
        self.running = false;
    }

    pub fn updateRoutingTable(self: *CapsuleNode, node: storage_mod.RemoteNode) !void {
        try self.dht.routing_table.update(node);
        // Persist to SQLite
        self.storage.savePeer(node) catch |err| {
            std.log.warn("SQLite: Failed to save peer {any}: {}", .{ node.id[0..4], err });
        };
    }

    fn handleFederationMessage(self: *CapsuleNode, sender: std.net.Address, frame: l0.LWFFrame) !void {
        var fbs = std.io.fixedBufferStream(frame.payload);
        const msg = fed.FederationMessage.decode(fbs.reader(), self.allocator) catch |err| {
            std.log.warn("Failed to decode federation message from {f}: {}", .{ sender, err });
            return;
        };

        switch (msg) {
            .hello => |h| {
                std.log.info("Received HELLO from {f} (ID: {x})", .{ sender, h.did_short });
                // If we don't have a session, create one and reply WELCOME
                if (!self.sessions.contains(sender)) {
                    try self.sessions.put(sender, PeerSession.init(sender, h.did_short));
                }

                // Reply WELCOME
                const reply = fed.FederationMessage{
                    .welcome = .{ .did_short = [_]u8{0} ** 8 }, // TODO: Real DID
                };
                try self.sendFederationMessage(sender, reply);
            },
            .welcome => |w| {
                std.log.info("Received WELCOME from {f} (ID: {x})", .{ sender, w.did_short });
                if (self.sessions.getPtr(sender)) |session| {
                    session.state = .Federated; // In Week 28 we skip AUTH for stubbing
                    std.log.info("Node {f} is now FEDERATED", .{sender});

                    // After federation, also ping to join DHT
                    try self.sendFederationMessage(sender, .{
                        .dht_ping = .{ .node_id = self.dht.routing_table.self_id },
                    });
                }
            },
            .auth => |a| {
                _ = a;
                // Handled in Week 29
            },
            .dht_ping => |p| {
                std.log.debug("DHT: PING from {f}", .{sender});
                // Update routing table
                try self.updateRoutingTable(.{
                    .id = p.node_id,
                    .address = sender,
                    .last_seen = std.time.milliTimestamp(),
                });
                // Reply PONG
                try self.sendFederationMessage(sender, .{
                    .dht_pong = .{ .node_id = self.dht.routing_table.self_id },
                });
            },
            .dht_pong => |p| {
                std.log.debug("DHT: PONG from {f}", .{sender});
                try self.updateRoutingTable(.{
                    .id = p.node_id,
                    .address = sender,
                    .last_seen = std.time.milliTimestamp(),
                });
            },
            .dht_find_node => |f| {
                std.log.debug("DHT: FIND_NODE from {f}", .{sender});
                const closest = try self.dht.routing_table.findClosest(f.target_id, 20);
                defer self.allocator.free(closest);

                // Convert to federation nodes
                var nodes = try self.allocator.alloc(fed.DhtNode, closest.len);
                for (closest, 0..) |node, i| {
                    nodes[i] = .{ .id = node.id, .address = node.address };
                }

                try self.sendFederationMessage(sender, .{
                    .dht_nodes = .{ .nodes = nodes },
                });
                self.allocator.free(nodes);
            },
            .dht_nodes => |n| {
                std.log.debug("DHT: Received {d} nodes from {f}", .{ n.nodes.len, sender });
                for (n.nodes) |node| {
                    // Update routing table with discovered nodes
                    try self.updateRoutingTable(.{
                        .id = node.id,
                        .address = node.address,
                        .last_seen = std.time.milliTimestamp(),
                    });
                    // TODO: If this was part of a findNode lookup, update the lookup state
                }
                self.allocator.free(n.nodes);
            },
        }
    }

    fn sendFederationMessage(self: *CapsuleNode, target: std.net.Address, msg: fed.FederationMessage) !void {
        var enc_buf: [128]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&enc_buf);
        try msg.encode(fbs.writer());
        const payload = fbs.getWritten();

        var frame = try l0.LWFFrame.init(self.allocator, payload.len);
        defer frame.deinit(self.allocator);

        frame.header.service_type = fed.SERVICE_TYPE;
        frame.header.payload_len = @intCast(payload.len);
        @memcpy(frame.payload, payload);
        frame.updateChecksum();

        try self.utcp.sendFrame(target, &frame, self.allocator);
    }

    /// Initiate connection to a discovered peer
    pub fn connectToPeer(self: *CapsuleNode, address: std.net.Address, did_short: [8]u8) !void {
        if (self.sessions.contains(address)) return;

        std.log.info("Initiating federation handshake with {f} (ID: {x})", .{ address, did_short });
        try self.sessions.put(address, PeerSession.init(address, did_short));

        // Send HELLO
        const msg = fed.FederationMessage{
            .hello = .{
                .did_short = [_]u8{0} ** 8, // TODO: Use real DID hash
                .version = fed.VERSION,
            },
        };

        var enc_buf: [128]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&enc_buf);
        try msg.encode(fbs.writer());
        const payload = fbs.getWritten();

        // Wrap in LWF
        var frame = try l0.LWFFrame.init(self.allocator, payload.len);
        defer frame.deinit(self.allocator);

        frame.header.service_type = fed.SERVICE_TYPE;
        frame.header.payload_len = @intCast(payload.len);
        @memcpy(frame.payload, payload);
        frame.updateChecksum();

        try self.utcp.sendFrame(address, &frame, self.allocator);
    }
};
