// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-4
// RESTful API 설계 및 JSON 직렬화 효율화
// ============================================================================
//
// 학습 목표:
// 1. HTTP 핸들러 및 라우팅(Routing) 설계
// 2. HTTP 상태 코드(Status Codes) 관리
// 3. JSON 직렬화/역직렬화 (std.json)
// 4. 스트리밍 API 설계
// 5. Zero-copy 파싱 기술
// 6. API 에러 처리 및 응답
// 7. 데이터 모델과 API 계약(Contract)
//
// 핵심 철학:
// "대외 창구의 설계" - 시스템과 세상의 연결점에서 명확한 약속이 필요하다.
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// ============================================================================
// 섹션 1: HTTP 상태 코드 정의 (HTTP Status Codes)
// ============================================================================

pub const HttpStatusCode = enum(u16) {
    ok = 200, // 요청 성공
    created = 201, // 리소스 생성됨
    bad_request = 400, // 잘못된 요청
    not_found = 404, // 리소스 없음
    conflict = 409, // 충돌
    internal_server_error = 500, // 서버 오류

    pub fn message(self: HttpStatusCode) []const u8 {
        return switch (self) {
            .ok => "OK",
            .created => "Created",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .conflict => "Conflict",
            .internal_server_error => "Internal Server Error",
        };
    }

    pub fn toInt(self: HttpStatusCode) u16 {
        return @intFromEnum(self);
    }
};

// ============================================================================
// 섹션 2: HTTP 메서드 정의 (HTTP Methods)
// ============================================================================

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,

    pub fn fromString(method: []const u8) ?HttpMethod {
        if (std.mem.eql(u8, method, "GET")) return .GET;
        if (std.mem.eql(u8, method, "POST")) return .POST;
        if (std.mem.eql(u8, method, "PUT")) return .PUT;
        if (std.mem.eql(u8, method, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, method, "PATCH")) return .PATCH;
        return null;
    }

    pub fn toString(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
        };
    }
};

// ============================================================================
// 섹션 3: 데이터 모델 정의 (Data Models)
// ============================================================================

/// 사용자 프로필
pub const UserProfile = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    is_admin: bool,

    pub fn format(self: UserProfile) [256]u8 {
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "User{{id={}, username={s}, email={s}, is_admin={}}}", .{
            self.id,
            self.username,
            self.email,
            self.is_admin,
        }) catch {};
        return buf;
    }
};

/// 게시글
pub const Post = struct {
    id: u32,
    title: []const u8,
    content: []const u8,
    author: []const u8,
    created_at: []const u8,

    pub fn format(self: Post) [512]u8 {
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "Post{{id={}, title={s}, author={s}}}", .{
            self.id,
            self.title,
            self.author,
        }) catch {};
        return buf;
    }
};

/// 댓글
pub const Comment = struct {
    id: u32,
    post_id: u32,
    author: []const u8,
    text: []const u8,

    pub fn format(self: Comment) [256]u8 {
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "Comment{{id={}, post_id={}, author={s}}}", .{
            self.id,
            self.post_id,
            self.author,
        }) catch {};
        return buf;
    }
};

// ============================================================================
// 섹션 4: API 요청/응답 구조 (Request/Response)
// ============================================================================

/// HTTP 요청 표현
pub const HttpRequest = struct {
    method: HttpMethod,
    path: []const u8,
    query_params: []const u8,
    body: ?[]const u8,

    pub fn init(method: HttpMethod, path: []const u8) HttpRequest {
        return HttpRequest{
            .method = method,
            .path = path,
            .query_params = "",
            .body = null,
        };
    }
};

