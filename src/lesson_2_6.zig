// ============================================================================
// 🎓 Zig 전공 201: Lesson 2-6
// 보안(Security) - 암호화와 인증 프로토콜 설계
// ============================================================================
//
// 학습 목표:
// 1. 현대적 암호화 라이브러리 (std.crypto)
// 2. 해시 함수 (SHA-256, BLAKE3)
// 3. AEAD 암호화 (AES-GCM, ChaCha20-Poly1305)
// 4. 비대칭키 서명 (Ed25519)
// 5. 보안을 고려한 메모리 관리 (Secure Zeroing)
// 6. 인증 및 JWT 설계
// 7. RBAC (Role-Based Access Control)
// 8. TLS(Transport Layer Security) 시뮬레이션
// 9. 메시지 서명 및 검증
// 10. 상수 시간 연산 (Constant-time Operations)
//
// 핵심 철학:
// "신뢰의 방패" - 시스템의 데이터 무결성을 보장하고 침입을 차단하는 정밀함이 필요하다.
// 저급 언어인 Zig에서 보안은 단순히 라이브러리를 쓰는 것을 넘어,
// 사이드 채널 공격과 메모리 잔류 데이터까지 고려해야 한다.
// ============================================================================

const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const crypto = std.crypto;

// ============================================================================
// 섹션 1: 해시 함수 (Hash Functions)
// ============================================================================

pub const HashAlgorithm = enum {
    sha256,
    blake3,

    pub fn toString(self: HashAlgorithm) []const u8 {
        return switch (self) {
            .sha256 => "SHA-256",
            .blake3 => "BLAKE3",
        };
    }
};

pub const HashDigest = struct {
    algorithm: HashAlgorithm,
    bytes: [32]u8,

    pub fn format(self: HashDigest) [64]u8 {
        var result: [64]u8 = undefined;
        _ = std.fmt.bufPrintZ(&result, "{s}", .{std.fmt.fmtSliceHexLower(&self.bytes)}) catch unreachable;
        return result;
    }

    pub fn equals(self: *const HashDigest, other: *const HashDigest) bool {
        // Constant-time comparison to prevent timing attacks
        var diff: u8 = 0;
        for (self.bytes, other.bytes) |a, b| {
            diff |= a ^ b;
        }
        return diff == 0;
    }
};

pub fn hashSHA256(data: []const u8) HashDigest {
    var digest: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return HashDigest{
        .algorithm = .sha256,
        .bytes = digest,
    };
}

pub fn hashBLAKE3(data: []const u8) HashDigest {
    var digest: [32]u8 = undefined;
    crypto.hash.Blake3.hash(data, &digest, .{});
    return HashDigest{
        .algorithm = .blake3,
        .bytes = digest,
    };
}

// ============================================================================
// 섹션 2: AEAD 암호화 (Authenticated Encryption with Associated Data)
// ============================================================================

pub const EncryptedData = struct {
    nonce: [12]u8,
    ciphertext: []u8,
    tag: [16]u8,
    allocator: Allocator,

    pub fn deinit(self: *EncryptedData) void {
        self.allocator.free(self.ciphertext);
    }

    pub fn clone(self: *const EncryptedData) !EncryptedData {
        return EncryptedData{
            .nonce = self.nonce,
            .ciphertext = try self.allocator.dupe(u8, self.ciphertext),
            .tag = self.tag,
            .allocator = self.allocator,
        };
    }
};

pub fn encryptAESGCM(
    allocator: Allocator,
    plaintext: []const u8,
    key: [32]u8,
    associated_data: []const u8,
) !EncryptedData {
    var nonce: [12]u8 = undefined;
    crypto.random.bytes(&nonce);

    var tag: [16]u8 = undefined;
    const ciphertext = try allocator.alloc(u8, plaintext.len);

    crypto.aead.aes_gcm.AES256GCM.encrypt(
        ciphertext,
        &tag,
        plaintext,
        associated_data,
        nonce,
        key,
    );

    return EncryptedData{
        .nonce = nonce,
        .ciphertext = ciphertext,
        .tag = tag,
        .allocator = allocator,
    };
}

pub fn decryptAESGCM(
    allocator: Allocator,
    encrypted: *const EncryptedData,
    key: [32]u8,
    associated_data: []const u8,
) ![]u8 {
    const plaintext = try allocator.alloc(u8, encrypted.ciphertext.len);

    crypto.aead.aes_gcm.AES256GCM.decrypt(
        plaintext,
        encrypted.ciphertext,
        encrypted.tag,
        associated_data,
        encrypted.nonce,
        key,
    ) catch {
        allocator.free(plaintext);
        return error.DecryptionFailed;
    };

    return plaintext;
}

