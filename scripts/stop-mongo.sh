#!/bin/bash
# Stop MongoDB
# Usage: ./stop-mongo.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "Stopping MongoDB..."

# Try graceful shutdown first
if mongosh --eval "db.adminCommand({ shutdown: 1 })" --quiet 2>/dev/null; then
    echo -e "${GREEN}MongoDB stopped gracefully${NC}"
else
    # Fallback to killing the process
    if pgrep -x "mongod" > /dev/null; then
        pkill -x mongod
        echo -e "${GREEN}MongoDB process killed${NC}"
    else
        echo -e "${RED}MongoDB is not running${NC}"
    fi
fi
