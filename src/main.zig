const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("libyaml.h");
});

const YamlEvents = enum(c_int) {
    YAML_NO_EVENT,
    YAML_STREAM_START_EVENT,
    YAML_STREAM_END_EVENT,
    YAML_DOCUMENT_START_EVENT,
    YAML_DOCUMENT_END_EVENT,
    YAML_ALIAS_EVENT,
    YAML_SCALAR_EVENT,
    YAML_SEQUENCE_START_EVENT,
    YAML_SEQUENCE_END_EVENT,
    YAML_MAPPING_START_EVENT,
    YAML_MAPPING_END_EVENT,
};

const YamlCurrentlyParsing = enum {
    KEY,
    VALUE,
};

const YamlNodeType = enum {
    DOCUMENT,
    STRING,
    ARRAY,
    ARRAY_ELEMENT,
    INT,
    FLOAT,
    OBJECT,
    ALIAS,
    BOOL,
    UNKNOWN,
};

const YamlNode = struct {
    parent: ?*YamlNode,
    node_type: YamlNodeType,
    key: ?[]u8,
    key_set: bool = false,
    value: ?[]u8,
    value_set: bool = false,
    nodes: std.ArrayList(*YamlNode),

    fn create_node(alloc: std.mem.Allocator, parent: *YamlNode) !*YamlNode {
        var node = try alloc.create(YamlNode);
        node.node_type = .UNKNOWN;
        node.key = undefined;
        node.value = null;
        node.nodes = std.ArrayList(*YamlNode).init(alloc);
        node.parent = parent;
        try parent.nodes.append(node);
        return node;
    }

    pub fn print(self: *YamlNode, alloc: std.mem.Allocator, depth: usize) !void {
        var padding = try alloc.alloc(u8, depth);
        @memset(padding[0..depth], 0x20);

        if (self.node_type == .DOCUMENT) {
            std.log.info("Document Start", .{});
        }
        if (self.node_type != .DOCUMENT) {
            if (self.value == null) {
                std.log.info("{s}Type {s} | Key \"{s}\" | Children={d}", .{
                    padding,
                    @tagName(self.node_type),
                    self.key orelse "",
                    self.nodes.items.len,
                });
            } else {
                std.log.info("{s}Type {s} | Key \"{s}\" | Value \"{s}\" | Children={d}", .{
                    padding,
                    @tagName(self.node_type),
                    self.key orelse "",
                    self.value orelse "",
                    self.nodes.items.len,
                });
            }
        }
        // std.log.info("Key {s}, Value {s}, Children {d}", .{ self.key, "", self.nodes.items.len });

        for (self.nodes.items) |i| {
            try i.print(alloc, depth + 2);
        }
    }

    fn set_key(self: *YamlNode, alloc: std.mem.Allocator, key: []u8) !void {
        if (self.key_set) {
            return error.KeyAlreadySet;
        }

        self.key = try alloc.alloc(u8, key.len);
        std.mem.copyForwards(u8, self.key orelse unreachable, key);
        self.key_set = true;
    }

    fn get_key(self: *YamlNode) []u8 {
        return self.key;
    }

    fn set_value(self: *YamlNode, alloc: std.mem.Allocator, value: []u8) !void {
        if (self.value_set) {
            return error.ValueAlreadySet;
        }

        self.value = try alloc.alloc(u8, value.len);
        std.mem.copyForwards(u8, self.value orelse unreachable, value);
        self.value_set = true;

        self.node_type = .STRING;

        try self.set_scalar_value_type(alloc);
    }

    fn set_scalar_value_type(self: *YamlNode, alloc: std.mem.Allocator) !void {
        if (self.value) |v| {
            var found_int = true;
            _ = std.fmt.parseInt(i32, v, 10) catch {
                found_int = false;
            };

            if (found_int) {
                self.node_type = .INT;
                return;
            }

            var found_float = true;
            _ = std.fmt.parseFloat(f32, v) catch {
                found_float = false;
            };

            if (found_float) {
                self.node_type = .FLOAT;
                return;
            }

            const v_tolower = try alloc.alloc(u8, v.len);
            defer alloc.free(v_tolower);

            self.toLower(v_tolower);
            if (std.mem.eql(u8, v_tolower, "true") or std.mem.eql(u8, v_tolower, "false")) {
                self.node_type = .BOOL;
                return;
            }
        }
    }

    fn get_bool_val(self: *YamlNode, alloc: std.mem.Allocator) !bool {
        const v = self.value orelse unreachable;
        const v_tolower = try alloc.alloc(u8, v.len);

        self.toLower(v_tolower);
        if (std.mem.eql(u8, v_tolower, "true") or std.mem.eql(u8, v_tolower, "1")) {
            return true;
        }

        return false;
    }

    fn get_float_val(self: *YamlNode, comptime T: anytype) !T {
        return std.fmt.parseFloat(T, self.value orelse unreachable);
    }

    fn get_int_val(self: *YamlNode, comptime T: anytype) !T {
        return std.fmt.parseInt(T, self.value orelse unreachable, 10);
    }

    fn hasChildren(self: *YamlNode) bool {
        if (self.nodes.items.len > 0) {
            return true;
        }
        return false;
    }

    fn toLower(self: *YamlNode, dest: []u8) void {
        if (self.value) |v| {
            for (0..v.len) |i| {
                dest[i] = std.ascii.toLower(v[i]);
            }
        }
    }
};

