//! GQL (Graph Query Language) Parser
//! 
//! ISO/IEC 39075:2024 compliant parser for Libertaria QVL.
//! Transpiles GQL queries to Zig programmatic API calls.

const std = @import("std");

// ============================================================================
// AST TYPES
// ============================================================================

/// Root node of a GQL query
pub const Query = struct {
    allocator: std.mem.Allocator,
    statements: []Statement,
    
    pub fn deinit(self: *Query) void {
        for (self.statements) |*stmt| {
            stmt.deinit();
        }
        self.allocator.free(self.statements);
    }
};

/// Statement types (GQL is statement-based)
pub const Statement = union(enum) {
    match: MatchStatement,
    create: CreateStatement,
    delete: DeleteStatement,
    return_stmt: ReturnStatement,
    
    pub fn deinit(self: *Statement) void {
        switch (self.*) {
            inline else => |*s| s.deinit(),
        }
    }
};

/// MATCH statement: pattern matching for graph traversal
pub const MatchStatement = struct {
    allocator: std.mem.Allocator,
    pattern: GraphPattern,
    where: ?Expression,
    
    pub fn deinit(self: *MatchStatement) void {
        self.pattern.deinit();
        if (self.where) |*w| w.deinit();
    }
};

/// CREATE statement: insert nodes/edges
pub const CreateStatement = struct {
    allocator: std.mem.Allocator,
    pattern: GraphPattern,
    
    pub fn deinit(self: *CreateStatement) void {
        self.pattern.deinit();
    }
};

/// DELETE statement: remove nodes/edges
pub const DeleteStatement = struct {
    allocator: std.mem.Allocator,
    targets: []Identifier,
    
    pub fn deinit(self: *DeleteStatement) void {
        for (self.targets) |*t| t.deinit();
        self.allocator.free(self.targets);
    }
};

/// RETURN statement: projection of results
pub const ReturnStatement = struct {
    allocator: std.mem.Allocator,
    items: []ReturnItem,
    
    pub fn deinit(self: *ReturnStatement) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
    }
};

/// Graph pattern: sequence of path patterns
pub const GraphPattern = struct {
    allocator: std.mem.Allocator,
    paths: []PathPattern,
    
    pub fn deinit(self: *GraphPattern) void {
        for (self.paths) |*p| p.deinit();
        self.allocator.free(self.paths);
    }
};

/// Path pattern: node -edge-> node -edge-> ...
pub const PathPattern = struct {
    allocator: std.mem.Allocator,
    elements: []PathElement, // Alternating Node and Edge
    
    pub fn deinit(self: *PathPattern) void {
        for (self.elements) |*e| e.deinit();
        self.allocator.free(self.elements);
    }
};

/// Element in a path (node or edge)
pub const PathElement = union(enum) {
    node: NodePattern,
    edge: EdgePattern,
    
    pub fn deinit(self: *PathElement) void {
        switch (self.*) {
            inline else => |*e| e.deinit(),
        }
    }
};

/// Node pattern: (n:Label {props})
pub const NodePattern = struct {
    allocator: std.mem.Allocator,
    variable: ?Identifier,
    labels: []Identifier,
    properties: ?PropertyMap,
    
    pub fn deinit(self: *NodePattern) void {
        if (self.variable) |*v| v.deinit();
        for (self.labels) |*l| l.deinit();
        self.allocator.free(self.labels);
        if (self.properties) |*p| p.deinit();
    }
};

/// Edge pattern: -[r:TYPE {props}]-> or <-[...]-
pub const EdgePattern = struct {
    allocator: std.mem.Allocator,
    direction: EdgeDirection,
    variable: ?Identifier,
    types: []Identifier,
    properties: ?PropertyMap,
    quantifier: ?Quantifier, // *1..3 for variable length
    
    pub fn deinit(self: *EdgePattern) void {
        if (self.variable) |*v| v.deinit();
        for (self.types) |*t| t.deinit();
        self.allocator.free(self.types);
        if (self.properties) |*p| p.deinit();
        if (self.quantifier) |*q| q.deinit();
    }
};

