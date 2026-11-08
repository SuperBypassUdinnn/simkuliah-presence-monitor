# simkuliah-presence-monitor Architecture & System Design

## 1. Overview
High-level system topology, domain boundaries, and data flow specifications.

- **Mode**: `monorepo`
- **Active Stacks**: `python, flutter`
- **Database Architecture**: `postgres`
- **Infrastructure Architecture**: `docker`

## 2. High-Level Component Topology

```text
[ Client Layer (Web/Mobile/CLI) ]
               │
               ▼ HTTP / WebSocket
[ API Gateway / Reverse Proxy ]
               │
               ▼
[ Core Application Services ]
         │            │
         ▼            ▼
[ Cache / Session ] [ Persistent Database ]
```

## 3. Cross-Cutting Invariants
1. **Unified Response Envelope**:
   ```json
   {
     "code": 200,
     "message": "Operation completed successfully",
     "data": {}
   }
   ```
2. **Standardized Error Envelope**:
   ```json
   {
     "code": "ERR_INVALID_INPUT",
     "message": "Localized human-readable error description"
   }
   ```
3. **Strict Domain Layer Separation**:
   - Entities and domain logic do not depend on external frameworks.
   - Adapters handle transport-specific protocols (HTTP, gRPC, CLI).