// ============================================================================
// 섹션 3: 비대칭키 서명 (Ed25519 Signatures)
// ============================================================================

pub const KeyPair = struct {
    public_key: [32]u8,
    secret_key: [64]u8,

    pub fn generate() !KeyPair {
        const seed = crypto.random.int(u64);
        var seed_array: [32]u8 = undefined;
        std.mem.writeInt(u64, seed_array[0..8], seed, .little);
        std.mem.writeInt(u64, seed_array[8..16], seed, .little);
        std.mem.writeInt(u64, seed_array[16..24], seed, .little);
        std.mem.writeInt(u64, seed_array[24..32], seed, .little);

        const keypair = try crypto.sign.Ed25519.KeyPair.create(seed_array);

        return KeyPair{
            .public_key = keypair.public_key,
            .secret_key = keypair.secret_key,
        };
    }
};

pub const Signature = struct {
    bytes: [64]u8,

    pub fn format(self: Signature) [128]u8 {
        var result: [128]u8 = undefined;
        _ = std.fmt.bufPrintZ(&result, "{s}", .{std.fmt.fmtSliceHexLower(&self.bytes)}) catch unreachable;
        return result;
    }
};

pub fn signMessage(message: []const u8, secret_key: [64]u8) Signature {
    const sig = crypto.sign.Ed25519.sign(message, secret_key[0..32].*, crypto.sign.Ed25519.Options{});
    return Signature{ .bytes = sig };
}

pub fn verifySignature(message: []const u8, signature: Signature, public_key: [32]u8) bool {
    crypto.sign.Ed25519.verify(&signature.bytes, message, public_key) catch {
        return false;
    };
    return true;
}

// ============================================================================
// 섹션 4: 보안 메모리 관리 (Secure Zeroing)
// ============================================================================

pub const SecureBuffer = struct {
    data: [32]u8,

    pub fn init(value: [32]u8) SecureBuffer {
        return SecureBuffer{ .data = value };
    }

    pub fn zero(self: *SecureBuffer) void {
        crypto.utils.secureZero(u8, &self.data);
    }

    pub fn isZeroed(self: *const SecureBuffer) bool {
        for (self.data) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }
};

// ============================================================================
// 섹션 5: 인증 토큰 (Authentication Token)
// ============================================================================

pub const UserRole = enum {
    admin,
    user,
    guest,

    pub fn toString(self: UserRole) []const u8 {
        return switch (self) {
            .admin => "ADMIN",
            .user => "USER",
            .guest => "GUEST",
        };
    }

    pub fn canDelete(self: UserRole) bool {
        return self == .admin;
    }

    pub fn canRead(self: UserRole) bool {
        return self == .admin or self == .user;
    }
};

pub const AuthToken = struct {
    user_id: u32,
    username: []const u8,
    role: UserRole,
    created_at: u64,
    expires_at: u64,
    signature: Signature,

    pub fn format(self: *const AuthToken, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(
            allocator,
            "Token{{user_id={}, username={s}, role={s}, created={}, expires={}}}",
            .{
                self.user_id,
                self.username,
                self.role.toString(),
                self.created_at,
                self.expires_at,
            },
        );
    }

    pub fn isExpired(self: *const AuthToken, current_time: u64) bool {
        return current_time > self.expires_at;
    }
};

pub fn createToken(
    user_id: u32,
    username: []const u8,
    role: UserRole,
    secret_key: [64]u8,
    allocator: Allocator,
) !AuthToken {
    const now = std.time.timestamp();
    const token_str = try std.fmt.allocPrint(
        allocator,
        "{}-{s}-{}-{}",
        .{ user_id, username, now, @intFromEnum(role) },
    );
    defer allocator.free(token_str);

    const signature = signMessage(token_str, secret_key);

    return AuthToken{
        .user_id = user_id,
        .username = username,
        .role = role,
        .created_at = @intCast(now),
        .expires_at = @intCast(now + 3600), // 1시간
        .signature = signature,
    };
}

// ============================================================================
// 섹션 6: RBAC (Role-Based Access Control)
// ============================================================================

pub const Permission = enum(u8) {
    read = 1,
    write = 2,
    delete = 4,
    admin = 8,

    pub fn toString(self: Permission) []const u8 {
        return switch (self) {
            .read => "READ",
            .write => "WRITE",
            .delete => "DELETE",
            .admin => "ADMIN",
        };
    }
};

