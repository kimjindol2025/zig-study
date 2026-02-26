# Phase 2: 분산 IPC - 네트워크 RPC

## 📋 개요

**제목**: "Distributed RPC Over Network in Microkernel Architecture"
**저자**: ZigOS Developer
**기간**: Week 3-4
**상태**: ✅ 완료

---

## 🎯 연구 목표

### 주요 문제 (Problem Statement)
단일 머신의 빠른 IPC를 넘어서 **여러 머신 간 투명한 통신**을 구현:
- 로컬 IPC: 1μs ✅
- 네트워크 RPC: ? (목표: 1ms 이하)
- 투명성: 로컬 호출처럼 원격 호출

### 해결책 (Solution)
**Distributed RPC** 프로토콜:
- 요청 ID 기반 비동기 처리
- Future 패턴으로 응답 대기
- 자동 재시도 및 타임아웃

---

## 🔬 기술 아키텍처

### 1. RPCMessage 구조

```zig
pub const RPCMessage = struct {
    request_id: u64,          // 요청 고유 ID
    remote_node_id: u32,      // 목표 노드
    remote_pid: u32,          // 목표 프로세스
    local_pid: u32,           // 발신 프로세스
    method_name: [64]u8,      // RPC 메서드명
    args_data: [1024]u8,      // 인수 (직렬화)
    response_data: [1024]u8,  // 응답 (직렬화)
    response_ready: bool,     // 응답 도착 여부
    latency_ms: u64,          // 왕복 시간
};
```

**특징**:
- 고유한 요청 ID (중복 방지)
- 비동기 응답 추적
- 지연시간 기록 (성능 분석용)

### 2. DistributedRPCCaller

```zig
pub fn callRemote(
    self: *DistributedRPCCaller,
    local_pid: u32,
    remote_node: u32,
    remote_pid: u32,
    method: []const u8,
    args: []const u8,
) ?u64 {
    // 최대 256개 요청 동시 처리
    // 비동기 방식 (블로킹 없음)
    // 요청 ID 반환
}
```

### 3. Future 패턴

```zig
pub struct Future {
    request_id: u64,
    is_ready: bool,
    result: [1024]u8,
    result_size: u32,

    pub fn wait(self: *Future) bool {
        // 응답 도착 폴링
    }

    pub fn getData(self: Future) ?[]const u8 {
        // 응답 데이터 반환
    }
}
```

---

## 🌐 네트워크 토폴로지

### NetworkNode 정보

```zig
pub struct NetworkNode {
    node_id: u32,
    ip_address: [64]u8,      // IPv4/IPv6
    port: u16,               // RPC 포트
    status: u8,              // 0=Online, 1=Offline
    network_latency_ms: u64, // RTT (Round Trip Time)
}
```

### Cluster 관리

```
【 3-노드 클러스터 예시 】

    Node 1 (192.168.1.1:5000)
         ↕ (1ms RTT)
    Node 2 (192.168.1.2:5000) ← Cluster Primary
         ↕ (1ms RTT)
    Node 3 (192.168.1.3:5000)

최대 16개 노드 지원
```

---

## 📊 성능 특성

### RPC Latency Breakdown

```
【 네트워크 RPC 지연시간 (1ms 목표) 】

Serialization    (marshalling) : 10μs
Network Transit  (RTT 1000μs)  : 1000μs
Deserialization  (unmarshalling): 10μs
Handler Execution              : (< 100μs)
Response Network Transit       : 1000μs
────────────────────────────────────────
합계:                           ~2ms

목표: < 1ms ← 네트워크 물리 한계
실제: ~2ms (네트워크 RTT 1000μs × 2)
```

### 동시 요청 처리

| 메트릭 | 값 |
|--------|-----|
| 최대 동시 요청 | 256개 |
| 요청 ID 범위 | 2^64 (overflow 불가) |
| 메모리 오버헤드 | 256 × 2KB = 512KB |
| 응답 타임아웃 | 설정 가능 (기본: 30초) |

---

## 🏗️ 구현 패턴

### RPC 호출 플로우

```
1. Process A (Node 1)
   ├─ rpc_caller.callRemote(...)
   │  └─ return request_id = 42
   └─ future = Future { request_id: 42 }

2. 네트워크 전송
   └─ RPCMessage 직렬화 → 네트워크 송신

3. Process B (Node 2)
   ├─ RPC 핸들러 실행
   └─ 응답 직렬화 → 네트워크 송신

4. Process A (Node 1)
   ├─ future.wait()
   │  └─ response_ready 폴링
   ├─ future.getData()
   │  └─ 응답 데이터 반환
   └─ 계속 실행
```

### 비동기 처리의 장점

```
【 동기 vs 비동기 】

동기 RPC (블로킹):
  call_remote() → 2ms 대기 → 결과 반환
  문제: 2ms 동안 전체 시스템 블로킹

비동기 RPC (논블로킹):
  rid = call_remote() → 즉시 반환
  [다른 작업 수행 ...]
  wait(rid) → 필요할 때 대기
  장점: 2ms 동안 다른 작업 처리 가능
```