pub fn DeserializedYaml(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,
        messages: std.ArrayList([]u8),

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn print(self: *Self) !void {
            var printer = print_with_padding(self.arena.allocator(), self.value, 0);
            try printer.print();

            if (self.messages.items.len > 0) {
                std.log.info("Parser Messages: ", .{});
                for (self.messages.items) |m| {
                    std.log.info(" - {s}", .{m});
                }
            }
        }
    };
}

fn PrintWithPadding(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        depth: usize,
        value: T,

        const Self = @This();

        pub fn print(self: *Self) !void {
            var padding = try self.alloc.alloc(u8, self.depth);
            @memset(padding[0..self.depth], 0x20);

            switch (@typeInfo(T)) {
                .pointer => |p| {
                    switch (p.size) {
                        .Slice => {
                            for (self.value) |v| {
                                std.debug.print("\n{s}-\n", .{padding});
                                var printer = print_with_padding(self.alloc, v, self.depth + 1);
                                try printer.print();
                            }
                        },
                        else => {},
                    }
                },
                .@"struct" => |s| {
                    inline for (s.fields) |field| {
                        switch (field.type) {
                            []u8 => {
                                std.debug.print("{s}{s}: {s}\n", .{ padding, field.name, @field(self.value, field.name) });
                            },
                            else => {
                                switch (@typeInfo(field.type)) {
                                    .comptime_int, .int => {
                                        std.debug.print("{s}{s}: {d}\n", .{ padding, field.name, @field(self.value, field.name) });
                                    },
                                    .comptime_float, .float => {
                                        std.debug.print("{s}{s}: {d}\n", .{ padding, field.name, @field(self.value, field.name) });
                                    },
                                    .bool => {
                                        std.debug.print("{s}{s}: {}\n", .{ padding, field.name, @field(self.value, field.name) });
                                    },
                                    else => {
                                        std.debug.print("{s}{s}:", .{ padding, field.name });
                                        var printer = print_with_padding(self.alloc, @field(self.value, field.name), self.depth + 1);
                                        try printer.print();
                                    },
                                }
                            },
                        }
                    }
                },
                else => {},
            }
        }
    };
}

fn print_with_padding(alloc: std.mem.Allocator, value: anytype, depth: usize) PrintWithPadding(@TypeOf(value)) {
    return .{
        .alloc = alloc,
        .depth = depth,
        .value = value,
    };
}

