#!/bin/bash
# Run all YCSB workloads (a-f) under multiple GDPR feature configurations:
#   - Baseline (no audit, no encryption, no TTL)
#   - Audit only
#   - Encryption only (LUKS at rest + TLS in transit)
#   - TTL only  (hooked for future TTL implementation)
#   - All features (audit + encryption + TTL)
#
# Outputs throughput results to a CSV file.
#
# Usage: ./run-all-workloads.sh [iterations]
#   iterations: number of times to run each workload (default: 1)
#               if > 1, reports average throughput and raw per-run values.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"

# Default (unencrypted) data directory; may be overridden by LUKS mount
DEFAULT_DATA_DIR="$PROJECT_ROOT/data/db-benchmark"
DATA_DIR="$DEFAULT_DATA_DIR"

LOG_DIR="$PROJECT_ROOT/logs"

RESULTS_DIR="$PROJECT_ROOT/results"
RESULTS_FILE="$RESULTS_DIR/throughput_results.csv"
RAW_RESULTS_FILE="$RESULTS_DIR/throughput_raw.csv"

# LUKS paths for encryption-at-rest
LUKS_DIR="$PROJECT_ROOT/.luks"
LUKS_MOUNT="$LUKS_DIR/mnt"
LUKS_IMG="$LUKS_DIR/mongo.img"
LUKS_NAME="mongo_luks"

# TLS cert for encryption-in-transit (created by scripts/setup-tls.sh)
TLS_DIR="$PROJECT_ROOT/certs"
TLS_PEM="$TLS_DIR/server.pem"

WORKLOADS="a b c d e f"

# Number of iterations (default 1, can be overridden via command line)
ITERATIONS=${1:-1}

# Feature Flags for current config (booleans as strings)
AUDIT_ENABLED=false
ENCRYPTION_ENABLED=false
TTL_ENABLED=false   # Placeholder for future TTL implementation

# MongoDB connection URL
MONGO_URL="mongodb://localhost:27017/ycsb?w=1"



# ----------------------------------------
# Helper: map config name -> feature flags
# ----------------------------------------
# Config names:
#   baseline   -> audit=off, encryption=off, ttl=off
#   audit      -> audit=on,  encryption=off, ttl=off
#   encryption -> audit=off, encryption=on,  ttl=off
#   ttl        -> audit=off, encryption=off, ttl=on
#   all        -> audit=on,  encryption=on,  ttl=on
apply_feature_config() {
    local config=$1

    case $config in
        baseline)
            AUDIT_ENABLED=false
            ENCRYPTION_ENABLED=false
            TTL_ENABLED=false
            ;;
        audit)
            AUDIT_ENABLED=true
            ENCRYPTION_ENABLED=false
            TTL_ENABLED=false
            ;;
        encryption)
            AUDIT_ENABLED=false
            ENCRYPTION_ENABLED=true
            TTL_ENABLED=false
            ;;
        ttl)
            AUDIT_ENABLED=false
            ENCRYPTION_ENABLED=false
            TTL_ENABLED=true
            ;;
        all)
            AUDIT_ENABLED=true
            ENCRYPTION_ENABLED=true
            TTL_ENABLED=true
            ;;
        *)
            echo "Unknown feature config: $config" >&2 #XXX
            exit 1
            ;;
    esac

    # Set Mongo URL based on encryption flag
    if [ "$ENCRYPTION_ENABLED" = true ]; then
        MONGO_URL="mongodb://localhost:27017/ycsb?w=1&tls=true&tlsInsecure=true"
    else
        MONGO_URL="mongodb://localhost:27017/ycsb?w=1"
    fi
}

# ----------------------------------------
# MongoDB management
# ----------------------------------------