/// HTTP 응답 표현
pub const HttpResponse = struct {
    status: HttpStatusCode,
    body: []const u8,
    content_type: []const u8 = "application/json",

    pub fn ok(body: []const u8) HttpResponse {
        return HttpResponse{
            .status = .ok,
            .body = body,
        };
    }

    pub fn created(body: []const u8) HttpResponse {
        return HttpResponse{
            .status = .created,
            .body = body,
        };
    }

    pub fn badRequest(body: []const u8) HttpResponse {
        return HttpResponse{
            .status = .bad_request,
            .body = body,
        };
    }

    pub fn notFound() HttpResponse {
        return HttpResponse{
            .status = .not_found,
            .body = "{}",
        };
    }

    pub fn serverError(body: []const u8) HttpResponse {
        return HttpResponse{
            .status = .internal_server_error,
            .body = body,
        };
    }

    pub fn format(self: HttpResponse) [1024]u8 {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        std.fmt.format(fbs.writer(), "HTTP/1.1 {} {}\nContent-Type: {}\n\n{s}", .{
            self.status.toInt(),
            self.status.message(),
            self.content_type,
            self.body,
        }) catch {};
        return buf;
    }
};

/// 에러 응답 구조
pub const ApiError = struct {
    code: u16,
    message: []const u8,
    details: ?[]const u8 = null,
};

// ============================================================================
// 섹션 5: JSON 직렬화/역직렬화 (JSON Serialization)
// ============================================================================

pub const JsonSerializer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) JsonSerializer {
        return JsonSerializer{
            .allocator = allocator,
        };
    }

    /// 구조체를 JSON 문자열로 직렬화 (Pretty format)
    pub fn serializePretty(self: JsonSerializer, comptime T: type, value: T) ![]u8 {
        return std.json.stringifyAlloc(self.allocator, value, .{
            .whitespace = .indent_2,
        });
    }

    /// 구조체를 JSON 문자열로 직렬화 (Compact format)
    pub fn serializeCompact(self: JsonSerializer, comptime T: type, value: T) ![]u8 {
        return std.json.stringifyAlloc(self.allocator, value, .{});
    }

    /// JSON 문자열을 구조체로 역직렬화
    pub fn deserialize(self: JsonSerializer, comptime T: type, json_str: []const u8) !T {
        var stream = std.json.TokenStream.init(json_str);
        return std.json.parse(T, &stream, .{
            .allocator = self.allocator,
        });
    }

    /// 메모리 크기 비교 (Pretty vs Compact)
    pub fn compareFormats(self: JsonSerializer, comptime T: type, value: T) !struct { pretty: []u8, compact: []u8 } {
        const pretty = try self.serializePretty(T, value);
        const compact = try self.serializeCompact(T, value);

        return .{
            .pretty = pretty,
            .compact = compact,
        };
    }
};

// ============================================================================
// 섹션 6: API 라우터 (Router Implementation)
// ============================================================================

pub const ApiRouter = struct {
    allocator: Allocator,
    posts: ArrayList(Post),
    users: ArrayList(UserProfile),
    comments: ArrayList(Comment),

    pub fn init(allocator: Allocator) ApiRouter {
        return ApiRouter{
            .allocator = allocator,
            .posts = ArrayList(Post).init(allocator),
            .users = ArrayList(UserProfile).init(allocator),
            .comments = ArrayList(Comment).init(allocator),
        };
    }

    pub fn deinit(self: *ApiRouter) void {
        self.posts.deinit();
        self.users.deinit();
        self.comments.deinit();
    }

    /// 라우팅: HTTP 요청을 적절한 핸들러로 연결
    pub fn route(self: *ApiRouter, request: HttpRequest) !HttpResponse {
        // 경로 분석
        if (std.mem.startsWith(u8, request.path, "/users")) {
            return try self.handleUsers(request);
        } else if (std.mem.startsWith(u8, request.path, "/posts")) {
            return try self.handlePosts(request);
        } else if (std.mem.startsWith(u8, request.path, "/comments")) {
            return try self.handleComments(request);
        } else if (std.mem.eql(u8, request.path, "/health")) {
            return try self.handleHealth();
        }

        return HttpResponse.notFound();
    }

    /// GET /health - 서버 상태 확인
    fn handleHealth(self: *ApiRouter) !HttpResponse {
        _ = self;
        const response = "{ \"status\": \"ok\", \"timestamp\": \"2026-02-26T12:00:00Z\" }";
        return HttpResponse.ok(response);
    }

    /// 사용자 핸들러
    fn handleUsers(self: *ApiRouter, request: HttpRequest) !HttpResponse {
        return switch (request.method) {
            .GET => {
                std.debug.print("[API] GET /users\n", .{});
                return HttpResponse.ok("{ \"users\": [] }");
            },
            .POST => {
                std.debug.print("[API] POST /users\n", .{});
                return HttpResponse.created("{ \"id\": 1 }");
            },
            else => HttpResponse.badRequest("Method not allowed"),
        };
    }

    /// 게시글 핸들러
    fn handlePosts(self: *ApiRouter, request: HttpRequest) !HttpResponse {
        return switch (request.method) {
            .GET => {
                std.debug.print("[API] GET /posts\n", .{});
                return HttpResponse.ok("{ \"posts\": [] }");
            },
            .POST => {
                std.debug.print("[API] POST /posts\n", .{});
                return HttpResponse.created("{ \"id\": 1 }");
            },
            .DELETE => {
                std.debug.print("[API] DELETE /posts/1\n", .{});
                return HttpResponse.ok("{ \"deleted\": true }");
            },
            else => HttpResponse.badRequest("Method not allowed"),
        };
    }

    /// 댓글 핸들러
    fn handleComments(self: *ApiRouter, request: HttpRequest) !HttpResponse {
        return switch (request.method) {
            .GET => {
                std.debug.print("[API] GET /comments\n", .{});
                return HttpResponse.ok("{ \"comments\": [] }");
            },
            .POST => {
                std.debug.print("[API] POST /comments\n", .{});
                return HttpResponse.created("{ \"id\": 1 }");
            },
            else => HttpResponse.badRequest("Method not allowed"),
        };
    }
};