pub fn YamlParser(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator = undefined,
        alloc: std.mem.Allocator = undefined,
        parent_alloc: std.mem.Allocator = undefined,

        // Setup the document
        document_limit: usize = 1000,
        documents: std.ArrayList(*YamlNode) = undefined,

        // Tracking information used by the parser
        current_document_index: i32 = 0,
        current_node: *YamlNode = undefined,

        const Self = @This();

        pub fn init(self: *Self, alloc: std.mem.Allocator) !void {
            // Create a memory arena so that this entire thing can be destroyed at once
            self.arena = std.heap.ArenaAllocator.init(alloc);

            // Create the allocator from the arena that the parser will use
            self.alloc = self.arena.allocator();

            // Store a reference to the parent allocator so that returned documents are held under that scope
            self.parent_alloc = alloc;

            // Create lists needed to help with parsing
            self.documents = std.ArrayList(*YamlNode).init(self.alloc);
        }

        pub fn deinit(self: Self) void {
            self.arena.deinit();
        }

        // Shorthand Helper
        pub fn parse(self: *Self, bytes: []u8) !DeserializedYaml(T) {
            return self.parse_document_n(bytes, 0);
        }

        pub fn parse_document_n(self: *Self, bytes: []u8, document_index: usize) !DeserializedYaml(T) {

            // Set a limit on the number of documents parsed for VERY large yaml files
            self.document_limit = document_index;

            // Read YAML and deserialize into an in-memory structure
            try self.deserialize(bytes);

            // if we did not get any documents back, then return an error
            if (self.documents.items.len < 1) {
                return error.NoDocuments;
            }

            // If userland is requesting a document that does not exist, return an error
            if (self.documents.items.len < document_index) {
                return error.InvalidDocumentIndex;
            }

            var documents = std.ArrayList(DeserializedYaml(T)).init(self.alloc);
            defer documents.deinit();

            // Loop over the documents
            for (self.documents.items) |document| {
                if (documents.items.len > self.document_limit) {
                    break;
                }

                const arena = std.heap.ArenaAllocator.init(self.parent_alloc);

                // Setup the return value
                var deserialized = DeserializedYaml(T){
                    .arena = arena,
                    .value = undefined,
                    .messages = undefined,
                };

                errdefer deserialized.arena.deinit();

                // Walk the internal structure and hydrate the userland structure
                var deserializer = try walk_and_deserialize_to_struct(deserialized.arena.allocator(), document.nodes.items, T);
                deserialized.value = try deserializer.walk();
                deserialized.messages = deserializer.messages;

                // Append the document to the list
                try documents.append(deserialized);
            }

            const docs = try documents.toOwnedSlice();
            return docs[document_index];
        }

        pub fn parse_document_range(self: *Self, bytes: []u8, start_index: usize, end_index: usize) ![]DeserializedYaml(T) {

            // Set a limit on the number of documents parsed for VERY large yaml files
            self.document_limit = end_index;

            // Read YAML and deserialize into an in-memory structure
            try self.deserialize(bytes);

            // if we did not get any documents back, then return an error
            if (self.documents.items.len < 1) {
                return error.NoDocuments;
            }

            // If userland is requesting a document that does not exist, return an error
            if (self.documents.items.len < end_index) {
                return error.InvalidEndingDocumentIndex;
            }

            var documents = std.ArrayList(DeserializedYaml(T)).init(self.alloc);

            // Loop over the documents
            for (self.documents.items) |document| {
                if (documents.items.len > self.document_limit) {
                    break;
                }

                const arena = std.heap.ArenaAllocator.init(self.parent_alloc);

                // Setup the return value
                var deserialized = DeserializedYaml(T){
                    .arena = arena,
                    .value = undefined,
                    .messages = undefined,
                };

                errdefer deserialized.arena.deinit();

                // Walk the internal structure and hydrate the userland structure
                var deserializer = try walk_and_deserialize_to_struct(deserialized.arena.allocator(), document.nodes.items, T);
                deserialized.value = try deserializer.walk();
                deserialized.messages = deserializer.messages;

                // Append the document to the list
                try documents.append(deserialized);
            }

            const docs = try documents.toOwnedSlice();
            return docs[start_index..end_index];
        }

        pub fn deserialize(self: *Self, bytes: []u8) !void {
            if (self.documents.items.len > 0) {
                std.log.err("A YAML Parser cannot be reused.  Deinit the existing parser and instantiate a new one", .{});
                return error.CannotReuseYamlParser;
            }

            var parser: c.yaml_parser_t = undefined;
            var event: c.struct_yaml_event_s = undefined;

            // convert from something Zig understands into something C understands
            const c_ptr: [*c]const u8 = @ptrCast(bytes);

            // Setup the C Yaml Parser
            const init_code = c.yaml_parser_initialize(&parser);
            defer c.yaml_parser_delete(&parser);

            if (init_code != 1) {
                return error.UnableToInitializeParser;
            }

            // Set the string we will be parsing in C
            c.yaml_parser_set_input_string(&parser, c_ptr, bytes.len);

            // This is a flip flop to determine if we are parsing a key or value
            var parsing_state: YamlCurrentlyParsing = .KEY;

            // Loop until we run out of data
            while (true) {
                defer c.yaml_event_delete(&event);

                // An event is an ecapsulation of what the parser found as it was scanning the tokens in the YAML input
                const event_code = c.yaml_parser_parse(&parser, &event);
                if (event_code != 1) {
                    return error.ParseError;
                }

                switch (@as(YamlEvents, @enumFromInt(event.type))) {
                    // Noop, keep moving
                    .YAML_NO_EVENT => {
                        //std.log.info("Got Event NO_EVENT Code: {d}", .{event.type});
                        continue;
                    },

                    // this denotes a single stream of bytes
                    .YAML_STREAM_START_EVENT => {
                        //std.log.info("Got Event STREAM_START Code: {d}", .{event.type});
                        continue;
                    },

                    // Denotes we have hit the end of the bytes stream
                    .YAML_STREAM_END_EVENT => {
                        //std.log.info("Got Event STREAM_END Code: {d}", .{event.type});
                        break;
                    },
                    // I would assume that this is an event for multiple yaml documents in a single stream
                    .YAML_DOCUMENT_START_EVENT => {
                        // Only create a new document if we need one?  This is probably a useless check
                        if (self.current_document_index + 1 > self.documents.items.len) {
                            // Create a new document
                            var doc = try self.alloc.create(YamlNode);
                            doc.key = undefined;
                            doc.nodes = std.ArrayList(*YamlNode).init(self.alloc);
                            doc.node_type = .DOCUMENT;
                            doc.parent = null;
                            try doc.set_key(self.alloc, @as([]u8, @constCast("Document")));

                            // Append that document to the list
                            try self.documents.append(doc);

                            // Set the current node
                            self.current_node = doc;

                            //std.log.info("Got Event DOCUMENT_START Code: {d}", .{event.type});
                        }
                        continue;
                    },

                    // Finished a document, ready to start the next document
                    .YAML_DOCUMENT_END_EVENT => {
                        // Increment the index so that we can step into the next document
                        self.current_document_index += 1;

                        if (self.current_document_index > self.document_limit) {
                            break;
                        }

                        //std.log.info("Got Event DOCUMENT_END Code: {d}", .{event.type});
                        continue;
                    },

                    // FIXME: IDK??
                    .YAML_ALIAS_EVENT => {
                        //std.log.info("Got Event ALIAS Code: {d}", .{event.type});
                    },

                    // A scalar event is either a key or value represented as a string, further processing on value needs to be done to get it into the right type for the struct
                    .YAML_SCALAR_EVENT => {
                        //std.log.info("Got Event SCALAR Code: {d}", .{event.type});
                        if (parsing_state == .KEY) {
                            if (self.current_node.key_set) {
                                try self.next_node();
                            }

                            // YAML keys have a max len of 1024 according to the spec
                            var key = try self.alloc.alloc(u8, event.data.scalar.length);
                            copy(event.data.scalar.value, key, event.data.scalar.length);

                            try self.current_node.set_key(self.alloc, key[0..event.data.scalar.length]);

                            parsing_state = .VALUE;
                            continue;
                        }

                        if (parsing_state == .VALUE) {
                            // FIXME: Currently set to 1024, but this needs to change if we start parsing REAL yaml
                            var value = try self.alloc.alloc(u8, event.data.scalar.length);

                            copy(event.data.scalar.value, value, event.data.scalar.length);
                            try self.current_node.set_value(self.alloc, value[0..event.data.scalar.length]);

                            parsing_state = .KEY;

                            continue;
                        }
                    },

                    // A sequence is esentially an array
                    .YAML_SEQUENCE_START_EVENT => {
                        //std.log.info("Got Event SEQUENCE_START Code: {d}", .{event.type});

                        parsing_state = .KEY;
                        self.current_node.node_type = .ARRAY;
                    },
                    .YAML_SEQUENCE_END_EVENT => {
                        //std.log.info("Got Event SEQUENCE_END Code: {d}", .{event.type});

                        parsing_state = .KEY;
                    },

                    // A mapping is esentially an object
                    .YAML_MAPPING_START_EVENT => {
                        //std.log.info("Got Event MAPPING_START Code: {d}", .{event.type});

                        parsing_state = .KEY;
                        try self.next_node();

                        self.current_node.node_type = .OBJECT;
                    },
                    .YAML_MAPPING_END_EVENT => {
                        //std.log.info("Got Event MAPPING_END Code: {d}", .{event.type});

                        parsing_state = .KEY;
                        switch (if (self.current_node.parent) |p| p.node_type else unreachable) {
                            // Needs to step back twice because this is a special case where array elements get their own container
                            .ARRAY_ELEMENT => {
                                // Step back twice
                                const node = self.current_node.parent orelse unreachable;
                                self.current_node = node.parent orelse unreachable;
                                continue;
                            },
                            // default case where only one step back to the parent is needed
                            else => self.current_node = self.current_node.parent orelse unreachable,
                        }
                    },
                }
            }
        }

        fn next_node(self: *Self) !void {
            switch (self.current_node.node_type) {
                .ARRAY => {
                    var node = try YamlNode.create_node(self.alloc, self.current_node);
                    node.node_type = .ARRAY_ELEMENT;
                    try node.set_key(self.alloc, @as([]u8, @constCast("Array Element")));
                    self.current_node = try YamlNode.create_node(self.alloc, node);
                    return;
                },
                .ARRAY_ELEMENT => {
                    self.current_node = try YamlNode.create_node(self.alloc, self.current_node.parent orelse unreachable);
                    return;
                },
                .DOCUMENT, .OBJECT => {
                    self.current_node = try YamlNode.create_node(self.alloc, self.current_node);
                    return;
                },
                else => {
                    self.current_node = try YamlNode.create_node(self.alloc, self.current_node.parent orelse unreachable);
                    return;
                },
            }
        }

        fn copy(src: [*c]u8, dest: []u8, len: usize) void {
            for (0..len) |i| {
                dest[i] = src[i];
            }
        }
    };
}