pub const EdgeDirection = enum {
    outgoing,   // -
    incoming,   // <-
    any,        // -
};

/// Quantifier for variable-length paths: *min..max
pub const Quantifier = struct {
    min: ?u32,
    max: ?u32, // null = unlimited
    
    pub fn deinit(self: *Quantifier) void {
        _ = self;
    }
};

/// Property map: {key: value, ...}
pub const PropertyMap = struct {
    allocator: std.mem.Allocator,
    entries: []PropertyEntry,
    
    pub fn deinit(self: *PropertyMap) void {
        for (self.entries) |*e| e.deinit();
        self.allocator.free(self.entries);
    }
};

pub const PropertyEntry = struct {
    key: Identifier,
    value: Expression,
    
    pub fn deinit(self: *PropertyEntry) void {
        self.key.deinit();
        self.value.deinit();
    }
};

/// Return item: expression [AS alias]
pub const ReturnItem = struct {
    expression: Expression,
    alias: ?Identifier,
    
    pub fn deinit(self: *ReturnItem) void {
        self.expression.deinit();
        if (self.alias) |*a| a.deinit();
    }
};

// ============================================================================
// EXPRESSIONS
// ============================================================================

pub const Expression = union(enum) {
    literal: Literal,
    identifier: Identifier,
    property_access: PropertyAccess,
    binary_op: BinaryOp,
    comparison: Comparison,
    function_call: FunctionCall,
    list: ListExpression,
    
    pub fn deinit(self: *Expression) void {
        switch (self.*) {
            inline else => |*e| e.deinit(),
        }
    }
};

pub const Literal = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    null: void,
    
    pub fn deinit(self: *Literal) void {
        switch (self.*) {
            .string => |s| std.heap.raw_free(s),
            else => {},
        }
    }
};

/// Identifier (variable, label, property name)
pub const Identifier = struct {
    name: []const u8,
    
    pub fn deinit(self: *Identifier) void {
        std.heap.raw_free(self.name);
    }
};

/// Property access: node.property or edge.property
pub const PropertyAccess = struct {
    object: Identifier,
    property: Identifier,
    
    pub fn deinit(self: *PropertyAccess) void {
        self.object.deinit();
        self.property.deinit();
    }
};

/// Binary operation: a + b, a - b, etc.
pub const BinaryOp = struct {
    left: *Expression,
    op: BinaryOperator,
    right: *Expression,
    
    pub fn deinit(self: *BinaryOp) void {
        self.left.deinit();
        std.heap.raw_free(self.left);
        self.right.deinit();
        std.heap.raw_free(self.right);
    }
};

pub const BinaryOperator = enum {
    add, sub, mul, div, mod,
    and_op, or_op,
};

/// Comparison: a = b, a < b, etc.
pub const Comparison = struct {
    left: *Expression,
    op: ComparisonOperator,
    right: *Expression,
    
    pub fn deinit(self: *Comparison) void {
        self.left.deinit();
        std.heap.raw_free(self.left);
        self.right.deinit();
        std.heap.raw_free(self.right);
    }
};

pub const ComparisonOperator = enum {
    eq,   // =
    neq,  // <>
    lt,   // <
    lte,  // <=
    gt,   // >
    gte,  // >=
};

/// Function call: function(arg1, arg2, ...)
pub const FunctionCall = struct {
    allocator: std.mem.Allocator,
    name: Identifier,
    args: []Expression,
    
    pub fn deinit(self: *FunctionCall) void {
        self.name.deinit();
        for (self.args) |*a| a.deinit();
        self.allocator.free(self.args);
    }
};

/// List literal: [1, 2, 3]
pub const ListExpression = struct {
    allocator: std.mem.Allocator,
    elements: []Expression,
    
    pub fn deinit(self: *ListExpression) void {
        for (self.elements) |*e| e.deinit();
        self.allocator.free(self.elements);
    }
};
