#!/usr/bin/env bash
# scripts/run-tests.sh — full test suite with structured log output.
#
# Usage:
#   ./scripts/run-tests.sh               # run all suites
#   ./scripts/run-tests.sh --unit        # unit tests only
#   ./scripts/run-tests.sh --infra       # infrastructure tests only
#   ./scripts/run-tests.sh --integration # integration tests (starts compose)
#   ./scripts/run-tests.sh --no-compose  # skip compose start/stop lifecycle
#
# Output:
#   - Colour output to stdout
#   - Full log saved to logs/test-YYYY-MM-DD_HH-MM-SS.log
#   - Exit code 0 = all suites passed, 1 = one or more suites failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
RUN_UNIT=true
RUN_INFRA=true
RUN_INTEGRATION=true
MANAGE_COMPOSE=true  # start/stop docker compose around integration tests

for arg in "$@"; do
  case "$arg" in
    --unit)         RUN_UNIT=true;  RUN_INFRA=false; RUN_INTEGRATION=false ;;
    --infra)        RUN_UNIT=false; RUN_INFRA=true;  RUN_INTEGRATION=false ;;
    --integration)  RUN_UNIT=false; RUN_INFRA=false; RUN_INTEGRATION=true  ;;
    --no-compose)   MANAGE_COMPOSE=false ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $0 [--unit|--infra|--integration] [--no-compose]"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="$LOG_DIR/test-${TIMESTAMP}.log"

# Tee all output to log file and stdout simultaneously
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
SUITE_RESULTS=()   # accumulates "SUITE_NAME:PASS|FAIL"
OVERALL_EXIT=0

header() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

run_pytest_suite() {
  local suite_name="$1"
  local pytest_args=("${@:2}")

  header "Suite: $suite_name"
  echo -e "  ${CYAN}Command:${NC} pytest ${pytest_args[*]}"
  echo -e "  ${CYAN}Started:${NC} $(date '+%H:%M:%S')"
  echo ""

  if python3 -m pytest "${pytest_args[@]}" \
      --tb=short \
      -v \
      --log-cli-level=WARNING; then
    echo ""
    echo -e "  ${GREEN}✓ PASSED${NC} — $suite_name"
    SUITE_RESULTS+=("$suite_name:PASS")
  else
    echo ""
    echo -e "  ${RED}✗ FAILED${NC} — $suite_name"
    SUITE_RESULTS+=("$suite_name:FAIL")
    OVERALL_EXIT=1
  fi

  echo -e "  ${CYAN}Finished:${NC} $(date '+%H:%M:%S')"
}

compose_up() {
  header "Starting Docker Compose stack"
  docker compose -f "$REPO_ROOT/docker-compose.yml" up --build -d
  echo ""
  echo "  Waiting for containers to become healthy..."
  local deadline=$((SECONDS + 120))
  while [[ $SECONDS -lt $deadline ]]; do
    local healthy
    healthy=$(docker compose -f "$REPO_ROOT/docker-compose.yml" ps --format json \
      | python3 -c "
import sys, json
data = [json.loads(l) for l in sys.stdin if l.strip()]
healthy = [s for s in data if s.get('Health') == 'healthy']
print(len(healthy), len(data))
" 2>/dev/null || echo "0 0")
    local h total
    h=$(echo "$healthy" | cut -d' ' -f1)
    total=$(echo "$healthy" | cut -d' ' -f2)
    if [[ "$total" -gt 0 && "$h" -eq "$total" ]]; then
      echo -e "  ${GREEN}✓${NC} All $total containers healthy"
      return 0
    fi
    echo -e "  ${YELLOW}  waiting... ($h/$total healthy)${NC}"
    sleep 3
  done
  echo -e "  ${RED}✗ Containers did not become healthy within 60s${NC}"
  docker compose -f "$REPO_ROOT/docker-compose.yml" ps
  return 1
}

compose_down() {
  echo ""
  header "Stopping Docker Compose stack"
  docker compose -f "$REPO_ROOT/docker-compose.yml" down
  echo -e "  ${GREEN}✓${NC} Stack stopped"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║           ANPE Demo — Test Suite Runner          ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  ${CYAN}Date:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  ${CYAN}Log:${NC}      $LOG_FILE"
echo -e "  ${CYAN}Suites:${NC}   unit=$RUN_UNIT  infra=$RUN_INFRA  integration=$RUN_INTEGRATION"

# ---------------------------------------------------------------------------
# Unit tests
# ---------------------------------------------------------------------------
if [[ "$RUN_UNIT" == true ]]; then
  run_pytest_suite \
    "Unit — api-gateway" \
    "services/api-gateway/test_main.py" \
    --rootdir="$REPO_ROOT"

  run_pytest_suite \
    "Unit — worker" \
    "services/worker/test_main.py" \
    --rootdir="$REPO_ROOT"
fi

# ---------------------------------------------------------------------------
# Infrastructure tests (no AWS needed)
# ---------------------------------------------------------------------------
if [[ "$RUN_INFRA" == true ]]; then
  run_pytest_suite \
    "Infrastructure (Terraform + ShellCheck)" \
    "tests/test_infrastructure.py" \
    --rootdir="$REPO_ROOT"
fi

# ---------------------------------------------------------------------------
# Integration tests (live Docker Compose)
# ---------------------------------------------------------------------------
if [[ "$RUN_INTEGRATION" == true ]]; then
  COMPOSE_STARTED=false

  if [[ "$MANAGE_COMPOSE" == true ]]; then
    if compose_up; then
      COMPOSE_STARTED=true
    else
      SUITE_RESULTS+=("Integration — Docker Compose:FAIL")
      OVERALL_EXIT=1
    fi
  fi

  if [[ "$MANAGE_COMPOSE" == false ]] || [[ "$COMPOSE_STARTED" == true ]]; then
    run_pytest_suite \
      "Integration — live stack" \
      "tests/test_integration.py" \
      --rootdir="$REPO_ROOT"
  fi

  if [[ "$COMPOSE_STARTED" == true ]]; then
    compose_down
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  TEST SUMMARY${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PASS_COUNT=0
FAIL_COUNT=0

for result in "${SUITE_RESULTS[@]}"; do
  suite="${result%%:*}"
  status="${result##*:}"
  if [[ "$status" == "PASS" ]]; then
    echo -e "  ${GREEN}✓ PASS${NC}  $suite"
    ((PASS_COUNT++)) || true
  else
    echo -e "  ${RED}✗ FAIL${NC}  $suite"
    ((FAIL_COUNT++)) || true
  fi
done

echo ""
echo -e "  ${CYAN}Suites run:${NC}    $((PASS_COUNT + FAIL_COUNT))"
echo -e "  ${GREEN}Passed:${NC}        $PASS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  ${RED}Failed:${NC}        $FAIL_COUNT"
else
  echo -e "  Failed:        $FAIL_COUNT"
fi
echo -e "  ${CYAN}Log saved to:${NC}  $LOG_FILE"
echo ""

if [[ $OVERALL_EXIT -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ALL TESTS PASSED${NC}"
else
  echo -e "${RED}${BOLD}  SOME TESTS FAILED — see log for details${NC}"
fi
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

exit $OVERALL_EXIT
