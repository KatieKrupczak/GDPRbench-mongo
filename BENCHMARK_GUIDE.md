# GDPR Benchmark Guide for MongoDB

This guide explains how to run GDPR workloads with and without audit logging enabled on MongoDB.

## Prerequisites

1. **MongoDB installed** (Community or Enterprise Edition)
2. **Java 8+** and **Maven 3** installed
3. Project built: `cd src && mvn clean package`

## Important: MongoDB Editions

- **MongoDB Enterprise**: Has native audit logging support via `auditLog` config
- **MongoDB Community**: Uses operation profiling as an alternative (logs to `system.profile` collection)

## Quick Start

### 1. Build the project

```bash
cd src
mvn clean package
```

### 2. Start MongoDB

**With audit logging (or profiling):**
```bash
./scripts/start-mongo.sh audit
```

**Without audit logging:**
```bash
./scripts/start-mongo.sh noaudit
```

### 3. Run a benchmark

```bash
# Load data first
./scripts/run-benchmark.sh audit gdpr_customer load

# Run the workload
./scripts/run-benchmark.sh audit gdpr_customer run
```

### 4. Stop MongoDB
```bash
./scripts/stop-mongo.sh
```

## Manual Setup (Alternative)

### Starting MongoDB Manually

**With audit logging (Enterprise) / profiling (Community):**
```bash
mkdir -p data/db-audit logs
mongod --config configs/mongod-log.yaml
```

**Without audit logging:**
```bash
mkdir -p data/db-noaudit logs
mongod --config configs/mongod-nolog.yaml
```

### Running Workloads Manually

```bash
cd src

# Load phase - creates initial data
./bin/ycsb.sh load mongodb -s -P workloads/gdpr_customer \
    -p mongodb.url="mongodb://localhost:27017/ycsb?w=1"

# Run phase - executes the workload
./bin/ycsb.sh run mongodb -s -P workloads/gdpr_customer \
    -p mongodb.url="mongodb://localhost:27017/ycsb?w=1"
```

## Configuration Options

### MongoDB Connection Properties

| Property | Description | Default |
|----------|-------------|---------|
| `mongodb.url` | MongoDB connection URL | `mongodb://localhost:27017/ycsb?w=1` |
| `mongodb.auditlog.path` | Path to audit log file (for readLog) | None |
| `mongodb.cleanup.interval` | TTL cleanup interval in seconds | 60 |
| `mongodb.upsert` | Use upserts instead of inserts | false |
| `batchsize` | Batch size for inserts | 1 |

### Example with audit log reading:
```bash
./bin/ycsb.sh run mongodb -s -P workloads/gdpr_customer \
    -p mongodb.url="mongodb://localhost:27017/ycsb?w=1" \
    -p mongodb.auditlog.path="/path/to/GDPRbench-mongo/logs/audit.json"
```

## Available Workloads

| Workload | Description |
|----------|-------------|
| `gdpr_customer` | Customer role operations (reads, updates, deletes) |
| `gdpr_controller` | Controller role (metadata updates, inserts, deletes) |
| `gdpr_processor` | Processor role operations |
| `workloada-f` | Standard YCSB workloads |

## Comparing Results

To compare performance with/without audit logging:

1. Run with audit:
```bash
./scripts/start-mongo.sh audit
./scripts/run-benchmark.sh audit gdpr_customer load
./scripts/run-benchmark.sh audit gdpr_customer run
./scripts/stop-mongo.sh
```

2. Run without audit:
```bash
./scripts/start-mongo.sh noaudit
./scripts/run-benchmark.sh noaudit gdpr_customer load
./scripts/run-benchmark.sh noaudit gdpr_customer run
./scripts/stop-mongo.sh
```

3. Compare results in `results/audit/` vs `results/noaudit/`

## Audit Logging Details

### MongoDB Enterprise
Uses native audit logging configured in `configs/mongod-log.yaml`:
- Logs to `logs/audit.json`
- Filters: authenticate, createCollection, createIndex, insert, update, delete, find, query, getMore

### MongoDB Community (Profiling Alternative)
Uses operation profiling configured in `configs/mongod-log.yaml`:
- Logs to `system.profile` collection
- `mode: all` logs every operation
- `slowOpThresholdMs: 0` ensures all ops are captured

To query profiling data:
```javascript
db.system.profile.find().sort({ts: -1}).limit(10)
```

## Verifying Audit Logging

### Check audit log file (Enterprise):
```bash
tail -f logs/audit.json
```

### Check profiling (Community):
```javascript
// In mongosh
db.setProfilingLevel(2)  // Enable if not already
db.system.profile.find().sort({ts: -1}).limit(10)
```

## Directory Structure

```
GDPRbench-mongo/
├── configs/
│   ├── mongod-log.yaml      # Config WITH audit/profiling
│   └── mongod-nolog.yaml    # Config WITHOUT audit/profiling
├── scripts/
│   ├── start-mongo.sh       # Start MongoDB
│   ├── stop-mongo.sh        # Stop MongoDB
│   └── run-benchmark.sh     # Run benchmarks
├── logs/                     # Log files (created at runtime)
├── data/                     # Database files (created at runtime)
├── results/                  # Benchmark results (created at runtime)
│   ├── audit/
│   └── noaudit/
└── src/
    ├── workloads/           # Workload configurations
    └── mongodb/             # MongoDB client code
```
