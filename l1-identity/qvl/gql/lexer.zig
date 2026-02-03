//! GQL Lexer/Tokenizer
//! 
//! Converts GQL query string into tokens for parser.
//! ISO/IEC 39075:2024 lexical structure.

const std = @import("std");

pub const TokenType = enum {
    // Keywords
    match,
    create,
    delete,
    return_keyword,
    where,
    as_keyword,
    and_keyword,
    or_keyword,
    not_keyword,
    null_keyword,
    true_keyword,
    false_keyword,
    
    // Punctuation
    left_paren,      // (
    right_paren,     // )
    left_bracket,    // [
    right_bracket,   // ]
    left_brace,      // {
    right_brace,     // }
    colon,           // :
    comma,           // ,
    dot,             // .
    minus,           // -
    arrow_right,     // ->
    arrow_left,      // <-
    star,            // *
    slash,           // /
    percent,         // %
    plus,            // +
    
    // Comparison operators
    eq,              // =
    neq,             // <>
    lt,              // <
    lte,             // <=
    gt,              // >
    gte,             // >=
    
    // Literals
    identifier,
    string_literal,
    integer_literal,
    float_literal,
    
    // Special
    eof,
    invalid,
};

pub const Token = struct {
    type: TokenType,
    text: []const u8, // Slice into original source
    line: u32,
    column: u32,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    column: u32,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(source: []const u8, allocator: std.mem.Allocator) Self {
        return Self{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
        };
    }
    
    /// Get next token
    pub fn nextToken(self: *Self) !Token {
        self.skipWhitespace();
        
        if (self.pos >= self.source.len) {
            return self.makeToken(.eof, 0);
        }
        
        const c = self.source[self.pos];
        
        // Identifiers and keywords
        if (isAlpha(c) or c == '_') {
            return self.readIdentifier();
        }
        
        // Numbers
        if (isDigit(c)) {
            return self.readNumber();
        }
        
        // Strings
        if (c == '"' or c == '\'') {
            return self.readString();
        }
        
        // Single-char tokens and operators
        switch (c) {
            '(' => { self.advance(); return self.makeToken(.left_paren, 1); },
            ')' => { self.advance(); return self.makeToken(.right_paren, 1); },
            '[' => { self.advance(); return self.makeToken(.left_bracket, 1); },
            ']' => { self.advance(); return self.makeToken(.right_bracket, 1); },
            '{' => { self.advance(); return self.makeToken(.left_brace, 1); },
            '}' => { self.advance(); return self.makeToken(.right_brace, 1); },
            ':' => { self.advance(); return self.makeToken(.colon, 1); },
            ',' => { self.advance(); return self.makeToken(.comma, 1); },
            '.' => { self.advance(); return self.makeToken(.dot, 1); },
            '+' => { self.advance(); return self.makeToken(.plus, 1); },
            '%' => { self.advance(); return self.makeToken(.percent, 1); },
            '*' => { self.advance(); return self.makeToken(.star, 1); },
            
            '-' => {
                self.advance();
                if (self.peek() == '>') {
                    self.advance();
                    return self.makeToken(.arrow_right, 2);
                }
                return self.makeToken(.minus, 1);
            },
            
            '<' => {
                self.advance();
                if (self.peek() == '-') {
                    self.advance();
                    return self.makeToken(.arrow_left, 2);
                } else if (self.peek() == '>') {
                    self.advance();
                    return self.makeToken(.neq, 2);
                } else if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(.lte, 2);
                }
                return self.makeToken(.lt, 1);
            },
            
            '>' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeToken(.gte, 2);
                }
                return self.makeToken(.gt, 1);
            },
            
            '=' => { self.advance(); return self.makeToken(.eq, 1); },
            
            else => {
                self.advance();
                return self.makeToken(.invalid, 1);
            },
        }
    }
    
    /// Read all tokens into array
    pub fn tokenize(self: *Self) ![]Token {
        var tokens: std.ArrayList(Token) = .{};
        errdefer tokens.deinit(self.allocator);
        
        while (true) {
            const tok = try self.nextToken();
            try tokens.append(self.allocator, tok);
            if (tok.type == .eof) break;
        }
        
        return tokens.toOwnedSlice(self.allocator);
    }
    
    // =========================================================================
    // Internal helpers
    // =========================================================================
    
    fn advance(self: *Self) void {
        if (self.pos >= self.source.len) return;
        
        if (self.source[self.pos] == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        self.pos += 1;
    }
    
    fn peek(self: *Self) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }
    
    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.advance();
            } else if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                // Single-line comment
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
            } else if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                // Multi-line comment
                self.advance(); // /
                self.advance(); // *
                while (self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                        self.advance(); // *
                        self.advance(); // /
                        break;
                    }
                    self.advance();
                }
            } else {
                break;
            }
        }
    }
    
    fn readIdentifier(self: *Self) Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;
        
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (isAlphaNum(c) or c == '_') {
                self.advance();
            } else {
                break;
            }
        }
        
        const text = self.source[start..self.pos];
        const tok_type = keywordFromString(text);
        
        return Token{
            .type = tok_type,
            .text = text,
            .line = start_line,
            .column = start_col,
        };
    }
    
    fn readNumber(self: *Self) !Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;
        var is_float = false;
        
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (isDigit(c)) {
                self.advance();
            } else if (c == '.' and !is_float) {
                // Check for range operator (e.g., 1..3)
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '.') {
                    break; // Stop before range operator
                }
                is_float = true;
                self.advance();
            } else {
                break;
            }
        }
        
        const text = self.source[start..self.pos];
        const tok_type: TokenType = if (is_float) .float_literal else .integer_literal;
        
        return Token{
            .type = tok_type,
            .text = text,
            .line = start_line,
            .column = start_col,
        };
    }
    
    fn readString(self: *Self) !Token {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;
        const quote = self.source[self.pos];
        self.advance(); // opening quote
        
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == quote) {
                self.advance(); // closing quote
                break;
            } else if (c == '\\' and self.pos + 1 < self.source.len) {
                self.advance(); // backslash
                self.advance(); // escaped char
            } else {
                self.advance();
            }
        }
        
        const text = self.source[start..self.pos];
        return Token{
            .type = .string_literal,
            .text = text,
            .line = start_line,
            .column = start_col,
        };
    }
    
    fn makeToken(self: *Self, tok_type: TokenType, len: usize) Token {
        const tok = Token{
            .type = tok_type,
            .text = self.source[self.pos - len .. self.pos],
            .line = self.line,
            .column = self.column - @as(u32, @intCast(len)),
        };
        return tok;
    }
};

