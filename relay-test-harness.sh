#!/bin/bash
set -e

# ReLay Gesture Testing Harness
# Automates log collection, test procedures, and validation

readonly LOG_FILE="/tmp/relay_test_$(date +%s).log"
readonly RESULTS_FILE="/tmp/relay_test_results_$(date +%Y%m%d_%H%M%S).txt"
readonly TIMEOUT=15

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Initialize results file
{
  echo "ReLay Gesture Testing Harness"
  echo "Date: $(date)"
  echo "Log file: $LOG_FILE"
  echo "======================================"
  echo ""
} > "$RESULTS_FILE"

log_section() {
  echo -e "${BLUE}=== $1 ===${NC}"
  echo "=== $1 ===" >> "$RESULTS_FILE"
}

test_result() {
  local name="$1"
  local passed="$2"
  local details="$3"

  ((TESTS_RUN++))

  if [ "$passed" = "true" ]; then
    echo -e "${GREEN}✓ PASS${NC}: $name"
    echo "✓ PASS: $name" >> "$RESULTS_FILE"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL${NC}: $name"
    echo "✗ FAIL: $name" >> "$RESULTS_FILE"
    ((TESTS_FAILED++))
  fi

  if [ -n "$details" ]; then
    echo "  Details: $details"
    echo "  Details: $details" >> "$RESULTS_FILE"
  fi
  echo "" >> "$RESULTS_FILE"
}

# Collect logs from system
start_log_collection() {
  echo -e "${YELLOW}Starting log collection...${NC}"
  # Try multiple log sources
  if command -v log &> /dev/null; then
    log stream --predicate 'eventMessage contains[cd] "gesture" OR eventMessage contains[cd] "interceptor" OR eventMessage contains[cd] "transition"' --level debug > "$LOG_FILE" 2>&1 &
    LOG_PID=$!
  else
    # Fallback: monitor typical log paths
    touch "$LOG_FILE"
    if [ -f "/tmp/relay.log" ]; then
      tail -f /tmp/relay.log > "$LOG_FILE" 2>&1 &
      LOG_PID=$!
    fi
  fi
  sleep 1
}

stop_log_collection() {
  if [ -n "$LOG_PID" ]; then
    kill $LOG_PID 2>/dev/null || true
    sleep 1
  fi
}

# Extract logs since last marker
get_recent_logs() {
  if [ -f "$LOG_FILE" ]; then
    tail -100 "$LOG_FILE"
  fi
}

