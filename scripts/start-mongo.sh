#!/bin/bash
# Start MongoDB with or without audit logging
# Usage: ./start-mongo.sh [audit|noaudit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MODE="${1:-audit}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create necessary directories
mkdir -p "$PROJECT_ROOT/data/db-audit"
mkdir -p "$PROJECT_ROOT/data/db-noaudit"
mkdir -p "$PROJECT_ROOT/logs"

# Check if MongoDB is already running
if pgrep -x "mongod" > /dev/null; then
    echo -e "${YELLOW}WARNING: MongoDB is already running${NC}"
    echo "Stop it first with: ./stop-mongo.sh"
    exit 1
fi

if [ "$MODE" = "audit" ]; then
    CONFIG_FILE="$PROJECT_ROOT/configs/mongod-log.yaml"
    echo -e "${GREEN}Starting MongoDB WITH audit logging...${NC}"
else
    CONFIG_FILE="$PROJECT_ROOT/configs/mongod-nolog.yaml"
    echo -e "${GREEN}Starting MongoDB WITHOUT audit logging...${NC}"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

echo "Config: $CONFIG_FILE"
echo ""

# Check MongoDB version and edition
MONGO_VERSION=$(mongod --version | head -1)
echo "MongoDB version: $MONGO_VERSION"

if echo "$MONGO_VERSION" | grep -q "Enterprise"; then
    echo -e "${GREEN}MongoDB Enterprise detected - native audit logging available${NC}"
else
    echo -e "${YELLOW}MongoDB Community detected${NC}"
    if [ "$MODE" = "audit" ]; then
        echo -e "${YELLOW}NOTE: Native audit logging requires Enterprise Edition${NC}"
        echo "Using operation profiling as an alternative (logs to system.profile collection)"
        echo ""
    fi
fi

# Start MongoDB
echo ""
echo "Starting mongod..."
mongod --config "$CONFIG_FILE" --fork

echo ""
echo -e "${GREEN}MongoDB started successfully!${NC}"
echo ""
echo "To check status: mongosh --eval 'db.adminCommand(\"serverStatus\")'"
echo "To stop: ./stop-mongo.sh"