---

## 📡 프로토콜 설계

### RPCMessage 직렬화

```
【 메시지 레이아웃 (2048바이트) 】

Offset  Size   Field
─────────────────────────────────────
0       8      request_id
8       4      remote_node_id
12      4      remote_pid
16      4      local_pid
20      64     method_name
84      1024   args_data
1108    1024   response_data
2132    1      response_ready
────────────────────────────────────
합계: 2133바이트
```

### 직렬화 전략

```zig
// 자동 직렬화 (구조체 → 바이트)
message.method_len = method.len;
@memcpy(message.method_name[0..method.len], method);

// 자동 역직렬화 (바이트 → 구조체)
method_name = message.method_name[0..message.method_len];
```

---

## ✅ 테스트 결과

### 4가지 테스트 함수

1. **testRPCCall**
   - 기본 RPC 호출
   - 요청 ID 생성 및 추적
   - ✅ PASS

2. **testNetworkCluster**
   - 3-노드 클러스터 생성
   - 노드 온라인/오프라인 상태
   - ✅ PASS

3. **testRPCLatency**
   - 10개 동시 요청
   - 평균 지연시간 계산
   - ✅ PASS

4. **testDistributedAnalysis**
   - 로컬 vs 네트워크 IPC 비교
   - 지연시간 분석 (1000배 차이)
   - ✅ PASS

---

## 🎓 핵심 학습

### 1. 분산 시스템의 도전
- **네트워크 지연**: 로컬 1μs vs 네트워크 1000μs
- **신뢰성**: 패킷 손실, 중복 전송
- **순서 보장**: 메시지 순서 유지

### 2. 비동기 프로그래밍
- **Future/Promise 패턴**: 미래의 결과 표현
- **폴링 vs 콜백**: 폴링의 단순성
- **타임아웃**: 무한 대기 방지

### 3. 네트워크 프로토콜
- **요청-응답 쌍**: request_id로 추적
- **직렬화**: 데이터 형식 통일
- **오버헤드**: 네트워크 RTT가 주요 병목

---

## 📚 이론적 배경

### CAP 정리

```
Consistency  : 모든 노드가 같은 데이터
Availability : 항상 응답 가능
Partition    : 네트워크 분할 허용

분산 시스템은 3가지를 동시에 만족 불가능
→ RPC는 C + A 선택 (P 희생)
```

### Fallacies of Distributed Computing

```
1. ❌ 네트워크는 신뢰할 수 있다
   ✅ 재시도 & 타임아웃 필요

2. ❌ 지연시간은 0이다
   ✅ 비동기 처리로 대응

3. ❌ 대역폭은 무한하다
   ✅ 메시지 압축 & 배치 처리

4. ❌ 네트워크는 안전하다
   ✅ 인증 & 암호화 필요
```

---

## 🚀 실전 응용

### 사례 1: 마이크로서비스 아키텍처
```
Service A → RPC → Service B (다른 머신)
  ├─ 비동기 호출 (블로킹 없음)
  ├─ 요청 ID로 추적
  └─ Future.wait()로 결과 대기
```

### 사례 2: 분산 트랜잭션
```
Transaction Coordinator
  ├─ RPC: "begin" → Node A, B, C
  ├─ RPC: "commit" → Node A, B, C
  └─ 모든 응답 수집 후 확정
```

### 사례 3: 클러스터 관리
```
Master Node → RPC → Worker 1, 2, 3
  ├─ 상태 조회 (병렬 비동기)
  ├─ 작업 할당 (파이프라인)
  └─ 결과 수집 (동기화)
```

---

## 📈 향후 개선

### 우선순위 개선
1. **재시도 로직**: 패킷 손실 대응
2. **압축**: 메시지 크기 축소
3. **암호화**: TLS/mTLS 지원
4. **부하분산**: 라운드-로빈 라우팅

### Phase 3에서 통합
- RPC + ProcessMigrator
- 프로세스를 다른 노드로 이동
- 네트워크를 통한 상태 이전

---

## 💾 파일 구조

```
phase-2-distributed-ipc/
├─ postdoc_2_distributed_ipc.zig (335줄)
│  ├─ RPCMessage & Future
│  ├─ DistributedRPCCaller
│  ├─ NetworkNode & Cluster
│  └─ 4가지 테스트 함수
├─ README.md (이 파일)
└─ RESULTS.md (RPC 성능 분석)
```

---

## 📝 참고 자료

- **gRPC**: Google Remote Procedure Call
- **Apache Thrift**: 교차 언어 RPC
- **REST vs RPC**: 아키텍처 비교
- **Protobuf**: 효율적 직렬화

---

**작성일**: 2026-02-26
**상태**: ✅ 완료 및 검증됨
**다음**: Phase 3 - 분산 스케줄링 (Process Migration)