pub const AccessControl = struct {
    user_role: UserRole,
    permissions: u8,

    pub fn init(user_role: UserRole) AccessControl {
        const permissions = switch (user_role) {
            .admin => @intFromEnum(Permission.read) | @intFromEnum(Permission.write) | @intFromEnum(Permission.delete) | @intFromEnum(Permission.admin),
            .user => @intFromEnum(Permission.read) | @intFromEnum(Permission.write),
            .guest => @intFromEnum(Permission.read),
        };

        return AccessControl{
            .user_role = user_role,
            .permissions = permissions,
        };
    }

    pub fn canAccess(self: *const AccessControl, required: Permission) bool {
        return (self.permissions & @intFromEnum(required)) != 0;
    }

    pub fn assertAccess(self: *const AccessControl, required: Permission) !void {
        if (!self.canAccess(required)) {
            return error.PermissionDenied;
        }
    }
};

// ============================================================================
// 섹션 7: TLS 시뮬레이션 (TLS Simulation)
// ============================================================================

pub const TLSSession = struct {
    session_id: [16]u8,
    client_public_key: [32]u8,
    server_public_key: [32]u8,
    shared_secret: [32]u8,
    is_established: bool = false,

    pub fn init(allocator: Allocator) !TLSSession {
        var session_id: [16]u8 = undefined;
        crypto.random.bytes(&session_id);

        return TLSSession{
            .session_id = session_id,
            .client_public_key = undefined,
            .server_public_key = undefined,
            .shared_secret = undefined,
        };
    }

    pub fn performHandshake(self: *TLSSession) !void {
        // 클라이언트와 서버 키쌍 생성
        const client_keypair = try KeyPair.generate();
        const server_keypair = try KeyPair.generate();

        self.client_public_key = client_keypair.public_key;
        self.server_public_key = server_keypair.public_key;

        // 공유 비밀 생성 (간단한 XOR 기반)
        var shared: [32]u8 = undefined;
        for (self.client_public_key, self.server_public_key, &shared) |c, s, *sh| {
            sh.* = c ^ s;
        }
        self.shared_secret = shared;
        self.is_established = true;
    }
};

// ============================================================================
// 섹션 8: 비밀번호 검증 (Password Verification)
// ============================================================================

pub const PasswordValidator = struct {
    hash_algorithm: HashAlgorithm,

    pub fn init(algorithm: HashAlgorithm) PasswordValidator {
        return PasswordValidator{ .hash_algorithm = algorithm };
    }

    pub fn hash(self: *const PasswordValidator, password: []const u8) HashDigest {
        return switch (self.hash_algorithm) {
            .sha256 => hashSHA256(password),
            .blake3 => hashBLAKE3(password),
        };
    }

    pub fn verify(self: *const PasswordValidator, password: []const u8, stored_hash: *const HashDigest) bool {
        const computed_hash = self.hash(password);
        return computed_hash.equals(stored_hash);
    }
};

// ============================================================================
// 섹션 9: 메시지 서명 (Message Signing)
// ============================================================================

pub const SignedMessage = struct {
    message: []const u8,
    signature: Signature,
    public_key: [32]u8,
    signer_name: []const u8,
    timestamp: u64,

    pub fn verify(self: *const SignedMessage) bool {
        return verifySignature(self.message, self.signature, self.public_key);
    }

    pub fn format(self: *const SignedMessage, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(
            allocator,
            "SignedMessage{{signer={s}, message={s}, verified={}, timestamp={}}}",
            .{
                self.signer_name,
                self.message,
                self.verify(),
                self.timestamp,
            },
        );
    }
};

