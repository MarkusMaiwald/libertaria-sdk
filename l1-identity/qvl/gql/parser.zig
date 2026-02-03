//! GQL Parser (Recursive Descent)
//! 
//! Parses GQL tokens into AST according to ISO/IEC 39075:2024.
//! Entry point: Parser.parse() -> Query AST

const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(tokens: []const Token, allocator: std.mem.Allocator) Self {
        return Self{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }
    
    /// Parse complete query
    pub fn parse(self: *Self) !ast.Query {
        var statements = std.ArrayList(ast.Statement).init(self.allocator);
        errdefer {
            for (statements.items) |*s| s.deinit();
            statements.deinit();
        }
        
        while (!self.isAtEnd()) {
            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }
        
        return ast.Query{
            .allocator = self.allocator,
            .statements = try statements.toOwnedSlice(),
        };
    }
    
    // =========================================================================
    // Statement parsing
    // =========================================================================
    
    fn parseStatement(self: *Self) !ast.Statement {
        if (self.match(.match)) {
            return ast.Statement{ .match = try self.parseMatchStatement() };
        }
        if (self.match(.create)) {
            return ast.Statement{ .create = try self.parseCreateStatement() };
        }
        if (self.match(.return_keyword)) {
            return ast.Statement{ .return_stmt = try self.parseReturnStatement() };
        }
        if (self.match(.delete)) {
            return ast.Statement{ .delete = try self.parseDeleteStatement() };
        }
        
        return error.UnexpectedToken;
    }
    
    fn parseMatchStatement(self: *Self) !ast.MatchStatement {
        const pattern = try self.parseGraphPattern();
        errdefer pattern.deinit();
        
        var where: ?ast.Expression = null;
        if (self.match(.where)) {
            where = try self.parseExpression();
        }
        
        return ast.MatchStatement{
            .allocator = self.allocator,
            .pattern = pattern,
            .where = where,
        };
    }
    
    fn parseCreateStatement(self: *Self) !ast.CreateStatement {
        const pattern = try self.parseGraphPattern();
        
        return ast.CreateStatement{
            .allocator = self.allocator,
            .pattern = pattern,
        };
    }
    
    fn parseDeleteStatement(self: *Self) !ast.DeleteStatement {
        // Simple: DELETE identifier [, identifier]*
        var targets = std.ArrayList(ast.Identifier).init(self.allocator);
        errdefer {
            for (targets.items) |*t| t.deinit();
            targets.deinit();
        }
        
        while (true) {
            const ident = try self.parseIdentifier();
            try targets.append(ident);
            
            if (!self.match(.comma)) break;
        }
        
        return ast.DeleteStatement{
            .allocator = self.allocator,
            .targets = try targets.toOwnedSlice(),
        };
    }
    
    fn parseReturnStatement(self: *Self) !ast.ReturnStatement {
        var items = std.ArrayList(ast.ReturnItem).init(self.allocator);
        errdefer {
            for (items.items) |*i| i.deinit();
            items.deinit();
        }
        
        while (true) {
            const expr = try self.parseExpression();
            
            var alias: ?ast.Identifier = null;
            if (self.match(.as_keyword)) {
                alias = try self.parseIdentifier();
            }
            
            try items.append(ast.ReturnItem{
                .expression = expr,
                .alias = alias,
            });
            
            if (!self.match(.comma)) break;
        }
        
        return ast.ReturnStatement{
            .allocator = self.allocator,
            .items = try items.toOwnedSlice(),
        };
    }
    
    // =========================================================================
    // Pattern parsing
    // =========================================================================
    
    fn parseGraphPattern(self: *Self) !ast.GraphPattern {
        var paths = std.ArrayList(ast.PathPattern).init(self.allocator);
        errdefer {
            for (paths.items) |*p| p.deinit();
            paths.deinit();
        }
        
        while (true) {
            const path = try self.parsePathPattern();
            try paths.append(path);
            
            if (!self.match(.comma)) break;
        }
        
        return ast.GraphPattern{
            .allocator = self.allocator,
            .paths = try paths.toOwnedSlice(),
        };
    }
    
    fn parsePathPattern(self: *Self) !ast.PathPattern {
        var elements = std.ArrayList(ast.PathElement).init(self.allocator);
        errdefer {
            for (elements.items) |*e| e.deinit();
            elements.deinit();
        }
        
        // Must start with a node
        const node = try self.parseNodePattern();
        try elements.append(ast.PathElement{ .node = node });
        
        // Optional: edge - node - edge - node ...
        while (self.check(.minus) or self.check(.arrow_left)) {
            const edge = try self.parseEdgePattern();
            try elements.append(ast.PathElement{ .edge = edge });
            
            const next_node = try self.parseNodePattern();
            try elements.append(ast.PathElement{ .node = next_node });
        }
        
        return ast.PathPattern{
            .allocator = self.allocator,
            .elements = try elements.toOwnedSlice(),
        };
    }
    
    fn parseNodePattern(self: *Self) !ast.NodePattern {
        try self.consume(.left_paren, "Expected '('");
        
        // Optional variable: (n) or (:Label)
        var variable: ?ast.Identifier = null;
        if (self.check(.identifier)) {
            variable = try self.parseIdentifier();
        }
        
        // Optional labels: (:Label1:Label2)
        var labels = std.ArrayList(ast.Identifier).init(self.allocator);
        errdefer {
            for (labels.items) |*l| l.deinit();
            labels.deinit();
        }
        
        while (self.match(.colon)) {
            const label = try self.parseIdentifier();
            try labels.append(label);
        }
        
        // Optional properties: ({key: value})
        var properties: ?ast.PropertyMap = null;
        if (self.check(.left_brace)) {
            properties = try self.parsePropertyMap();
        }
        
        try self.consume(.right_paren, "Expected ')'");
        
        return ast.NodePattern{
            .allocator = self.allocator,
            .variable = variable,
            .labels = try labels.toOwnedSlice(),
            .properties = properties,
        };
    }
    
    fn parseEdgePattern(self: *Self) !ast.EdgePattern {
        var direction: ast.EdgeDirection = .outgoing;
        
        // Check for incoming: <-
        if (self.match(.arrow_left)) {
            direction = .incoming;
        } else if (self.match(.minus)) {
            direction = .outgoing;
        }
        
        // Edge details in brackets: -[r:TYPE]-
        var variable: ?ast.Identifier = null;
        var types = std.ArrayList(ast.Identifier).init(self.allocator);
        errdefer {
            for (types.items) |*t| t.deinit();
            types.deinit();
        }
        var properties: ?ast.PropertyMap = null;
        var quantifier: ?ast.Quantifier = null;
        
        if (self.match(.left_bracket)) {
            // Variable: [r]
            if (self.check(.identifier)) {
                variable = try self.parseIdentifier();
            }
            
            // Type: [:TRUST]
            while (self.match(.colon)) {
                const edge_type = try self.parseIdentifier();
                try types.append(edge_type);
            }
            
            // Properties: [{level: 3}]
            if (self.check(.left_brace)) {
                properties = try self.parsePropertyMap();
            }
            
            // Quantifier: [*1..3]
            if (self.match(.star)) {
                quantifier = try self.parseQuantifier();
            }
            
            try self.consume(.right_bracket, "Expected ']'");
        }
        
        // Arrow end
        if (direction == .outgoing) {
            try self.consume(.arrow_right, "Expected '->'");
        } else {
            // Incoming already consumed <-, now just need -
            try self.consume(.minus, "Expected '-'");
        }
        
        return ast.EdgePattern{
            .allocator = self.allocator,
            .direction = direction,
            .variable = variable,
            .types = try types.toOwnedSlice(),
            .properties = properties,
            .quantifier = quantifier,
        };
    }
    
    fn parseQuantifier(self: *Self) !ast.Quantifier {
        var min: ?u32 = null;
        var max: ?u32 = null;
        
        if (self.check(.integer_literal)) {
            min = try self.parseInteger();
        }
        
        if (self.match(.dot) and self.match(.dot)) {
            if (self.check(.integer_literal)) {
                max = try self.parseInteger();
            }
        }
        
        return ast.Quantifier{
            .min = min,
            .max = max,
        };
    }
    
    fn parsePropertyMap(self: *Self) !ast.PropertyMap {
        try self.consume(.left_brace, "Expected '{'");
        
        var entries = std.ArrayList(ast.PropertyEntry).init(self.allocator);
        errdefer {
            for (entries.items) |*e| e.deinit();
            entries.deinit();
        }
        
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            const key = try self.parseIdentifier();
            try self.consume(.colon, "Expected ':'");
            const value = try self.parseExpression();
            
            try entries.append(ast.PropertyEntry{
                .key = key,
                .value = value,
            });
            
            if (!self.match(.comma)) break;
        }
        
        try self.consume(.right_brace, "Expected '}'");
        
        return ast.PropertyMap{
            .allocator = self.allocator,
            .entries = try entries.toOwnedSlice(),
        };
    }
    
    // =========================================================================
    // Expression parsing
    // =========================================================================
    
    fn parseExpression(self: *Self) !ast.Expression {
        return try self.parseOrExpression();
    }
    
    fn parseOrExpression(self: *Self) !ast.Expression {
        var left = try self.parseAndExpression();
        
        while (self.match(.or_keyword)) {
            const right = try self.parseAndExpression();
            
            // Create binary op
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = left;
            
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            
            left = ast.Expression{
                .binary_op = ast.BinaryOp{
                    .left = left_ptr,
                    .op = .or_op,
                    .right = right_ptr,
                },
            };
        }
        
        return left;
    }
    
    fn parseAndExpression(self: *Self) !ast.Expression {
        var left = try self.parseComparison();
        
        while (self.match(.and_keyword)) {
            const right = try self.parseComparison();
            
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = left;
            
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            
            left = ast.Expression{
                .binary_op = ast.BinaryOp{
                    .left = left_ptr,
                    .op = .and_op,
                    .right = right_ptr,
                },
            };
        }
        
        return left;
    }
    
    fn parseComparison(self: *Self) !ast.Expression {
        var left = try self.parseAdditive();
        
        const op: ?ast.ComparisonOperator = blk: {
            if (self.match(.eq)) break :blk .eq;
            if (self.match(.neq)) break :blk .neq;
            if (self.match(.lt)) break :blk .lt;
            if (self.match(.lte)) break :blk .lte;
            if (self.match(.gt)) break :blk .gt;
            if (self.match(.gte)) break :blk .gte;
            break :blk null;
        };
        
        if (op) |comparison_op| {
            const right = try self.parseAdditive();
            
            const left_ptr = try self.allocator.create(ast.Expression);
            left_ptr.* = left;
            
            const right_ptr = try self.allocator.create(ast.Expression);
            right_ptr.* = right;
            
            return ast.Expression{
                .comparison = ast.Comparison{
                    .left = left_ptr,
                    .op = comparison_op,
                    .right = right_ptr,
                },
            };
        }
        
        return left;
    }
    
    fn parseAdditive(self: *Self) !ast.Expression {
        _ = self;
        // Simplified: just return primary for now
        return try self.parsePrimary();
    }
    
    fn parsePrimary(self: *Self) !ast.Expression {
        if (self.match(.null_keyword)) {
            return ast.Expression{ .literal = ast.Literal{ .null = {} } };
        }
        if (self.match(.true_keyword)) {
            return ast.Expression{ .literal = ast.Literal{ .boolean = true } };
        }
        if (self.match(.false_keyword)) {
            return ast.Expression{ .literal = ast.Literal{ .boolean = false } };
        }
        if (self.match(.string_literal)) {
            return ast.Expression{ .literal = ast.Literal{ .string = self.previous().text } };
        }
        if (self.check(.integer_literal)) {
            const val = try self.parseInteger();
            return ast.Expression{ .literal = ast.Literal{ .integer = @intCast(val) } };
        }
        
        // Property access or identifier
        if (self.check(.identifier)) {
            const ident = try self.parseIdentifier();
            
            if (self.match(.dot)) {
                const property = try self.parseIdentifier();
                return ast.Expression{
                    .property_access = ast.PropertyAccess{
                        .object = ident,
                        .property = property,
                    },
                };
            }
            
            return ast.Expression{ .identifier = ident };
        }
        
        return error.UnexpectedToken;
    }
    
    // =========================================================================
    // Helpers
    // =========================================================================
    
    fn parseIdentifier(self: *Self) !ast.Identifier {
        const tok = try self.consume(.identifier, "Expected identifier");
        return ast.Identifier{ .name = tok.text };
    }
    
    fn parseInteger(self: *Self) !u32 {
        const tok = try self.consume(.integer_literal, "Expected integer");
        return try std.fmt.parseInt(u32, tok.text, 10);
    }
    
    fn match(self: *Self, tok_type: TokenType) bool {
        if (self.check(tok_type)) {
            self.advance();
            return true;
        }
        return false;
    }
    
    fn check(self: *Self, tok_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == tok_type;
    }
    
    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) self.pos += 1;
        return self.previous();
    }
    
    fn isAtEnd(self: *Self) bool {
        return self.peek().type == .eof;
    }
    
    fn peek(self: *Self) Token {
        return self.tokens[self.pos];
    }
    
    fn previous(self: *Self) Token {
        return self.tokens[self.pos - 1];
    }
    
    fn consume(self: *Self, tok_type: TokenType, message: []const u8) !Token {
        if (self.check(tok_type)) return self.advance();
        std.log.err("{s}, got {s}", .{ message, @tagName(self.peek().type) });
        return error.UnexpectedToken;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "Parser: simple MATCH" {
    const allocator = std.testing.allocator;
    const source = "MATCH (n:Identity) RETURN n";
    
    var lex = lexer.Lexer.init(source, allocator);
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);
    
    var parser = Parser.init(tokens, allocator);
    const query = try parser.parse();
    defer query.deinit();
    
    try std.testing.expectEqual(2, query.statements.len);
    try std.testing.expect(query.statements[0] == .match);
    try std.testing.expect(query.statements[1] == .return_stmt);
}

test "Parser: path pattern" {
    const allocator = std.testing.allocator;
    const source = "MATCH (a)-[t:TRUST]->(b) RETURN a, b";
    
    var lex = lexer.Lexer.init(source, allocator);
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);
    
    var parser = Parser.init(tokens, allocator);
    const query = try parser.parse();
    defer query.deinit();
    
    try std.testing.expectEqual(1, query.statements[0].match.pattern.paths.len);
}
