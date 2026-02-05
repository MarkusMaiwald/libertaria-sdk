//! GQL to Zig Code Generator
//! 
//! Transpiles GQL AST to Zig programmatic API calls.
//! Turns declarative graph queries into imperative Zig code.

const std = @import("std");
const ast = @import("ast.zig");

const Query = ast.Query;
const Statement = ast.Statement;
const MatchStatement = ast.MatchStatement;
const CreateStatement = ast.CreateStatement;
const GraphPattern = ast.GraphPattern;
const PathPattern = ast.PathPattern;
const NodePattern = ast.NodePattern;
const EdgePattern = ast.EdgePattern;
const Expression = ast.Expression;

/// Code generation context
pub const CodeGenContext = struct {
    allocator: std.mem.Allocator,
    indent_level: usize = 0,
    output: std.ArrayList(u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .indent_level = 0,
            .output = std.ArrayList(u8){},
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }
    
    pub fn getCode(self: *Self) ![]const u8 {
        return self.output.toOwnedSlice(self.allocator);
    }
    
    fn write(self: *Self, text: []const u8) !void {
        try self.output.appendSlice(self.allocator, text);
    }
    
    fn writeln(self: *Self, text: []const u8) !void {
        try self.writeIndent();
        try self.write(text);
        try self.write("\n");
    }
    
    fn writeIndent(self: *Self) !void {
        for (0..self.indent_level) |_| {
            try self.write("    ");
        }
    }
    
    fn indent(self: *Self) void {
        self.indent_level += 1;
    }
    
    fn dedent(self: *Self) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }
};

/// Generate Zig code from GQL query
pub fn generate(allocator: std.mem.Allocator, query: Query) ![]const u8 {
    var ctx = CodeGenContext.init(allocator);
    errdefer ctx.deinit();
    
    // Header
    try ctx.writeln("// Auto-generated from GQL query");
    try ctx.writeln("// Libertaria QVL Programmatic API");
    try ctx.writeln("");
    try ctx.writeln("const std = @import(\"std\");");
    try ctx.writeln("const qvl = @import(\"qvl\");");
    try ctx.writeln("");
    try ctx.writeln("pub fn execute(graph: *qvl.HybridGraph) !void {");
    ctx.indent();
    
    // Generate code for each statement
    for (query.statements) |stmt| {
        try generateStatement(&ctx, stmt);
    }
    
    ctx.dedent();
    try ctx.writeln("}");
    
    return ctx.getCode();
}

fn generateStatement(ctx: *CodeGenContext, stmt: Statement) !void {
    switch (stmt) {
        .match => |m| try generateMatch(ctx, m),
        .create => |c| try generateCreate(ctx, c),
        .delete => |d| try generateDelete(ctx, d),
        .return_stmt => |r| try generateReturn(ctx, r),
    }
}

fn generateMatch(ctx: *CodeGenContext, match: MatchStatement) !void {
    try ctx.writeln("");
    try ctx.writeln("// MATCH statement");
    
    // Generate path traversal for each pattern
    for (match.pattern.paths) |path| {
        try generatePathTraversal(ctx, path);
    }
    
    // Generate WHERE clause if present
    if (match.where) |where| {
        try ctx.write("    // WHERE ");
        try generateExpression(ctx, where);
        try ctx.write("\n");
    }
}

fn generatePathTraversal(ctx: *CodeGenContext, path: PathPattern) !void {
    // Path pattern: (a)-[r]->(b)-[s]->(c)
    // Generate: traverse from start node following edges
    
    if (path.elements.len == 0) return;
    
    // Get start node
    const start_node = path.elements[0].node;
    const start_var = start_node.variable orelse ast.Identifier{ .name = "_" };
    
    try ctx.write("    // Traverse from ");
    try ctx.write(start_var.name);
    try ctx.write("\n");
    
    // For simple 1-hop: getOutgoing and filter
    if (path.elements.len == 3) {
        // (a)-[r]->(b)
        const edge = path.elements[1].edge;
        const end_node = path.elements[2].node;
        
        const edge_var = edge.variable orelse ast.Identifier{ .name = "edge" };
        const end_var = end_node.variable orelse ast.Identifier{ .name = "target" };
        
        try ctx.write("    var ");
        try ctx.write(edge_var.name);
        try ctx.write(" = try graph.getOutgoing(");
        try ctx.write(start_var.name);
        try ctx.write(");\n");
        
        // Filter by edge type if specified
        if (edge.types.len > 0) {
            try ctx.write("    // Filter by type: ");
            for (edge.types) |t| {
                try ctx.write(t.name);
                try ctx.write(" ");
            }
            try ctx.write("\n");
        }
        
        try ctx.write("    var ");
        try ctx.write(end_var.name);
        try ctx.write(" = ");
        try ctx.write(edge_var.name);
        try ctx.write(".to;\n");
    }
}