# Search logs for pattern
has_log_pattern() {
  local pattern="$1"
  if grep -q "$pattern" "$LOG_FILE" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Extract gesture IDs from logs
extract_gesture_ids() {
  grep -oE 'gesture=[a-f0-9]{8}' "$LOG_FILE" 2>/dev/null | sort | uniq || echo ""
}

# Validate gesture lifecycle
validate_gesture_lifecycle() {
  local gesture_id="$1"
  local found_begin=0
  local found_commit=0
  local found_state_change=0

  if grep -q "gesture began.*gesture=$gesture_id" "$LOG_FILE"; then
    found_begin=1
  fi

  if grep -q "gesture committed.*gesture=$gesture_id" "$LOG_FILE"; then
    found_commit=1
  fi

  if grep -q "state transition.*gesture=$gesture_id" "$LOG_FILE"; then
    found_state_change=1
  fi

  if [ $found_begin -eq 1 ] && [ $found_commit -eq 1 ] && [ $found_state_change -eq 1 ]; then
    return 0
  fi
  return 1
}

# Interactive test procedure
run_test_procedure() {
  local test_name="$1"
  local instructions="$2"
  local success_pattern="$3"

  echo ""
  echo -e "${YELLOW}Test: $test_name${NC}"
  echo "Instructions: $instructions"
  echo ""
  read -p "Ready? Press ENTER when you've completed the gesture, then I'll check the logs..."

  sleep 1
  local logs=$(get_recent_logs)

  if [ -n "$success_pattern" ] && echo "$logs" | grep -q "$success_pattern"; then
    test_result "$test_name" "true" "Log pattern found: $success_pattern"
    return 0
  elif [ -n "$success_pattern" ]; then
    test_result "$test_name" "false" "Expected pattern not found: $success_pattern"
    echo "Recent logs:"
    echo "$logs" | tail -20
    return 1
  else
    # No pattern specified, ask user
    read -p "Did the gesture complete successfully? (y/n): " response
    if [ "$response" = "y" ]; then
      test_result "$test_name" "true" "User confirmed"
      return 0
    else
      test_result "$test_name" "false" "User reported failure"
      return 1
    fi
  fi
}

# Main test suites

suite_1_gesture_recognition() {
  log_section "Suite 1: Gesture Recognition"

  echo -e "${YELLOW}This suite tests basic 2-finger title-bar hit recognition.${NC}"
  echo "We'll test each app in sequence."
  echo ""

  run_test_procedure \
    "Finder: Title-bar hit recognition" \
    "1. Open Finder window
2. Position it so title bar is visible
3. Place two fingers on title bar and drag LEFT (≥2cm)
4. Observe window snap to left half" \
    "title bar hit"

  run_test_procedure \
    "Safari: Title-bar hit recognition" \
    "1. Open Safari window
2. Place two fingers on title bar and drag LEFT (≥2cm)
3. Observe window snap to left half" \
    "title bar hit"

  run_test_procedure \
    "Terminal: Title-bar hit recognition" \
    "1. Open Terminal window
2. Place two fingers on title bar and drag RIGHT (≥2cm)
3. Observe window snap to right half" \
    "title bar hit"
}

suite_2_gesture_lifecycle() {
  log_section "Suite 2: Gesture Lifecycle Logging"

  echo -e "${YELLOW}This suite validates that all gesture phases are logged with matching IDs.${NC}"
  echo ""

  # Clear log before test
  > "$LOG_FILE"

  run_test_procedure \
    "Complete gesture lifecycle" \
    "1. Open Finder
2. Perform ONE 2-finger drag on title bar (left or right, ≥2cm)
3. Wait for snap to complete" \
    ""

  # Parse logs
  local gesture_ids=$(extract_gesture_ids)
  if [ -z "$gesture_ids" ]; then
    test_result "Gesture ID generation" "false" "No gesture IDs found in logs"
    return 1
  fi

  local first_id=$(echo "$gesture_ids" | head -1)
  echo "Found gesture ID: $first_id"

  if validate_gesture_lifecycle "$first_id"; then
    test_result "Gesture lifecycle validation" "true" "Gesture $first_id has begin, commit, and state change"
  else
    test_result "Gesture lifecycle validation" "false" "Incomplete gesture lifecycle for $first_id"
    echo "Logs:"
    grep "gesture=$first_id" "$LOG_FILE" 2>/dev/null || echo "(no matching logs)"
  fi
}

suite_3_snap_directions() {
  log_section "Suite 3: Left / Right Snap"

  echo -e "${YELLOW}This suite tests left and right swipe snap targets.${NC}"
  echo ""

  run_test_procedure \
    "Left snap (window to left 50%)" \
    "1. Open Finder
2. Move window to center or right side
3. 2-finger drag LEFT on title bar (≥2cm, moderate speed)
4. Window should snap to left half of screen" \
    "leftHalf"

  run_test_procedure \
    "Right snap (window to right 50%)" \
    "1. 2-finger drag RIGHT on title bar (≥2cm)
2. Window should snap to right half of screen" \
    "rightHalf"
}

suite_4_center_snap() {
  log_section "Suite 4: Center Snap (if enabled)"

  echo -e "${YELLOW}This suite tests center snap if the toggle is enabled.${NC}"
  echo ""

  read -p "Is 'Center Snap' enabled in ReLay settings? (y/n): " center_enabled

  if [ "$center_enabled" != "y" ]; then
    echo "Skipping center snap tests (not enabled)"
    return 0
  fi

  run_test_procedure \
    "Up swipe → center snap" \
    "1. Open Finder window (not maximized)
2. 2-finger drag UP on title bar
3. Window should center on screen" \
    "center"
}

suite_5_multi_gesture() {
  log_section "Suite 5: Multi-Gesture Sequence"

  echo -e "${YELLOW}This suite tests that consecutive gestures have different IDs.${NC}"
  echo ""

  > "$LOG_FILE"

  run_test_procedure \
    "Gesture #1: left snap" \
    "1. Open Finder
2. 2-finger drag LEFT on title bar
3. Wait for snap" \
    ""

  > "$LOG_FILE"
  sleep 2

  run_test_procedure \
    "Gesture #2: right snap" \
    "1. 2-finger drag RIGHT on title bar
2. Wait for snap" \
    ""

  local gesture_ids=$(extract_gesture_ids)
  local id_count=$(echo "$gesture_ids" | wc -l)

  if [ "$id_count" -ge 2 ]; then
    test_result "Multi-gesture ID separation" "true" "Found $id_count unique gesture IDs"
  else
    test_result "Multi-gesture ID separation" "false" "Only found $id_count gesture ID(s), expected 2"
  fi
}

suite_6_settings() {
  log_section "Suite 6: Settings Verification"

  echo -e "${YELLOW}This suite tests settings behavior.${NC}"
  echo ""

  read -p "Run Settings Verification tests? (y/n): " run_settings

  if [ "$run_settings" != "y" ]; then
    return 0
  fi

  run_test_procedure \
    "Snap Speed: Instant vs Smooth" \
    "1. Open ReLay Settings
2. Move 'Snap Speed' slider to INSTANT (left)
3. Snap a window - should complete quickly (~0.08s)
4. Move slider to SMOOTH (right)
5. Snap again - should take longer (~0.45s)" \
    ""

  run_test_procedure \
    "Snap Haptics toggle" \
    "1. Toggle 'Snap Haptics' ON
2. Snap a window - you should feel haptic feedback
3. Toggle OFF
4. Snap again - no haptic feedback" \
    ""

  run_test_procedure \
    "Feel Presets (Careful/Balanced/Snappy)" \
    "1. Click 'Careful' preset - observe all sliders move left
2. Snap a window - should feel slow and deliberate
3. Click 'Snappy' - all sliders move right
4. Snap again - should feel faster and more responsive" \
    ""
}

# Main execution
main() {
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   ReLay Gesture Testing Harness        ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
  echo ""

  echo "This harness will:"
  echo "  1. Collect logs from your system"
  echo "  2. Guide you through test procedures"
  echo "  3. Validate logs automatically"
  echo "  4. Generate a final report"
  echo ""

  read -p "Ready to start? (y/n): " ready
  if [ "$ready" != "y" ]; then
    echo "Exiting."
    exit 0
  fi

  echo ""
  read -p "Is ReLay already running? (y/n): " relay_running
  if [ "$relay_running" != "y" ]; then
    echo -e "${YELLOW}Please build and run ReLay before continuing.${NC}"
    echo "  swift build"
    read -p "Press ENTER when ReLay is running..."
  fi

  start_log_collection

  # Run test suites
  suite_1_gesture_recognition
  suite_2_gesture_lifecycle
  suite_3_snap_directions
  suite_4_center_snap
  suite_5_multi_gesture
  suite_6_settings

  # Stop collection
  stop_log_collection

  # Summary
  echo ""
  log_section "Test Summary"
  echo -e "${BLUE}Tests Run: $TESTS_RUN${NC}"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"

  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
  else
    echo -e "${YELLOW}⚠ Some tests failed. Review details below.${NC}"
  fi

  {
    echo ""
    echo "Test Summary"
    echo "Tests Run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    echo "Log file: $LOG_FILE"
  } >> "$RESULTS_FILE"

  echo ""
  echo "Results saved to: $RESULTS_FILE"
  echo "Full logs available in: $LOG_FILE"

  if command -v cat &> /dev/null; then
    read -p "View results now? (y/n): " view_results
    if [ "$view_results" = "y" ]; then
      cat "$RESULTS_FILE"
    fi
  fi
}

main "$@"