// ============================================================================
// Helper functions
// ============================================================================

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

fn keywordFromString(text: []const u8) TokenType {
    // Zig 0.15.2 compatible: use switch instead of ComptimeStringMap
    if (std.mem.eql(u8, text, "MATCH") or std.mem.eql(u8, text, "match")) return .match;
    if (std.mem.eql(u8, text, "CREATE") or std.mem.eql(u8, text, "create")) return .create;
    if (std.mem.eql(u8, text, "DELETE") or std.mem.eql(u8, text, "delete")) return .delete;
    if (std.mem.eql(u8, text, "RETURN") or std.mem.eql(u8, text, "return")) return .return_keyword;
    if (std.mem.eql(u8, text, "WHERE") or std.mem.eql(u8, text, "where")) return .where;
    if (std.mem.eql(u8, text, "AS") or std.mem.eql(u8, text, "as")) return .as_keyword;
    if (std.mem.eql(u8, text, "AND") or std.mem.eql(u8, text, "and")) return .and_keyword;
    if (std.mem.eql(u8, text, "OR") or std.mem.eql(u8, text, "or")) return .or_keyword;
    if (std.mem.eql(u8, text, "NOT") or std.mem.eql(u8, text, "not")) return .not_keyword;
    if (std.mem.eql(u8, text, "NULL") or std.mem.eql(u8, text, "null")) return .null_keyword;
    if (std.mem.eql(u8, text, "TRUE") or std.mem.eql(u8, text, "true")) return .true_keyword;
    if (std.mem.eql(u8, text, "FALSE") or std.mem.eql(u8, text, "false")) return .false_keyword;
    return .identifier;
}

// ============================================================================
// TESTS
// ============================================================================

test "Lexer: simple keywords" {
    const allocator = std.testing.allocator;
    const source = "MATCH (n) RETURN n";
    
    var lex = Lexer.init(source, allocator);
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);
    
    try std.testing.expectEqual(TokenType.match, tokens[0].type);
    try std.testing.expectEqual(TokenType.left_paren, tokens[1].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[2].type);
    try std.testing.expectEqual(TokenType.right_paren, tokens[3].type);
    try std.testing.expectEqual(TokenType.return_keyword, tokens[4].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[5].type);
    try std.testing.expectEqual(TokenType.eof, tokens[6].type);
}

test "Lexer: arrow operators" {
    const allocator = std.testing.allocator;
    const source = "-> <-";
    
    var lexer = Lexer.init(source, allocator);
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    try std.testing.expectEqual(TokenType.arrow_right, tokens[0].type);
    try std.testing.expectEqual(TokenType.arrow_left, tokens[1].type);
}

test "Lexer: string literal" {
    const allocator = std.testing.allocator;
    const source = "\"hello world\"";
    
    var lexer = Lexer.init(source, allocator);
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    try std.testing.expectEqual(TokenType.string_literal, tokens[0].type);
    try std.testing.expectEqualStrings("\"hello world\"", tokens[0].text);
}

test "Lexer: numbers" {
    const allocator = std.testing.allocator;
    const source = "42 3.14";
    
    var lexer = Lexer.init(source, allocator);
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    try std.testing.expectEqual(TokenType.integer_literal, tokens[0].type);
    try std.testing.expectEqual(TokenType.float_literal, tokens[1].type);
}
