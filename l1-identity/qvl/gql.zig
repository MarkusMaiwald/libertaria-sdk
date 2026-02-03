//! GQL (Graph Query Language) for Libertaria QVL
//! 
//! ISO/IEC 39075:2024 compliant implementation
//! Entry point: parse(query_string) -> AST

const std = @import("std");

pub const ast = @import("gql/ast.zig");
pub const lexer = @import("gql/lexer.zig");
pub const parser = @import("gql/parser.zig");
pub const codegen = @import("gql/codegen.zig");

/// Parse GQL query string into AST
pub fn parse(allocator: std.mem.Allocator, query: []const u8) !ast.Query {
    var lex = lexer.Lexer.init(query, allocator);
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);
    
    var par = parser.Parser.init(tokens, allocator);
    return try par.parse();
}

/// Transpile GQL to Zig code (programmatic API)
/// 
/// Example:
///   GQL: MATCH (n:Identity)-[t:TRUST]->(m) WHERE n.did = 'alice' RETURN m
///   Zig: try graph.findTrustPath(alice, trust_filter)
pub fn transpileToZig(allocator: std.mem.Allocator, query: ast.Query) ![]const u8 {
    // TODO: Implement code generation
    _ = allocator;
    _ = query;
    return "// TODO: Transpile GQL to Zig";
}

// Re-export commonly used types
pub const Query = ast.Query;
pub const Statement = ast.Statement;
pub const MatchStatement = ast.MatchStatement;
pub const CreateStatement = ast.CreateStatement;
pub const ReturnStatement = ast.ReturnStatement;
pub const GraphPattern = ast.GraphPattern;
pub const NodePattern = ast.NodePattern;
pub const EdgePattern = ast.EdgePattern;

// Re-export code generator
pub const generateZig = codegen.generate;