# Function to start MongoDB
start_mongo() {
    echo "Starting MongoDB..."

    # Base command: dbPath + logpath
    local cmd=(mongod --dbpath "$DATA_DIR" --logpath "$LOG_DIR/mongod.log" --fork --quiet)

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        # Ensure TLS cert exists
        if [ ! -f "$TLS_PEM" ]; then
            echo "[tls] TLS PEM not found at $TLS_PEM"
            echo "      Run: ./scripts/setup-tls.sh"
            exit 1
        fi

        echo "[mongo] Starting with TLS (requireTLS) and encrypted dbPath=$DATA_DIR"
        cmd+=( --tlsMode requireTLS
               --tlsCertificateKeyFile "$TLS_PEM"
               --tlsAllowInvalidCertificates
               --tlsAllowInvalidHostnames )
    else
        echo "[mongo] Starting without TLS (unencrypted in transit), dbPath=$DATA_DIR"
    fi


    "${cmd[@]}" 2>/dev/null
    sleep 2
}

# Function to stop MongoDB
stop_mongo() {
    echo "Stopping MongoDB..."
    mongosh --quiet --eval "db.adminCommand({shutdown: 1})" 2>/dev/null || true
    sleep 2
}

# Function to enable/disable audit (profiling) logging
set_profiling() {
    local level=$1
    mongosh --quiet --eval "db.getSiblingDB('ycsb').setProfilingLevel($level)" 2>/dev/null
}

# Function to clean database
clean_db() {
    mongosh --quiet --eval "db.getSiblingDB('ycsb').dropDatabase()" 2>/dev/null
}

# ADD TTL HOOKS HERE IF NEEDED
enable_ttl() {
    # TODO: implement TTL indexes / policies for GDPR TTL experiment
    # Example placeholder:
    # mongosh --quiet --eval "db.getSiblingDB('ycsb').collection.createIndex({expireAt:1},{expireAfterSeconds:0})"
    echo "[ttl] TTL feature ENABLED (hook - implement TTL indexes here)"
}

disable_ttl() {
    # TODO: disable TTL behavior if needed (drop TTL indexes, etc.)
    echo "[ttl] TTL feature DISABLED (hook - clean up TTL config here)"
}

# ----------------------------------------
# Run one YCSB iteration for a workload
# ----------------------------------------
# Function to run a single iteration and return throughput
run_single_iteration() {
    local workload=$1

    # Load phase
    cd "$SRC_DIR"
    ./bin/ycsb.sh load mongodb -P "workloads/workload$workload" \
        -p mongodb.url="$MONGO_URL" 2>&1 | grep -q "Return=OK" || true

    # Run phase and capture throughput
    local output=$(./bin/ycsb.sh run mongodb -P "workloads/workload$workload" \
        -p mongodb.url="$MONGO_URL" 2>&1)

    local throughput=$(echo "$output" | grep "\[OVERALL\], Throughput" | awk -F', ' '{print $3}')

    if [ -z "$throughput" ]; then
        echo "0"
    else
        echo "$throughput"
    fi
}

# ----------------------------------------
# Run workload (multiple iterations) under current feature config
# ----------------------------------------
# Function to run a workload with multiple iterations
run_workload() {
    local workload=$1
    local config_name=$2

    local audit_val="$AUDIT_ENABLED"
    local encryption_val="$ENCRYPTION_ENABLED"
    local ttl_val="$TTL_ENABLED"

    echo "  Running workload$workload [config=$config_name, audit=$audit_val, enc=$encryption_val, ttl=$ttl_val]..."

    local sum=0
    local count=0

    for ((i=1; i<=ITERATIONS; i++)); do
        if [ "$ITERATIONS" -gt 1 ]; then
            echo "    Iteration $i/$ITERATIONS..."
        fi

        clean_db

        # If audit enabled, reset profile collection
        if [ "$AUDIT_ENABLED" = true ]; then
            mongosh --quiet --eval "db.getSiblingDB('ycsb').system.profile.drop()" 2>/dev/null || true
            set_profiling 2
        else
            set_profiling 0
        fi

        local throughput=$(run_single_iteration "$workload")

        if [ "$throughput" != "0" ]; then
            sum=$(echo "$sum + $throughput" | bc)
            count=$((count + 1))

            if [ "$ITERATIONS" -gt 1 ]; then
                echo "$workload,$config_name,$audit_val,$encryption_val,$ttl_val,$i,$throughput" >> "$RAW_RESULTS_FILE"
                echo "      Throughput: $throughput ops/sec"
            fi
        fi
    done

    # Calculate average
    local avg_throughput
    if [ "$count" -gt 0 ]; then
        avg_throughput=$(echo "scale=2; $sum / $count" | bc)
    else
        avg_throughput="ERROR"
    fi

    echo "$workload,$config_name,$audit_val,$encryption_val,$ttl_val,$avg_throughput" >> "$RESULTS_FILE"

    if [ "$ITERATIONS" -gt 1 ]; then
        echo "    Average: $avg_throughput ops/sec (from $count runs)"
    else
        echo "    Throughput: $avg_throughput ops/sec"
    fi
}