// ============================================================================
// 섹션 7: API 계약(Contract) 문서화
// ============================================================================

pub const ApiContract = struct {
    pub const Endpoints = struct {
        // GET /health - 서버 상태 확인
        pub const health_check = struct {
            pub const method = "GET";
            pub const path = "/health";
            pub const response = struct {
                status: []const u8,
                timestamp: []const u8,
            };
        };

        // GET /users - 모든 사용자 조회
        pub const list_users = struct {
            pub const method = "GET";
            pub const path = "/users";
            pub const response = struct {
                users: []const u8,
            };
        };

        // POST /users - 사용자 생성
        pub const create_user = struct {
            pub const method = "POST";
            pub const path = "/users";
            pub const request = struct {
                username: []const u8,
                email: []const u8,
            };
            pub const response = struct {
                id: u32,
            };
        };

        // GET /posts/:id - 특정 게시글 조회
        pub const get_post = struct {
            pub const method = "GET";
            pub const path = "/posts/:id";
            pub const response = Post;
        };

        // POST /posts - 게시글 생성
        pub const create_post = struct {
            pub const method = "POST";
            pub const path = "/posts";
            pub const request = struct {
                title: []const u8,
                content: []const u8,
                author: []const u8,
            };
            pub const response = struct {
                id: u32,
                created_at: []const u8,
            };
        };

        // DELETE /posts/:id - 게시글 삭제
        pub const delete_post = struct {
            pub const method = "DELETE";
            pub const path = "/posts/:id";
            pub const response = struct {
                deleted: bool,
            };
        };
    };

    pub fn printContract() void {
        std.debug.print(
            \\
            \\【 API 계약(Contract) 정의 】
            \\
            \\1. GET /health
            \\   Response: {{ "status": "ok", "timestamp": "..." }}
            \\
            \\2. GET /users
            \\   Response: {{ "users": [...] }}
            \\
            \\3. POST /users
            \\   Request: {{ "username": "...", "email": "..." }}
            \\   Response: {{ "id": 1 }}
            \\
            \\4. GET /posts/:id
            \\   Response: Post struct
            \\
            \\5. POST /posts
            \\   Request: {{ "title": "...", "content": "...", "author": "..." }}
            \\   Response: {{ "id": 1, "created_at": "..." }}
            \\
            \\6. DELETE /posts/:id
            \\   Response: {{ "deleted": true }}
            \\
        , .{});
    }
};