fn generateCreate(ctx: *CodeGenContext, create: CreateStatement) !void {
    try ctx.writeln("");
    try ctx.writeln("// CREATE statement");
    
    for (create.pattern.paths) |path| {
        // Create nodes and edges
        for (path.elements) |elem| {
            switch (elem) {
                .node => |n| {
                    if (n.variable) |v| {
                        try ctx.write("    const ");
                        try ctx.write(v.name);
                        try ctx.write(" = try graph.addNode(.{ .id = \"");
                        try ctx.write(v.name);
                        try ctx.write("\" });\n");
                    }
                },
                .edge => |e| {
                    if (e.variable) |v| {
                        try ctx.write("    try graph.addEdge(");
                        try ctx.write(v.name);
                        try ctx.write(");\n");
                    }
                },
            }
        }
    }
}

fn generateDelete(ctx: *CodeGenContext, delete: ast.DeleteStatement) !void {
    try ctx.writeln("");
    try ctx.writeln("// DELETE statement");
    
    for (delete.targets) |target| {
        try ctx.write("    try graph.removeNode(");
        try ctx.write(target.name);
        try ctx.write(");\n");
    }
}

fn generateReturn(ctx: *CodeGenContext, ret: ast.ReturnStatement) !void {
    try ctx.writeln("");
    try ctx.writeln("// RETURN statement");
    try ctx.writeln("    var results = std.ArrayList(Result).init(allocator);");
    try ctx.writeln("    defer results.deinit();");
    
    for (ret.items) |item| {
        try ctx.write("    try results.append(");
        try generateExpression(ctx, item.expression);
        try ctx.write(");\n");
    }
}

fn generateExpression(ctx: *CodeGenContext, expr: Expression) !void {
    switch (expr) {
        .identifier => |i| try ctx.write(i.name),
        .literal => |l| try generateLiteral(ctx, l),
        .property_access => |p| {
            try ctx.write(p.object.name);
            try ctx.write(".");
            try ctx.write(p.property.name);
        },
        .comparison => |c| {
            try generateExpression(ctx, c.left.*);
            try ctx.write(" ");
            try ctx.write(comparisonOpToString(c.op));
            try ctx.write(" ");
            try generateExpression(ctx, c.right.*);
        },
        .binary_op => |b| {
            try generateExpression(ctx, b.left.*);
            try ctx.write(" ");
            try ctx.write(binaryOpToString(b.op));
            try ctx.write(" ");
            try generateExpression(ctx, b.right.*);
        },
        else => try ctx.write("/* complex expression */"),
    }
}

fn generateLiteral(ctx: *CodeGenContext, literal: ast.Literal) !void {
    switch (literal) {
        .string => |s| {
            try ctx.write("\"");
            try ctx.write(s);
            try ctx.write("\"");
        },
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{i});
            try ctx.write(str);
        },
        .float => |f| {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{f});
            try ctx.write(str);
        },
        .boolean => |b| try ctx.write(if (b) "true" else "false"),
        .null => try ctx.write("null"),
    }
}

fn comparisonOpToString(op: ast.ComparisonOperator) []const u8 {
    return switch (op) {
        .eq => "==",
        .neq => "!=",
        .lt => "<",
        .lte => "<=",
        .gt => ">",
        .gte => ">=",
    };
}

fn binaryOpToString(op: ast.BinaryOperator) []const u8 {
    return switch (op) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .and_op => "and",
        .or_op => "or",
    };
}

// ============================================================================
// TESTS
// ============================================================================

test "Codegen: simple MATCH" {
    const allocator = std.testing.allocator;
    const gql = "MATCH (n:Identity) RETURN n";
    
    var lex = @import("lexer.zig").Lexer.init(gql, allocator);
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);
    
    var parser = @import("parser.zig").Parser.init(tokens, allocator);
    var query = try parser.parse();
    defer query.deinit();
    
    const code = try generate(allocator, query);
    defer allocator.free(code);
    
    // Check that generated code contains expected patterns
    const code_str = code;
    try std.testing.expect(std.mem.indexOf(u8, code_str, "execute") != null);
    try std.testing.expect(std.mem.indexOf(u8, code_str, "HybridGraph") != null);
}