// ============================================================================
// 섹션 10: Assignment 2-6 - 테스트
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});
    try stdout.print("🎓 Zig 전공 201: Lesson 2-6 - 보안 및 암호화 설계\n", .{});
    try stdout.print("═══════════════════════════════════════════════════════════\n", .{});

    // Assignment 2-6: 1️⃣ 데이터 해싱 (SHA-256, BLAKE3)
    try stdout.print("\n1️⃣ 데이터 해싱:\n", .{});
    const password = "secure_password_123";
    const sha256_hash = hashSHA256(password);
    const blake3_hash = hashBLAKE3(password);

    var sha256_str: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&sha256_str, "{x}", .{std.fmt.fmtSliceHexLower(&sha256_hash.bytes)}) catch unreachable;
    try stdout.print("  비밀번호: {s}\n", .{password});
    try stdout.print("  SHA-256: {s}...\n", .{sha256_str[0..16]});

    var blake3_str: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&blake3_str, "{x}", .{std.fmt.fmtSliceHexLower(&blake3_hash.bytes)}) catch unreachable;
    try stdout.print("  BLAKE3: {s}...\n", .{blake3_str[0..16]});

    // Assignment 2-6: 2️⃣ 보안 삭제 (Secure Zeroing)
    try stdout.print("\n2️⃣ 보안 메모리 관리:\n", .{});
    var sensitive: SecureBuffer = undefined;
    std.mem.copy(u8, &sensitive.data, password[0..std.math.min(32, password.len)]);
    try stdout.print("  메모리 초기화 전: isZeroed = {}\n", .{sensitive.isZeroed()});
    sensitive.zero();
    try stdout.print("  메모리 초기화 후: isZeroed = {}\n", .{sensitive.isZeroed()});

    // Assignment 2-6: 3️⃣ 서명 생성 및 검증 (Ed25519)
    try stdout.print("\n3️⃣ 디지털 서명 (Ed25519):\n", .{});
    const keypair = try KeyPair.generate();
    const message = "이것은 중요한 메시지입니다";
    const signature = signMessage(message, keypair.secret_key);

    const is_valid = verifySignature(message, signature, keypair.public_key);
    try stdout.print("  메시지: {s}\n", .{message});
    try stdout.print("  서명 검증: {}\n", .{is_valid});

    // 잘못된 서명 테스트
    var wrong_signature = signature;
    wrong_signature.bytes[0] ^= 0xFF; // 서명 변조
    const is_wrong_valid = verifySignature(message, wrong_signature, keypair.public_key);
    try stdout.print("  변조된 서명 검증: {}\n", .{is_wrong_valid});

    // Assignment 2-6: 4️⃣ 인증 토큰 생성
    try stdout.print("\n4️⃣ 인증 토큰 생성:\n", .{});
    const token = try createToken(1001, "admin_user", .admin, keypair.secret_key, allocator);
    const token_str = try token.format(allocator);
    defer allocator.free(token_str);
    try stdout.print("  {s}\n", .{token_str});

    // Assignment 2-6: 5️⃣ RBAC (Role-Based Access Control)
    try stdout.print("\n5️⃣ 접근 제어 (RBAC):\n", .{});
    var admin_ac = AccessControl.init(.admin);
    var user_ac = AccessControl.init(.user);
    var guest_ac = AccessControl.init(.guest);

    try stdout.print("  Admin - READ: {}, WRITE: {}, DELETE: {}\n", .{
        admin_ac.canAccess(.read),
        admin_ac.canAccess(.write),
        admin_ac.canAccess(.delete),
    });
    try stdout.print("  User  - READ: {}, WRITE: {}, DELETE: {}\n", .{
        user_ac.canAccess(.read),
        user_ac.canAccess(.write),
        user_ac.canAccess(.delete),
    });
    try stdout.print("  Guest - READ: {}, WRITE: {}, DELETE: {}\n", .{
        guest_ac.canAccess(.read),
        guest_ac.canAccess(.write),
        guest_ac.canAccess(.delete),
    });

    // Assignment 2-6: 6️⃣ TLS 핸드셰이크 시뮬레이션
    try stdout.print("\n6️⃣ TLS 핸드셰이크 시뮬레이션:\n", .{});
    var tls_session = try TLSSession.init(allocator);
    try tls_session.performHandshake();
    try stdout.print("  세션 ID: ", .{});
    for (tls_session.session_id[0..4]) |byte| {
        try stdout.print("{x:0>2}", .{byte});
    }
    try stdout.print("...\n", .{});
    try stdout.print("  핸드셰이크 완료: {}\n", .{tls_session.is_established});

    // Assignment 2-6: 7️⃣ AEAD 암호화 (AES-GCM)
    try stdout.print("\n7️⃣ AEAD 암호화 (AES-GCM):\n", .{});
    var key: [32]u8 = undefined;
    crypto.random.bytes(&key);
    const plaintext = "기밀 정보: 직원 급여 데이터";
    const associated_data = "metadata";

    var encrypted = try encryptAESGCM(allocator, plaintext, key, associated_data);
    defer encrypted.deinit();

    try stdout.print("  평문: {s}\n", .{plaintext});
    try stdout.print("  암호화됨: 길이 {}\n", .{encrypted.ciphertext.len});

    const decrypted = try decryptAESGCM(allocator, &encrypted, key, associated_data);
    defer allocator.free(decrypted);
    try stdout.print("  복호화됨: {s}\n", .{decrypted});

    // Assignment 2-6: 8️⃣ 비밀번호 검증
    try stdout.print("\n8️⃣ 비밀번호 검증:\n", .{});
    const validator = PasswordValidator.init(.sha256);
    const stored_hash = validator.hash("my_password");

    const correct_verify = validator.verify("my_password", &stored_hash);
    const wrong_verify = validator.verify("wrong_password", &stored_hash);

    try stdout.print("  정확한 비밀번호 검증: {}\n", .{correct_verify});
    try stdout.print("  틀린 비밀번호 검증: {}\n", .{wrong_verify});

    // Assignment 2-6: 9️⃣ 메시지 서명
    try stdout.print("\n9️⃣ 메시지 서명:\n", .{});
    const signed_message = SignedMessage{
        .message = "이 메시지는 검증 가능합니다",
        .signature = signature,
        .public_key = keypair.public_key,
        .signer_name = "Security Officer",
        .timestamp = @intCast(std.time.timestamp()),
    };

    const signed_str = try signed_message.format(allocator);
    defer allocator.free(signed_str);
    try stdout.print("  {s}\n", .{signed_str});

    try stdout.print("\n✅ Assignment 2-6 완성!\n", .{});
    try stdout.print("조작된 기록은 결코 통과할 수 없음을 증명했습니다.\n", .{});
    try stdout.print("신뢰의 방패 - 보안이 강화되었습니다.\n", .{});
}

