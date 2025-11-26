#!/bin/bash
# Run all YCSB workloads (a-f) with and without audit logging
# Outputs throughput results to a CSV file
#
# Usage: ./run-all-workloads.sh [iterations]
#   iterations: number of times to run each workload (default: 1)
#               if > 1, reports average throughput

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"

DATA_DIR="$PROJECT_ROOT/data/db-benchmark"
LOG_DIR="$PROJECT_ROOT/logs"
RESULTS_FILE="$PROJECT_ROOT/results/throughput_results.csv"
RAW_RESULTS_FILE="$PROJECT_ROOT/results/throughput_raw.csv"

MONGO_URL="mongodb://localhost:27017/ycsb?w=1"
WORKLOADS="a b c d e f"

# Number of iterations (default 1, can be overridden via command line)
ITERATIONS=${1:-1}

# Create directories
mkdir -p "$DATA_DIR" "$LOG_DIR" "$PROJECT_ROOT/results"

# Initialize results files
echo "workload,audit_logging,throughput_ops_sec" > "$RESULTS_FILE"
if [ "$ITERATIONS" -gt 1 ]; then
    echo "workload,audit_logging,iteration,throughput_ops_sec" > "$RAW_RESULTS_FILE"
fi

# Function to start MongoDB
start_mongo() {
    echo "Starting MongoDB..."
    mongod --dbpath "$DATA_DIR" --logpath "$LOG_DIR/mongod.log" --fork --quiet 2>/dev/null
    sleep 2
}

# Function to stop MongoDB
stop_mongo() {
    echo "Stopping MongoDB..."
    mongosh --quiet --eval "db.adminCommand({shutdown: 1})" 2>/dev/null || true
    sleep 2
}

# Function to enable/disable profiling
set_profiling() {
    local level=$1
    mongosh --quiet --eval "db.getSiblingDB('ycsb').setProfilingLevel($level)" 2>/dev/null
}

# Function to clean database
clean_db() {
    mongosh --quiet --eval "db.getSiblingDB('ycsb').dropDatabase()" 2>/dev/null
}

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

# Function to run a workload with multiple iterations
run_workload() {
    local workload=$1
    local audit_mode=$2

    echo "  Running workload$workload ($audit_mode)..."

    local sum=0
    local count=0

    for ((i=1; i<=ITERATIONS; i++)); do
        if [ "$ITERATIONS" -gt 1 ]; then
            echo "    Iteration $i/$ITERATIONS..."
        fi

        clean_db

        # If audit enabled, reset profile collection
        if [ "$audit_mode" = "enabled" ]; then
            mongosh --quiet --eval "db.getSiblingDB('ycsb').system.profile.drop()" 2>/dev/null || true
            set_profiling 2
        fi

        local throughput=$(run_single_iteration "$workload")

        if [ "$throughput" != "0" ]; then
            sum=$(echo "$sum + $throughput" | bc)
            count=$((count + 1))

            if [ "$ITERATIONS" -gt 1 ]; then
                echo "$workload,$audit_mode,$i,$throughput" >> "$RAW_RESULTS_FILE"
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

    echo "$workload,$audit_mode,$avg_throughput" >> "$RESULTS_FILE"

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

# Check if MongoDB is already running, stop it
if pgrep -x mongod > /dev/null; then
    stop_mongo
fi

start_mongo

echo ""
echo "Running workloads WITHOUT audit logging..."
echo "------------------------------------------"
set_profiling 0

for w in $WORKLOADS; do
    run_workload "$w" "disabled"
done

echo ""
echo "Running workloads WITH audit logging..."
echo "------------------------------------------"

for w in $WORKLOADS; do
    run_workload "$w" "enabled"
done

stop_mongo

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
