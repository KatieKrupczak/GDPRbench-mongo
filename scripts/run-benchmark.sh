#!/bin/bash
# GDPR Benchmark Runner for MongoDB
# Usage: ./run-benchmark.sh [audit|noaudit] [workload] [operation]
#
# Examples:
#   ./run-benchmark.sh audit gdpr_customer load
#   ./run-benchmark.sh audit gdpr_customer run
#   ./run-benchmark.sh noaudit gdpr_controller load
#   ./run-benchmark.sh noaudit gdpr_controller run

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"

# Configuration
AUDIT_MODE="${1:-audit}"
WORKLOAD="${2:-gdpr_customer}"
OPERATION="${3:-run}"

# MongoDB connection
MONGO_URL="mongodb://localhost:27017/ycsb?w=1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}GDPR Benchmark - MongoDB${NC}"
echo -e "${GREEN}=======================================${NC}"
echo "Mode: $AUDIT_MODE"
echo "Workload: $WORKLOAD"
echo "Operation: $OPERATION"
echo ""

# Check if MongoDB is running
if ! mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo -e "${RED}ERROR: MongoDB is not running${NC}"
    echo "Please start MongoDB with one of the following configs:"
    echo "  With audit:    mongod --config $PROJECT_ROOT/configs/mongod-log.yaml"
    echo "  Without audit: mongod --config $PROJECT_ROOT/configs/mongod-nolog.yaml"
    exit 1
fi

# Check if workload file exists
WORKLOAD_FILE="$SRC_DIR/workloads/$WORKLOAD"
if [ ! -f "$WORKLOAD_FILE" ]; then
    echo -e "${RED}ERROR: Workload file not found: $WORKLOAD_FILE${NC}"
    echo "Available workloads:"
    ls "$SRC_DIR/workloads/"
    exit 1
fi

# Create output directory
OUTPUT_DIR="$PROJECT_ROOT/results/$AUDIT_MODE"
mkdir -p "$OUTPUT_DIR"

# Generate timestamp for output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/${WORKLOAD}_${OPERATION}_${TIMESTAMP}.txt"

echo -e "${YELLOW}Running benchmark...${NC}"
echo "Output will be saved to: $OUTPUT_FILE"
echo ""

# Run the benchmark
cd "$SRC_DIR"
./bin/ycsb.sh "$OPERATION" mongodb -s \
    -P "$WORKLOAD_FILE" \
    -p mongodb.url="$MONGO_URL" \
    2>&1 | tee "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}Benchmark complete!${NC}"
echo "Results saved to: $OUTPUT_FILE"

# If audit mode, show audit log stats
if [ "$AUDIT_MODE" = "audit" ]; then
    AUDIT_LOG="$PROJECT_ROOT/logs/audit.json"
    if [ -f "$AUDIT_LOG" ]; then
        echo ""
        echo -e "${YELLOW}Audit log statistics:${NC}"
        echo "  Total entries: $(wc -l < "$AUDIT_LOG")"
        echo "  File size: $(du -h "$AUDIT_LOG" | cut -f1)"
    fi
fi