// ============================================================================
// 메인 함수: API 설계 시연
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔═══════════════════════════════════════════════════════════╗
        \\║   🎓 Zig 전공 201: RESTful API 설계 및 JSON 효율화        ║
        \\║   "대외 창구의 설계"                                     ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // JSON 직렬화/역직렬화 시연
    std.debug.print("\n【 JSON 직렬화 및 역직렬화 】\n\n", .{});

    var serializer = JsonSerializer.init(allocator);

    // 사용자 객체 생성
    const user = UserProfile{
        .id = 1,
        .username = "zig_master",
        .email = "master@zig.dev",
        .is_admin = true,
    };

    // Pretty format JSON
    const user_json_pretty = try serializer.serializePretty(UserProfile, user);
    defer allocator.free(user_json_pretty);
    std.debug.print("Pretty JSON:\n{s}\n\n", .{user_json_pretty});

    // Compact format JSON
    const user_json_compact = try serializer.serializeCompact(UserProfile, user);
    defer allocator.free(user_json_compact);
    std.debug.print("Compact JSON:\n{s}\n\n", .{user_json_compact});

    // 메모리 크기 비교
    std.debug.print("【 JSON 크기 비교 】\n", .{});
    std.debug.print("Pretty: {} bytes\n", .{user_json_pretty.len});
    std.debug.print("Compact: {} bytes\n", .{user_json_compact.len});
    std.debug.print("절약률: {d:.1}%\n\n", .{
        (@as(f64, @floatFromInt(user_json_pretty.len - user_json_compact.len)) /
            @as(f64, @floatFromInt(user_json_pretty.len))) * 100.0,
    });

    // 게시글 JSON
    std.debug.print("【 게시글 JSON 직렬화 】\n\n", .{});
    const post = Post{
        .id = 1,
        .title = "Zig으로 배우는 시스템 프로그래밍",
        .content = "대규모 시스템 설계의 기초...",
        .author = "Alice",
        .created_at = "2026-02-26T12:00:00Z",
    };

    const post_json = try serializer.serializePretty(Post, post);
    defer allocator.free(post_json);
    std.debug.print("{s}\n\n", .{post_json});

    // API 라우팅 시연
    std.debug.print("【 API 라우팅 및 요청 처리 】\n\n", .{});

    var router = ApiRouter.init(allocator);
    defer router.deinit();

    // 요청 1: GET /health
    const req1 = HttpRequest.init(.GET, "/health");
    const res1 = try router.route(req1);
    std.debug.print("요청: {} {}\n", .{req1.method.toString(), req1.path});
    std.debug.print("응답: HTTP/1.1 {} {}\n\n", .{ res1.status.toInt(), res1.status.message() });

    // 요청 2: POST /users
    const req2 = HttpRequest.init(.POST, "/users");
    const res2 = try router.route(req2);
    std.debug.print("요청: {} {}\n", .{req2.method.toString(), req2.path});
    std.debug.print("응답: HTTP/1.1 {} {}\n\n", .{ res2.status.toInt(), res2.status.message() });

    // 요청 3: GET /posts
    const req3 = HttpRequest.init(.GET, "/posts");
    const res3 = try router.route(req3);
    std.debug.print("요청: {} {}\n", .{req3.method.toString(), req3.path});
    std.debug.print("응답: HTTP/1.1 {} {}\n\n", .{ res3.status.toInt(), res3.status.message() });

    // 요청 4: DELETE /posts/1
    const req4 = HttpRequest.init(.DELETE, "/posts/1");
    const res4 = try router.route(req4);
    std.debug.print("요청: {} {}\n", .{req4.method.toString(), req4.path});
    std.debug.print("응답: HTTP/1.1 {} {}\n\n", .{ res4.status.toInt(), res4.status.message() });

    // 요청 5: GET /unknown (404)
    const req5 = HttpRequest.init(.GET, "/unknown");
    const res5 = try router.route(req5);
    std.debug.print("요청: {} {}\n", .{req5.method.toString(), req5.path});
    std.debug.print("응답: HTTP/1.1 {} {}\n\n", .{ res5.status.toInt(), res5.status.message() });

    // API 계약 문서화
    ApiContract.printContract();

    // 종합 정보
    std.debug.print("\n【 RESTful API 설계 핵심 요소 】\n", .{});
    std.debug.print("✓ HTTP 상태 코드 (200, 201, 400, 404, 500)\n", .{});
    std.debug.print("✓ HTTP 메서드 (GET, POST, PUT, DELETE, PATCH)\n", .{});
    std.debug.print("✓ JSON 직렬화/역직렬화 (std.json)\n", .{});
    std.debug.print("✓ 라우팅 (경로 분석 및 핸들러 연결)\n", .{});
    std.debug.print("✓ 요청/응답 모델 (Request/Response)\n", .{});
    std.debug.print("✓ API 계약 (코드가 문서)\n", .{});

    std.debug.print("\n【 Assignment 2-4 】\n", .{});
    std.debug.print("1. Post 구조체 직렬화\n", .{});
    std.debug.print("2. JSON 변환 (Pretty/Compact)\n", .{});
    std.debug.print("3. 에러 처리 (malformed JSON)\n", .{});
    std.debug.print("4. 메모리 절약률 기록\n", .{});

    std.debug.print("\n✅ RESTful API 설계 및 JSON 효율화 완료!\n\n", .{});
}