# Main execution
echo "=========================================="
echo "GDPR Benchmark - All Workloads"
echo "=========================================="
echo "Iterations per workload: $ITERATIONS"
echo ""

# Create directories
mkdir -p "$DEFAULT_DATA_DIR" "$LOG_DIR" "$RESULTS_DIR"

# Initialize results files
echo "workload,config,audit,encryption,ttl,throughput_ops_sec" > "$RESULTS_FILE"
if [ "$ITERATIONS" -gt 1 ]; then
    echo "workload,config,audit,encryption,ttl,iteration,throughput_ops_sec" > "$RAW_RESULTS_FILE"
fi

# Check if MongoDB is already running, stop it
if pgrep -x mongod > /dev/null; then
    stop_mongo
fi

# Configurations to run
#CONFIGS=("baseline" "audit" "encryption" "ttl" "all") # Full set
CONFIGS=("baseline" "audit" "encryption" ) # Implemented set

for config in "${CONFIGS[@]}"; do
    echo "------------------------------------------"
    echo "Feature Configuration: $config"
    echo "------------------------------------------"

    # Apply feature flags
    apply_feature_config "$config"

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        mkdir -p "$LUKS_DIR" "$LUKS_MOUNT"

        # If the LUKS image doesn't exist yet, create it once
        if [ ! -f "$LUKS_IMG" ]; then
            echo "[luks] Image not found at $LUKS_IMG – creating it via luks-create.sh..."
            "$SCRIPT_DIR/luks-create.sh"
        fi

        # Ensure LUKS is mounted
        if ! mountpoint -q "$LUKS_MOUNT"; then
            echo "[luks] Mounting LUKS volume for encryption-at-rest..."
            "$SCRIPT_DIR/luks-open.sh"
        fi
        
        DATA_DIR="$LUKS_MOUNT"
    else
        # Use default unencrypted data dir
        DATA_DIR="$DEFAULT_DATA_DIR"
    fi

    # Handle TTL setup/teardown
    if [ "$TTL_ENABLED" = true ]; then
        enable_ttl
    else
        disable_ttl
    fi

    # Start MongoDB with current config
    start_mongo

    if [ "$TTL_ENABLED" = true ]; then
        echo "[ttl] TTL is ENABLED for this config." # call enable_ttl() here
    else
        echo "[ttl] TTL is DISABLED for this config." # call disable_ttl() here
    fi

    # Run all workloads under current config
    for w in $WORKLOADS; do
        run_workload "$w" "$config"
    done

    stop_mongo

    # Unmount LUKS if used
    if [ "$ENCRYPTION_ENABLED" = true ]; then
        echo "[luks] Unmounting LUKS volume..."
        ./scripts/luks-close.sh
    fi 
done

echo ""
echo "=========================================="
echo "Results saved to: $RESULTS_FILE"
if [ "$ITERATIONS" -gt 1 ]; then
    echo "Raw results saved to: $RAW_RESULTS_FILE"
fi
echo "=========================================="
echo ""
echo "Summary (average throughput in ops/sec):"
echo ""
cat "$RESULTS_FILE"
