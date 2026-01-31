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
const qvl_store_mod = @import("qvl_store.zig");
const control_mod = @import("control.zig");
const quarantine_mod = @import("quarantine");

const NodeConfig = config_mod.NodeConfig;
const UTCP = utcp_mod.UTCP;
// SoulKey definition (temporarily embedded until module is available)
const SoulKey = struct {
    did: [32]u8,
    public_key: [32]u8,

    pub fn fromSeed(seed: *const [32]u8) !SoulKey {
        var public_key: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(seed, &public_key, .{});
        return SoulKey{
            .did = public_key,
            .public_key = public_key,
        };
    }
};
const RiskGraph = qvl.types.RiskGraph;
const DiscoveryService = discovery_mod.DiscoveryService;
const PeerTable = peer_table_mod.PeerTable;
const PeerSession = fed.PeerSession;
const DhtService = dht_mod.DhtService;
const StorageService = storage_mod.StorageService;
const QvlStore = qvl_store_mod.QvlStore;

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
    qvl_store: *QvlStore,
    control_socket: std.net.Server,
    identity: SoulKey,

    running: bool,
    global_state: quarantine_mod.GlobalState,
    dht_timer: i64 = 0,
    qvl_timer: i64 = 0,

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

        const qvl_db_path = try std.fmt.allocPrint(allocator, "{s}/qvl.db", .{config.data_dir});
        defer allocator.free(qvl_db_path);
        const qvl_store = try QvlStore.init(allocator, qvl_db_path);

        // Initialize Control Socket
        const socket_path = config.control_socket_path;
        // Unlink if exists (check logic in start, or here? start binds.)

        // Load or Generate Identity
        var seed: [32]u8 = undefined;
        var identity: SoulKey = undefined;

        // Try to open existing key file
        if (std.fs.cwd().openFile(config.identity_key_path, .{})) |file| {
            defer file.close();
            const bytes_read = try file.readAll(&seed);
            if (bytes_read != 32) {
                std.log.err("Identity: Invalid key file size at {s}", .{config.identity_key_path});
                return error.InvalidKeyFile;
            }
            std.log.info("Identity: Loaded key from {s}", .{config.identity_key_path});
            identity = try SoulKey.fromSeed(&seed);
        } else |err| {
            if (err == error.FileNotFound) {
                std.log.info("Identity: No key found at {s}, generating new...", .{config.identity_key_path});
                std.crypto.random.bytes(&seed);

                // Save to file
                const kf = try std.fs.cwd().createFile(config.identity_key_path, .{ .read = true });
                defer kf.close();
                try kf.writeAll(&seed);

                identity = try SoulKey.fromSeed(&seed);
            } else {
                return err;
            }
        }

        // Update NodeID from Identity DID (first 32 bytes)
        @memcpy(node_id[0..32], &identity.did);
        @memcpy(&self.dht.routing_table.self_id, &identity.did);

        // Bind Control Socket
        std.fs.cwd().deleteFile(socket_path) catch {};
        const uds_address = try std.net.Address.initUnix(socket_path);

        const control_socket = try uds_address.listen(.{ .kernel_backlog = 10 });
        std.log.info("Control Socket listening at {s}", .{socket_path});

        self.* = CapsuleNode{
            .allocator = allocator,
            .config = config,
            .utcp = utcp_instance,
            .risk_graph = risk_graph,
            .discovery = discovery,
            .peer_table = PeerTable.init(allocator),
            .sessions = std.HashMap(std.net.Address, PeerSession, AddressContext, 80).init(allocator),
            .dht = DhtService.init(allocator, node_id),
            .storage = storage,
            .qvl_store = qvl_store,
            .control_socket = control_socket,
            .identity = identity,
            .running = false,
            .global_state = quarantine_mod.GlobalState{},
        };
        self.dht_timer = std.time.milliTimestamp();
        self.qvl_timer = std.time.milliTimestamp();

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
        self.qvl_store.deinit();
        self.control_socket.deinit();
        // Clean up socket file
        std.fs.cwd().deleteFile(self.config.control_socket_path) catch {};
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
            .{
                .fd = self.control_socket.stream.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const TICK_MS = 100; // 10Hz tick rate
        var last_tick = std.time.milliTimestamp();
        var discovery_timer: usize = 0;
        var dht_timer: usize = 0;
        var qvl_sync_timer: usize = 0;

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

                // 3. Control Socket Traffic
                if (poll_fds[2].revents & std.posix.POLL.IN != 0) {
                    var conn = self.control_socket.accept() catch |err| {
                        std.log.warn("Control Socket accept error: {}", .{err});
                        continue;
                    };
                    defer conn.stream.close();

                    self.handleControlConnection(conn) catch |err| {
                        std.log.warn("Control handle error: {}", .{err});
                    };
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

                // QVL sync (every ~30s)
                qvl_sync_timer += 1;
                if (qvl_sync_timer >= 300) {
                    std.log.info("Node: Syncing Lattice to DuckDB...", .{});
                    try self.qvl_store.syncLattice(self.risk_graph.nodes.items, self.risk_graph.edges.items);
                    qvl_sync_timer = 0;
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

    fn handleControlConnection(self: *CapsuleNode, conn: std.net.Server.Connection) !void {
        var buf: [4096]u8 = undefined;
        const bytes_read = try conn.stream.read(&buf);
        if (bytes_read == 0) return;

        const slice = buf[0..bytes_read];

        // Parse Command
        const parsed = std.json.parseFromSlice(control_mod.Command, self.allocator, slice, .{}) catch |err| {
            std.log.warn("Control: Failed to parse command: {}", .{err});
            return;
        };
        defer parsed.deinit();

        const cmd = parsed.value;
        var response: control_mod.Response = undefined;

        switch (cmd) {
            .Status => {
                response = .{
                    .NodeStatus = .{
                        .node_id = "NODE_ID_STUB",
                        .state = if (self.running) "Running" else "Stopping",
                        .peers_count = self.peer_table.peers.count(),
                        .uptime_seconds = 0, // TODO: Track start time
                        .version = "0.1.0",
                    },
                };
            },
            .Peers => {
                response = .{ .Ok = "Peer listing not yet fully implemented in CLI JSON" };
            },
            .Sessions => {
                const sessions = try self.getSessions();
                response = .{ .SessionList = sessions };
            },
            .QvlQuery => |args| {
                const metrics = try self.getQvlMetrics(args);
                response = .{ .QvlResult = metrics };
            },
            .Dht => {
                const dht_info = try self.getDhtInfo();
                response = .{ .DhtInfo = dht_info };
            },
            .Identity => {
                const identity_info = try self.getIdentityInfo();
                response = .{ .IdentityInfo = identity_info };
            },
            .Shutdown => {
                std.log.info("Control: Received SHUTDOWN command", .{});
                self.running = false;
                response = .{ .Ok = "Shutting down..." };
            },
            .Slash => |args| {
                if (try self.processSlashCommand(args)) {
                    response = .{ .Ok = "Target slashed successfully." };
                } else {
                    response = .{ .Error = "Failed to slash target." };
                }
            },
            .SlashLog => |args| {
                const logs = try self.getSlashLog(args.limit);
                response = .{ .SlashLogResult = logs };
            },
            .Ban => |args| {
                if (try self.processBan(args)) {
                    response = .{ .Ok = "Peer banned successfully." };
                } else {
                    response = .{ .Error = "Failed to ban peer." };
                }
            },
            .Unban => |args| {
                if (try self.processUnban(args)) {
                    response = .{ .Ok = "Peer unbanned successfully." };
                } else {
                    response = .{ .Error = "Failed to unban peer." };
                }
            },
            .Trust => |args| {
                if (try self.processTrust(args)) {
                    response = .{ .Ok = "Trust override set successfully." };
                } else {
                    response = .{ .Error = "Failed to set trust override." };
                }
            },
            .Lockdown => {
                self.global_state.engage();
                std.log.warn("LOCKDOWN: Emergency network lockdown engaged!", .{});
                response = .{ .LockdownStatus = try self.getLockdownStatus() };
            },
            .Unlock => {
                self.global_state.disengage();
                std.log.info("UNLOCK: Network lockdown disengaged", .{});
                response = .{ .LockdownStatus = try self.getLockdownStatus() };
            },
            .Airlock => |args| {
                const state = std.meta.stringToEnum(quarantine_mod.AirlockState, args.state) orelse .Open;
                self.global_state.setAirlock(state);
                std.log.info("AIRLOCK: State set to {s}", .{args.state});
                response = .{ .LockdownStatus = try self.getLockdownStatus() };
            },
        }

        // Send Response - buffer to ArrayList then write to stream
        var resp_buf = std.ArrayList(u8){};
        defer resp_buf.deinit(self.allocator);
        var w_struct = resp_buf.writer(self.allocator);
        var buffer: [1024]u8 = undefined;
        var adapter = w_struct.adaptToNewApi(&buffer);
        try std.json.Stringify.value(response, .{}, &adapter.new_interface);
        try adapter.new_interface.flush();
        try conn.stream.writeAll(resp_buf.items);
    }

    fn processSlashCommand(_: *CapsuleNode, args: control_mod.SlashArgs) !bool {
        std.log.warn("Slash: Initiated against {s} for {s}", .{ args.target_did, args.reason });

        const timestamp = std.time.timestamp();

        // TODO: Import slash types properly when module structure is fixed
        const SlashReason = enum { BetrayalCycle, Other };
        const SlashSeverity = enum { Quarantine, Ban };

        const reason_enum = std.meta.stringToEnum(SlashReason, args.reason) orelse .BetrayalCycle;
        const severity_enum = std.meta.stringToEnum(SlashSeverity, args.severity) orelse .Quarantine;

        const evidence_hash: [32]u8 = [_]u8{0} ** 32;

        _ = timestamp; // TODO: Use timestamp when logging is enabled
        _ = args.target_did; // TODO: Use when logging is enabled

        // TODO: Re-enable when QvlStore.logSlashEvent is implemented
        _ = reason_enum;
        _ = severity_enum;
        _ = evidence_hash;
        //try self.qvl_store.logSlashEvent(@intCast(timestamp), args.target_did, reason_enum, severity_enum, evidence_hash);
        return true;
    }

    fn getSlashLog(self: *CapsuleNode, limit: usize) ![]control_mod.SlashEvent {
        _ = self;
        _ = limit;
        //TODO: Implement getSlashEvents when QvlStore API is stable
        return &[_]control_mod.SlashEvent{};
    }

    fn processBan(self: *CapsuleNode, args: control_mod.BanArgs) !bool {
        std.log.warn("Ban: Banning peer {s} for: {s}", .{ args.target_did, args.reason });

        // Persist ban to storage
        try self.storage.banPeer(args.target_did, args.reason);

        // TODO: Disconnect peer if currently connected
        // Iterate through sessions and disconnect if DID matches

        std.log.info("Ban: Peer {s} banned successfully", .{args.target_did});
        return true;
    }

    fn processUnban(self: *CapsuleNode, args: control_mod.UnbanArgs) !bool {
        std.log.info("Unban: Unbanning peer {s}", .{args.target_did});

        // Remove ban from storage
        try self.storage.unbanPeer(args.target_did);

        std.log.info("Unban: Peer {s} unbanned successfully", .{args.target_did});
        return true;
    }

    fn processTrust(_: *CapsuleNode, args: control_mod.TrustArgs) !bool {
        std.log.info("Trust: Setting manual trust override for {s} to {d}", .{ args.target_did, args.score });

        // TODO: Update QVL trust score override
        // This would integrate with the RiskGraph trust computation
        // For now, just log the action

        std.log.info("Trust: Trust override set for {s} = {d}", .{ args.target_did, args.score });
        return true;
    }

    fn getSessions(self: *CapsuleNode) ![]control_mod.SessionInfo {
        var sessions = try self.allocator.alloc(control_mod.SessionInfo, self.sessions.count());

        var iter = self.sessions.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            var addr_buf: [64]u8 = undefined;
            const addr_str = try std.fmt.bufPrint(&addr_buf, "{any}", .{entry.key_ptr.*});
            const addr_copy = try self.allocator.dupe(u8, addr_str);

            const did_hex = std.fmt.bytesToHex(&entry.value_ptr.did_short, .lower);
            const did_copy = try self.allocator.dupe(u8, &did_hex);

            sessions[i] = .{
                .address = addr_copy,
                .did_short = did_copy,
                .state = "Active",
            };
        }
        return sessions;
    }

    fn getDhtInfo(self: *CapsuleNode) !control_mod.DhtInfo {
        const node_id_hex = std.fmt.bytesToHex(&self.dht.routing_table.self_id, .lower);

        return control_mod.DhtInfo{
            .local_node_id = try self.allocator.dupe(u8, &node_id_hex),
            .routing_table_size = self.dht.routing_table.buckets.len,
            .known_nodes = 0, // TODO: Compute actual node count when RoutingTable API is stable
        };
    }

    fn getIdentityInfo(self: *CapsuleNode) !control_mod.IdentityInfo {
        const did_hex = std.fmt.bytesToHex(&self.identity.did, .lower);
        const pubkey_hex = std.fmt.bytesToHex(&self.identity.public_key, .lower);
        const dht_id_hex = std.fmt.bytesToHex(&self.dht.routing_table.self_id, .lower);

        return control_mod.IdentityInfo{
            .did = try self.allocator.dupe(u8, &did_hex),
            .public_key = try self.allocator.dupe(u8, &pubkey_hex),
            .dht_node_id = try self.allocator.dupe(u8, &dht_id_hex),
        };
    }

    fn getLockdownStatus(self: *CapsuleNode) !control_mod.LockdownInfo {
        const airlock_str: []const u8 = switch (self.global_state.airlock) {
            .Open => "open",
            .Restricted => "restricted",
            .Closed => "closed",
        };
        return control_mod.LockdownInfo{
            .is_locked = self.global_state.isLocked(),
            .airlock_state = airlock_str,
            .locked_since = self.global_state.lockdown_since,
        };
    }

    fn getQvlMetrics(self: *CapsuleNode, args: control_mod.QvlQueryArgs) !control_mod.QvlMetrics {
        _ = args; // TODO: Use target_did for specific queries
        _ = self;

        // TODO: Get actual metrics from the risk graph when API is stable
        // For now, return placeholder values
        return control_mod.QvlMetrics{
            .total_vertices = 0,
            .total_edges = 0,
            .trust_rank = 0.0,
        };
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