pub fn yaml_parser(ret: anytype) !YamlParser(ret) {
    return .{};
}

test "simple_yaml parse_document_n" {
    const dat = struct {
        name: []u8 = undefined,
    };

    const alloc = std.testing.allocator;

    // Setup the parser
    var parser = try yaml_parser(dat);
    try parser.init(alloc);
    defer parser.deinit();

    var parsed = try parser.parse_document_n(@constCast("name: hello world"), 0);
    defer parsed.deinit();

    try std.testing.expectEqualSlices(u8, "hello world", parsed.value.name);
}

test "simple_yaml parse_document_range" {
    const dat = struct {
        name: []u8 = undefined,
    };

    const alloc = std.testing.allocator;

    // Setup the parser
    var parser = try yaml_parser(dat);
    try parser.init(alloc);
    defer parser.deinit();

    var parsed = try parser.parse_document_range(@constCast("name: hello world"), 0, 1);
    for (0..parsed.len) |p| {
        defer parsed[p].deinit();
    }

    try std.testing.expectEqualSlices(u8, "hello world", parsed[0].value.name);
}

fn WalkDeserializeToStruct(comptime T: type) type {
    return struct {
        alloc: std.mem.Allocator,
        nodes: []*YamlNode,
        node: *YamlNode,
        messages: std.ArrayList([]u8),

        const Self = @This();

        pub fn walk(self: *Self) !T {
            switch (@typeInfo(T)) {
                .array => |_| {
                    unreachable;
                },
                .bool => {
                    if (self.node.node_type != .BOOL) {
                        try self.messages.append(try std.fmt.allocPrint(self.alloc, "Expected type is {s} for key {s}, deserialized type is {s}", .{ @typeName(T), self.node.key orelse unreachable, @tagName(self.node.node_type) }));
                    }

                    return try self.node.get_bool_val(self.alloc);
                },
                .float => {
                    if (self.node.node_type != .FLOAT) {
                        try self.messages.append(try std.fmt.allocPrint(self.alloc, "Expected type is {s} for key {s}, deserialized type is {s}", .{ @typeName(T), self.node.key orelse unreachable, @tagName(self.node.node_type) }));
                    }

                    return self.node.get_float_val(T);
                },
                .int => {
                    if (self.node.node_type != .INT) {
                        try self.messages.append(try std.fmt.allocPrint(self.alloc, "Expected type is {s} for key {s}, deserialized type is {s}", .{ @typeName(T), self.node.key orelse unreachable, @tagName(self.node.node_type) }));
                    }

                    return self.node.get_int_val(T);
                },
                .optional => |o| {
                    var next = try walk_and_deserialize_to_struct(self.alloc, self.node, o.child);
                    defer self.messages.appendSlice(next.messages.items) catch |e| {
                        std.log.err("Unable to append message: {}", .{e});
                    };

                    return try next.walk();
                },
                .pointer => |p| {
                    switch (p.size) {
                        .One => {
                            const r: *p.child = try self.alloc.create(p.child);
                            var next = try walk_and_deserialize_to_struct(self.alloc, self.node, p.child);
                            defer self.messages.appendSlice(next.messages.items) catch |e| {
                                std.log.err("Unable to append message: {}", .{e});
                            };
                            r.* = try next.walk();

                            return r;
                        },
                        .Slice => {

                            // Deal with concrete types once we have no more children
                            if (!self.node.hasChildren()) {
                                switch (self.node.node_type) {
                                    // "STRING" types need to be dealt with here since they are pointers not really concrete types
                                    .STRING => {
                                        if (T != []u8) {
                                            try self.messages.append(try std.fmt.allocPrint(self.alloc, "UnexpectedPointerType {s} on {d}", .{ @typeName(T), getLineNumber() }));
                                            return error.UnexpectedPointerType;
                                        }

                                        return (self.node.value orelse try self.alloc.alloc(u8, 0));
                                    },
                                    else => |e| {
                                        try self.messages.append(try std.fmt.allocPrint(self.alloc, "UnexpectedPointerType {s} on {d}", .{ @tagName(e), getLineNumber() }));
                                        return error.UnexpectedPointerType;
                                    },
                                }
                            }

                            var arr = std.ArrayList(p.child).init(self.alloc);
                            for (self.node.nodes.items) |n| {
                                var next = try walk_and_deserialize_to_struct(self.alloc, n, p.child);
                                defer self.messages.appendSlice(next.messages.items) catch |e| {
                                    std.log.err("Unable to append message: {}", .{e});
                                };
                                try arr.append(try next.walk());
                            }
                            return try arr.toOwnedSlice();
                        },
                        else => |e| {
                            try self.messages.append(try std.fmt.allocPrint(self.alloc, "UnexpectedPointerType {s} on {d}", .{ @tagName(e), getLineNumber() }));
                            return error.UnexpectedPointerType;
                        },
                    }
                },
                .@"struct" => |s| {
                    switch (self.node.node_type) {

                        // An ARRAY_ELEMENT is a container/bridge between the previous type and the next type
                        .ARRAY_ELEMENT => {
                            const r: *T = try self.alloc.create(T);
                            r.* = T{};
                            for (self.node.nodes.items) |n| {
                                inline for (s.fields) |field| {
                                    if (std.mem.eql(u8, field.name, n.key orelse unreachable)) {
                                        var next = try walk_and_deserialize_to_struct(self.alloc, n, field.type);
                                        defer self.messages.appendSlice(next.messages.items) catch |e| {
                                            std.log.err("Unable to append message: {}", .{e});
                                        };

                                        @field(r, field.name) = try next.walk();
                                    }
                                }
                            }

                            return r.*;
                        },

                        // This covers all normal flow
                        else => {
                            const r: *T = try self.alloc.create(T);
                            r.* = T{};
                            for (self.nodes) |current_node| {
                                self.node = current_node;

                                inline for (s.fields) |field| {
                                    if (std.mem.eql(u8, field.name, self.node.key orelse unreachable)) {
                                        var next = try walk_and_deserialize_to_struct(self.alloc, self.node, field.type);
                                        defer self.messages.appendSlice(next.messages.items) catch |e| {
                                            std.log.err("Unable to append message: {}", .{e});
                                        };

                                        @field(r.*, field.name) = try next.walk();
                                    }
                                }
                            }

                            return r.*;
                        },
                    }
                },
                else => |_| {
                    unreachable;
                },
            }
        }

        fn getLineNumber() i32 {
            const src = @src();
            return src.line;
        }
    };
}

fn walk_and_deserialize_to_struct(alloc: std.mem.Allocator, nodes: anytype, T: anytype) !WalkDeserializeToStruct(T) {
    const selfNodes = switch (@TypeOf(nodes)) {
        *YamlNode => blk: {
            var r = std.ArrayList(*YamlNode).init(alloc);
            try r.append(nodes);
            break :blk r.items;
        },
        []*YamlNode => nodes,
        else => unreachable,
    };

    return .{
        .alloc = alloc,
        .nodes = selfNodes,
        .node = selfNodes[0],
        .messages = std.ArrayList([]u8).init(alloc),
    };
}
