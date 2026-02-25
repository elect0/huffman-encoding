const std = @import("std");
const huffman_uncoding = @import("huffman_encoding");

const Order = std.math.Order;

fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));

    return content;
}

const Node = struct {
    freq: u32,
    char: ?u8,
    left: ?*Node,
    right: ?*Node,

    fn init(allocator: std.mem.Allocator, freq: u32, char: ?u8, left: ?*Node, right: ?*Node) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{
            .freq = freq,
            .char = char,
            .left = left,
            .right = right,
        };

        return node;
    }
};

const BitWritter = struct {
    buffer: u8 = 0,
    bit_count: u8 = 0,
    out_file: std.fs.File,

    fn writeBit(self: *BitWritter, bit: u8) !void {
        const val: u8 = if (bit == '1') 1 else 0;

        self.buffer = (self.buffer << 1) | val;
        self.bit_count += 1;

        if (self.bit_count == 8) {
            try self.out_file.writeAll(&[_]u8{self.buffer});
            self.buffer = 0;
            self.bit_count = 0;
        }
    }

    fn flush(self: *BitWritter) !void {
        if (self.bit_count > 0) {
            const padding = 8 - self.bit_count;
            self.buffer <<= @intCast(padding);
            try self.out_file.writeAll(&[_]u8{self.buffer});
        }
    }
};

fn compareNodes(context: void, a: *Node, b: *Node) Order {
    _ = context;

    return std.math.order(a.freq, b.freq);
}

fn free_tree(allocator: std.mem.Allocator, node: *Node) !void {
    if (node.left) |left| {
        try free_tree(allocator, left);
    }

    if (node.right) |right| {
        try free_tree(allocator, right);
    }

    allocator.destroy(node);
}

fn generateCodes(node: *Node, path: *std.ArrayList(u8), dictionary: *std.AutoHashMap(u8, []const u8), allocator: std.mem.Allocator) !void {
    if (node.char) |c| {
        const code = try allocator.dupe(u8, path.items);

        try dictionary.put(c, code);
        return;
    }

    if (node.left) |left| {
        try path.append(allocator, '0');
        try generateCodes(left, path, dictionary, allocator);
        _ = path.pop();
    }

    if (node.right) |right| {
        try path.append(allocator, '1');
        try generateCodes(right, path, dictionary, allocator);
        _ = path.pop();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();

    var map: std.AutoHashMap(u8, u32) = .init(allocator);
    defer map.deinit();

    const content: []u8 = try read_file(allocator, "test.txt");
    defer allocator.free(content);

    for (content) |char| {
        const entry = try map.getOrPut(char);

        if (!entry.found_existing) {
            entry.value_ptr.* = 1;
        } else {
            entry.value_ptr.* += 1;
        }
    }

    var pq: std.PriorityQueue(*Node, void, compareNodes) = .init(allocator, {});
    defer pq.deinit();

    var it = map.iterator();

    while (it.next()) |entry| {
        const node: *Node = try .init(allocator, entry.value_ptr.*, entry.key_ptr.*, null, null);

        try pq.add(node);
    }

    while (pq.count() > 1) {
        const left = pq.remove();
        const right = pq.remove();

        const parent: *Node = try .init(allocator, left.freq + right.freq, null, left, right);

        try pq.add(parent);
    }

    const root = pq.remove();

    var dictionary = std.AutoHashMap(u8, []const u8).init(allocator);

    defer {
        var dicit = dictionary.valueIterator();
        while (dicit.next()) |code| allocator.free(code.*);
        dictionary.deinit();
    }

    var path: std.ArrayList(u8) = .empty;
    defer path.deinit(allocator);

    try generateCodes(root, &path, &dictionary, allocator);

    const output_file = try std.fs.cwd().createFile("out.huff", .{});
    defer output_file.close();

    var bit_writer: BitWritter = .{ .out_file = output_file };

    for (content) |char| {
        const code = dictionary.get(char).?;
        for (code) |bit| {
            try bit_writer.writeBit(bit);
        }
    }
    try bit_writer.flush();

    try free_tree(allocator, root);
}
