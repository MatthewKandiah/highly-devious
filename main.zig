const std = @import("std");

const DEBUG = true;

fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG) {
        std.debug.print(fmt, args);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const stdIn = std.io.getStdIn().reader();
    const stdOut = std.io.getStdOut().writer();
    try runRepl(allocator, stdIn.any(), stdOut.any());
    stdOut.print("Exiting gracefully\n", .{}) catch {};
}

fn runRepl(
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
) !void {
    var tokeniser = Tokeniser.init(allocator);
    defer tokeniser.deinit();

    var buf: [1024]u8 = undefined;
    while (true) {
        const line = try reader.readUntilDelimiterOrEof(&buf, '\n') orelse continue;
        if (std.mem.eql(u8, line, "#exit")) {
            break;
        }
        try writer.print("----------------------\n", .{});
        try tokeniser.tokenise(line);
        tokeniser.debug();
        // TODO - evaluate s-expression
        if (tokeniser.open_paren_count == tokeniser.close_paren_count) {
            try writer.print("ready to evaluate s-expressions\n", .{});
        } else {
            try writer.print("waiting for more input before evaluating\n", .{});
        }
    }
}

const TokenList = std.DoublyLinkedList(Token);

const Tokeniser = struct {
    allocator: std.mem.Allocator,
    tokens: TokenList,
    open_paren_count: u32,
    close_paren_count: u32,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tokens = .{},
            .open_paren_count = 0,
            .close_paren_count = 0,
        };
    }

    fn deinit(self: Self) void {
        var next = self.tokens.first;
        while (next) |node| {
            next = node.next;
            self.allocator.destroy(node);
        }
    }

    fn debug(self: Self) void {
        debugPrint("Token count: {}\n", .{self.tokens.len});
        debugPrint("Open paren count: {}\n", .{self.open_paren_count});
        debugPrint("Close paren count: {}\n", .{self.close_paren_count});
        debugPrint("Tokens: \n", .{});
        var maybe_next_token = self.tokens.first;
        while (maybe_next_token != null) {
            if (maybe_next_token) |next_token| {
                switch (next_token.data.type) {
                    .character => debugPrint(
                        "\ttype: Character, value: {c}\n",
                        .{@as(u8, @intCast(next_token.data.data.character))},
                    ),
                    .symbol => debugPrint(
                        "\ttype: Symbol, value: {s}\n",
                        .{next_token.data.data.symbol},
                    ),
                    .number => debugPrint(
                        "\ttype: Number, value: {d}\n",
                        .{next_token.data.data.number},
                    ),
                    .string => debugPrint(
                        "\ttype: String, value: {s}\n",
                        .{next_token.data.data.string},
                    ),
                }
                maybe_next_token = next_token.next;
            }
        }
    }

    fn tokenise(self: *Self, chars: []const u8) !void {
        var idx: usize = 0;
        while (idx < chars.len) {
            const next_token_result = try self.getNextToken(chars[idx..]);
            if (next_token_result.token) |token| {
                try self.append(token);
            }
            const consumed_chars = next_token_result.consumed_chars;
            idx += consumed_chars;
        }
    }

    fn isValidSingleCharToken(char: u8) bool {
        return switch (char) {
            '(' => true,
            ')' => true,
            '+' => true,
            '-' => true,
            '*' => true,
            '/' => true,
            else => false,
        };
    }

    fn getNextToken(self: *Self, chars: []const u8) !struct { token: ?Token, consumed_chars: usize } {
        var consumed_chars: usize = 0;
        while (consumed_chars < chars.len) {
            if (std.ascii.isWhitespace(chars[consumed_chars])) {
                consumed_chars += 1;
                continue;
            }

            if (isValidSingleCharToken(chars[consumed_chars])) {
                // TODO - not sure this condition needs to be this complex
                if (chars[consumed_chars] == '(' or chars[consumed_chars] == ')' or consumed_chars == chars.len - 1 or (consumed_chars + 1 < chars.len and std.ascii.isWhitespace(chars[consumed_chars + 1]))) {
                    const token = Token{ .type = .character, .data = .{ .character = chars[consumed_chars] } };
                    if (chars[consumed_chars] == '(') {
                        self.open_paren_count += 1;
                    } else if (chars[consumed_chars] == ')') {
                        self.close_paren_count += 1;
                    }
                    consumed_chars += 1;
                    return .{ .token = token, .consumed_chars = consumed_chars };
                }
            }

            if (chars[consumed_chars] == '"') {
                const string_start = consumed_chars;
                consumed_chars += 1;
                while (consumed_chars < chars.len and chars[consumed_chars] != '"') {
                    if (chars[consumed_chars] != '"' and consumed_chars == chars.len - 1) {
                        return error.IncompleteString;
                    }
                    consumed_chars += 1;
                }
                consumed_chars += 1;
                if (consumed_chars - string_start < 2) std.debug.panic("Should never happen: {}, {}\n", .{ consumed_chars, string_start });
                const string_character_count = consumed_chars - string_start + 2; // total number of characters consumed after finding first quote, excluding the quotation mark characters
                const string_slice = try self.allocator.alloc(u8, string_character_count);
                std.mem.copyForwards(u8, string_slice, chars[string_start + 1 .. consumed_chars - 1]);
                const token = Token{ .type = .string, .data = .{ .string = string_slice } };
                return .{ .token = token, .consumed_chars = consumed_chars };
            }

            if (std.ascii.isDigit(chars[consumed_chars])) {
                const number_start = consumed_chars;
                consumed_chars += 1;
                var point_found = false;
                while (consumed_chars < chars.len and !std.ascii.isWhitespace(chars[consumed_chars]) and (std.ascii.isDigit(chars[consumed_chars]) or chars[consumed_chars] == '.')) {
                    if (chars[consumed_chars] == '.') {
                        if (point_found) {
                            return error.TooManyPointsInNumber;
                        } else {
                            point_found = true;
                        }
                    }
                    consumed_chars += 1;
                }
                const number = try std.fmt.parseFloat(f64, chars[number_start..consumed_chars]);
                const token = Token{ .type = .number, .data = .{ .number = number } };
                return .{ .token = token, .consumed_chars = consumed_chars };
            }

            if (std.ascii.isAlphanumeric(chars[consumed_chars])) {
                const symbol_start = consumed_chars;
                consumed_chars += 1;
                while (consumed_chars < chars.len and !std.ascii.isWhitespace(chars[consumed_chars])) {
                    consumed_chars += 1;
                }
                const symbol_character_count = consumed_chars - symbol_start;
                const symbol_slice = try self.allocator.alloc(u8, symbol_character_count);
                std.mem.copyForwards(u8, symbol_slice, chars[symbol_start..consumed_chars]);
                const token = Token{ .type = .symbol, .data = .{ .symbol = symbol_slice } };
                return .{ .token = token, .consumed_chars = consumed_chars };
            }
        }
        return .{ .token = null, .consumed_chars = consumed_chars };
    }

    fn append(self: *Self, token: Token) !void {
        const new_node_ptr = try self.allocator.create(TokenList.Node);
        const new_node = TokenList.Node{ .data = token };
        new_node_ptr.* = new_node;
        self.tokens.append(new_node_ptr);
    }

    fn popFirst(self: *Self) ?Token {
        const first_ptr = self.tokens.popFirst() orelse return null;
        const value = first_ptr.*.data;
        self.allocator.destroy(first_ptr);
        return value;
    }

    fn popLast(self: *Self) ?Token {
        const last_ptr = self.tokens.pop() orelse return null;
        const value = last_ptr.*.data;
        self.allocator.destroy(last_ptr);
        return value;
    }
};

const TokenType = enum {
    character, // ( ) + - * /
    symbol, // user defined symbols
    number,
    string, // string surrounded by "" marks
};

// TODO - free string and symbol data
const Token = struct { type: TokenType, data: union(TokenType) {
    character: usize,
    symbol: []const u8,
    number: f64,
    string: []const u8,
} };