// ============================================================================
// 테스트
// ============================================================================

test "Hash digest constant-time comparison" {
    const hash1 = hashSHA256("test");
    const hash2 = hashSHA256("test");
    const hash3 = hashSHA256("different");

    try testing.expect(hash1.equals(&hash2));
    try testing.expect(!hash1.equals(&hash3));
}

test "Secure buffer zeroing" {
    var buffer = SecureBuffer.init([_]u8{42} ** 32);
    try testing.expect(!buffer.isZeroed());

    buffer.zero();
    try testing.expect(buffer.isZeroed());
}

test "Ed25519 signature generation and verification" {
    const keypair = try KeyPair.generate();
    const message = "test message";
    const signature = signMessage(message, keypair.secret_key);

    try testing.expect(verifySignature(message, signature, keypair.public_key));
}

test "Ed25519 signature tampering detection" {
    const keypair = try KeyPair.generate();
    const message = "test message";
    var signature = signMessage(message, keypair.secret_key);

    // Tamper with signature
    signature.bytes[0] ^= 0xFF;

    try testing.expect(!verifySignature(message, signature, keypair.public_key));
}

test "Password validation" {
    const validator = PasswordValidator.init(.sha256);
    const password = "secure_password";
    const hash = validator.hash(password);

    try testing.expect(validator.verify(password, &hash));
    try testing.expect(!validator.verify("wrong_password", &hash));
}

test "RBAC permissions" {
    var admin_ac = AccessControl.init(.admin);
    var user_ac = AccessControl.init(.user);
    var guest_ac = AccessControl.init(.guest);

    try testing.expect(admin_ac.canAccess(.delete));
    try testing.expect(!user_ac.canAccess(.delete));
    try testing.expect(!guest_ac.canAccess(.write));
}

test "Auth token expiration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keypair = try KeyPair.generate();
    const token = try createToken(1, "user", .user, keypair.secret_key, allocator);

    const now = @as(u64, @intCast(std.time.timestamp()));
    try testing.expect(!token.isExpired(now));
    try testing.expect(token.isExpired(now + 7200)); // 2 hours later
}

test "TLS session establishment" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var session = try TLSSession.init(allocator);
    try testing.expect(!session.is_established);

    try session.performHandshake();
    try testing.expect(session.is_established);
}

test "AES-GCM encryption and decryption" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var key: [32]u8 = undefined;
    crypto.random.bytes(&key);

    const plaintext = "secret message";
    const associated_data = "metadata";

    var encrypted = try encryptAESGCM(allocator, plaintext, key, associated_data);
    defer encrypted.deinit();

    const decrypted = try decryptAESGCM(allocator, &encrypted, key, associated_data);
    defer allocator.free(decrypted);

    try testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "Hash algorithm selection" {
    const sha256_hash = hashSHA256("test");
    const blake3_hash = hashBLAKE3("test");

    try testing.expect(sha256_hash.algorithm == .sha256);
    try testing.expect(blake3_hash.algorithm == .blake3);
}

test "Role permissions hierarchy" {
    const admin = UserRole.admin;
    const user = UserRole.user;
    const guest = UserRole.guest;

    try testing.expect(admin.canDelete());
    try testing.expect(!user.canDelete());
    try testing.expect(!guest.canDelete());
    try testing.expect(admin.canRead());
    try testing.expect(user.canRead());
    try testing.expect(guest.canRead());
}
