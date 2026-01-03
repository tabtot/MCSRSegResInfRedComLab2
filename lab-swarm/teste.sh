#!/bin/bash

# Script to kill a container, collect logs, and measure RTO
# Usage: ./rto_test.sh <worker_node> <service_name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WORKER_NODE=${1:-worker1}
SERVICE_NAME=${2:-"web-backend"}
HEALTH_CHECK_URL=${3:-"http://192.168.1.70:8080/health"}
LOG_DIR="./rto_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${LOG_DIR}/rto_report_${TIMESTAMP}.txt"

# Create log directory
mkdir -p "${LOG_DIR}"

echo -e "${YELLOW}=== RTO Test Script ===${NC}"
echo "Worker Node: ${WORKER_NODE}"
echo "Service: ${SERVICE_NAME}"
echo "Timestamp: ${TIMESTAMP}"
echo ""

# Function to log with timestamp
log_event() {
    local event=$1
    local timestamp=$(date +%s.%N)
    echo "${timestamp}|${event}" >> "${LOG_DIR}/events_${TIMESTAMP}.log"
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S.%3N')]${NC} ${event}"
}

# Function to check service health
check_health() {
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "${HEALTH_CHECK_URL}" > /dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
        ((attempt++))
    done
    return 1
}

# Get container ID from the service
log_event "Getting container ID for service ${SERVICE_NAME}"
CONTAINER_ID=$(docker exec ${WORKER_NODE} docker ps --filter "name=${SERVICE_NAME}" --format "{{.ID}}" | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    echo -e "${RED}Error: No container found for service ${SERVICE_NAME} on ${WORKER_NODE}${NC}"
    exit 1
fi

echo "Container ID: ${CONTAINER_ID}"
echo ""

# Record initial state
log_event "Recording initial state"
docker exec ${WORKER_NODE} docker ps --filter "name=${SERVICE_NAME}" >> "${LOG_DIR}/initial_state_${TIMESTAMP}.log"

# Check initial health
log_event "Checking initial service health"
if check_health; then
    log_event "Service is healthy before test"
else
    echo -e "${RED}Warning: Service not healthy before test${NC}"
fi

# Record start time
START_TIME=$(date +%s.%N)
log_event "TEST START - Killing container ${CONTAINER_ID}"

# Kill the container
echo -e "${RED}Killing container...${NC}"
docker exec ${WORKER_NODE} docker kill ${CONTAINER_ID}

log_event "Container killed"

# Wait for recovery and monitor
log_event "Monitoring service recovery"
echo "Waiting for service to recover..."

RECOVERED=false
CHECK_START=$(date +%s.%N)

for i in {1..60}; do
    sleep 1
    
    # Check if new container is running
    NEW_CONTAINER=$(docker exec ${WORKER_NODE} docker ps --filter "name=${SERVICE_NAME}" --format "{{.ID}}" | head -n 1)
    
    if [ ! -z "$NEW_CONTAINER" ] && [ "$NEW_CONTAINER" != "$CONTAINER_ID" ]; then
        log_event "New container detected: ${NEW_CONTAINER}"
        
        # Check if service is healthy
        if check_health; then
            RECOVERY_TIME=$(date +%s.%N)
            log_event "Service recovered and healthy"
            RECOVERED=true
            break
        fi
    fi
    
    echo -n "."
done

echo ""

# Calculate RTO
if [ "$RECOVERED" = true ]; then
    RTO=$(echo "$RECOVERY_TIME - $START_TIME" | bc)
    log_event "TEST COMPLETE - RTO: ${RTO} seconds"
    echo -e "${GREEN}Service recovered successfully!${NC}"
else
    log_event "TEST FAILED - Service did not recover within timeout"
    echo -e "${RED}Service did not recover within 60 seconds${NC}"
    RTO="FAILED"
fi

# Collect final state
log_event "Collecting final state"
docker exec ${WORKER_NODE} docker ps --filter "name=${SERVICE_NAME}" >> "${LOG_DIR}/final_state_${TIMESTAMP}.log"

# Get Docker Swarm service logs
log_event "Collecting service logs"
docker service logs ${SERVICE_NAME} --tail 50 > "${LOG_DIR}/service_logs_${TIMESTAMP}.log" 2>&1 || true

# Generate report
echo ""
echo -e "${YELLOW}=== Generating Report ===${NC}"

cat > "${REPORT_FILE}" << EOF
=====================================
RTO MEASUREMENT REPORT
=====================================

Test Information:
-----------------
Date/Time: $(date '+%Y-%m-%d %H:%M:%S')
Worker Node: ${WORKER_NODE}
Service Name: ${SERVICE_NAME}
Original Container ID: ${CONTAINER_ID}
New Container ID: ${NEW_CONTAINER:-N/A}

Test Results:
-------------
Test Start: $(date -d @${START_TIME} '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date -r ${START_TIME} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
Recovery Time: $(date -d @${RECOVERY_TIME:-0} '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date -r ${RECOVERY_TIME:-0} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
RTO (Recovery Time Objective): ${RTO} seconds
Status: $([ "$RECOVERED" = true ] && echo "SUCCESS" || echo "FAILED")

Timeline:
---------
$(cat ${LOG_DIR}/events_${TIMESTAMP}.log)

Service Configuration:
---------------------
Replicas: $(docker service inspect ${SERVICE_NAME} --format '{{.Spec.Mode.Replicated.Replicas}}' 2>/dev/null || echo "N/A")
Restart Policy: $(docker service inspect ${SERVICE_NAME} --format '{{.Spec.TaskTemplate.RestartPolicy.Condition}}' 2>/dev/null || echo "N/A")

Initial State:
-------------
$(cat ${LOG_DIR}/initial_state_${TIMESTAMP}.log)

Final State:
-----------
$(cat ${LOG_DIR}/final_state_${TIMESTAMP}.log)

Observations:
------------
- Container was forcefully killed using 'docker kill'
- Docker Swarm detected the failure and started a new container
- Health check endpoint: ${HEALTH_CHECK_URL}
$([ "$RECOVERED" = true ] && echo "- Service recovered within acceptable time" || echo "- Service failed to recover within 60 seconds")

Generated: $(date)
=====================================
EOF

# Display report
cat "${REPORT_FILE}"

echo ""
echo -e "${GREEN}Report saved to: ${REPORT_FILE}${NC}"
echo -e "${GREEN}All logs saved to: ${LOG_DIR}/${NC}"

# Exit with appropriate code
if [ "$RECOVERED" = true ]; then
    exit 0
else
    exit 1
fi
