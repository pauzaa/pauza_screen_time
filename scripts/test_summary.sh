#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
total=$(find . -path "*/test-results/testDebugUnitTest/*" -name "*.xml" -exec sed -n 's/.*tests="\([0-9]*\)".*/\1/p' {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
failed=$(find . -path "*/test-results/testDebugUnitTest/*" -name "*.xml" -exec sed -n 's/.*failures="\([0-9]*\)".*/\1/p' {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
errors=$(find . -path "*/test-results/testDebugUnitTest/*" -name "*.xml" -exec sed -n 's/.*errors="\([0-9]*\)".*/\1/p' {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
skipped=$(find . -path "*/test-results/testDebugUnitTest/*" -name "*.xml" -exec sed -n 's/.*skipped="\([0-9]*\)".*/\1/p' {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
echo "Tests run: ${total:-0}"
echo "Failures: ${failed:-0}"
echo "Errors: ${errors:-0}"
echo "Skipped: ${skipped:-0}"