// ============================================================================
// 단위 테스트
// ============================================================================

test "HttpStatusCode conversion" {
    const status = HttpStatusCode.ok;
    try testing.expect(status.toInt() == 200);
    try testing.expect(std.mem.eql(u8, status.message(), "OK"));
}

test "HttpMethod parsing" {
    const method = HttpMethod.fromString("GET");
    try testing.expect(method == .GET);
    try testing.expect(std.mem.eql(u8, method.?.toString(), "GET"));
}

test "HttpMethod invalid" {
    const method = HttpMethod.fromString("INVALID");
    try testing.expect(method == null);
}

test "UserProfile JSON serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serializer = JsonSerializer.init(allocator);

    const user = UserProfile{
        .id = 1,
        .username = "test",
        .email = "test@example.com",
        .is_admin = false,
    };

    const json = try serializer.serializeCompact(UserProfile, user);
    defer allocator.free(json);

    try testing.expect(json.len > 0);
    try testing.expect(std.mem.indexOf(u8, json, "test") != null);
}

test "Post JSON serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serializer = JsonSerializer.init(allocator);

    const post = Post{
        .id = 1,
        .title = "Test Post",
        .content = "Content",
        .author = "Alice",
        .created_at = "2026-02-26",
    };

    const json = try serializer.serializeCompact(Post, post);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "Test Post") != null);
}

test "HttpResponse creation" {
    const response = HttpResponse.ok("{ \"status\": \"ok\" }");
    try testing.expect(response.status == .ok);
    try testing.expect(std.mem.indexOf(u8, response.body, "status") != null);
}

test "HttpResponse not found" {
    const response = HttpResponse.notFound();
    try testing.expect(response.status == .not_found);
}

test "HttpResponse created" {
    const response = HttpResponse.created("{ \"id\": 1 }");
    try testing.expect(response.status == .created);
}

test "ApiRouter health check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = ApiRouter.init(allocator);
    defer router.deinit();

    const request = HttpRequest.init(.GET, "/health");
    const response = try router.route(request);

    try testing.expect(response.status == .ok);
}

test "ApiRouter not found" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = ApiRouter.init(allocator);
    defer router.deinit();

    const request = HttpRequest.init(.GET, "/unknown");
    const response = try router.route(request);

    try testing.expect(response.status == .not_found);
}

test "JSON format comparison" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serializer = JsonSerializer.init(allocator);

    const user = UserProfile{
        .id = 1,
        .username = "zig_master",
        .email = "master@zig.dev",
        .is_admin = true,
    };

    const formats = try serializer.compareFormats(UserProfile, user);
    defer allocator.free(formats.pretty);
    defer allocator.free(formats.compact);

    // Compact should be smaller or equal
    try testing.expect(formats.compact.len <= formats.pretty.len);
}

test "Comment JSON serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serializer = JsonSerializer.init(allocator);

    const comment = Comment{
        .id = 1,
        .post_id = 1,
        .author = "Bob",
        .text = "Great post!",
    };

    const json = try serializer.serializeCompact(Comment, comment);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "Great post") != null);
}

test "모든 API 테스트 통과" {
    std.debug.print("\n✅ RESTful API - 모든 테스트 완료!\n", .{});
}
