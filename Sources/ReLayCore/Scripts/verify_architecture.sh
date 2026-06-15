#!/usr/bin/env bash
set -euo pipefail

echo "🔍 ReLay Architecture Enforcement Check"

ROOT="Sources/ReLayCore"
fail() { echo "❌ ARCHITECTURE VIOLATION: $1"; exit 1; }

# RULE 1: Input isolation - cannot depend on LayoutEngine, LayoutLibrary, SpatialState, or WindowEngine
echo "Checking Input boundaries..."
for file in "$ROOT"/Input/**/*.swift; do
  if grep -q "import.*LayoutEngine" "$file" 2>/dev/null; then
    fail "Input cannot import LayoutEngine (violation in $file)"
  fi
  if grep -q "import.*LayoutLibrary" "$file" 2>/dev/null; then
    fail "Input cannot import LayoutLibrary (violation in $file)"
  fi
  if grep -q "import.*SpatialState" "$file" 2>/dev/null; then
    fail "Input cannot import SpatialState (violation in $file)"
  fi
  if grep -q "import.*WindowEngine" "$file" 2>/dev/null; then
    fail "Input cannot import WindowEngine (violation in $file)"
  fi
done

# RULE 2: SpatialState isolation - cannot depend on LayoutEngine, LayoutLibrary, or WindowEngine
echo "Checking SpatialState boundaries..."
for file in "$ROOT"/SpatialState/**/*.swift; do
  if grep -q "import.*LayoutEngine" "$file" 2>/dev/null; then
    fail "SpatialState cannot import LayoutEngine (violation in $file)"
  fi
  if grep -q "import.*LayoutLibrary" "$file" 2>/dev/null; then
    fail "SpatialState cannot import LayoutLibrary (violation in $file)"
  fi
  if grep -q "import.*WindowEngine" "$file" 2>/dev/null; then
    fail "SpatialState cannot import WindowEngine (violation in $file)"
  fi
done

# RULE 3: LayoutEngine purity - cannot depend on SpatialState, WindowEngine, or Input
echo "Checking LayoutEngine boundaries..."
for file in "$ROOT"/LayoutEngine/**/*.swift; do
  if grep -q "import.*SpatialState" "$file" 2>/dev/null; then
    fail "LayoutEngine cannot import SpatialState (violation in $file)"
  fi
  if grep -q "import.*WindowEngine" "$file" 2>/dev/null; then
    fail "LayoutEngine cannot import WindowEngine (violation in $file)"
  fi
  if grep -q "import.*Input" "$file" 2>/dev/null; then
    fail "LayoutEngine cannot import Input (violation in $file)"
  fi
done

# RULE 4: LayoutLibrary read-only isolation - cannot depend on Input, SpatialState, or WindowEngine
echo "Checking LayoutLibrary boundaries..."
for file in "$ROOT"/LayoutLibrary/**/*.swift; do
  if grep -q "import.*Input" "$file" 2>/dev/null; then
    fail "LayoutLibrary cannot import Input (violation in $file)"
  fi
  if grep -q "import.*SpatialState" "$file" 2>/dev/null; then
    fail "LayoutLibrary cannot import SpatialState (violation in $file)"
  fi
  if grep -q "import.*WindowEngine" "$file" 2>/dev/null; then
    fail "LayoutLibrary cannot import WindowEngine (violation in $file)"
  fi
done

# RULE 5: WindowEngine isolation - can only depend on Core
echo "Checking WindowEngine boundaries..."
for file in "$ROOT"/WindowEngine/**/*.swift; do
  if grep -q "import.*LayoutEngine" "$file" 2>/dev/null; then
    fail "WindowEngine cannot import LayoutEngine (violation in $file)"
  fi
  if grep -q "import.*SpatialState" "$file" 2>/dev/null; then
    fail "WindowEngine cannot import SpatialState (violation in $file)"
  fi
  if grep -q "import.*Input" "$file" 2>/dev/null; then
    fail "WindowEngine cannot import Input (violation in $file)"
  fi
  if grep -q "import.*LayoutLibrary" "$file" 2>/dev/null; then
    fail "WindowEngine cannot import LayoutLibrary (violation in $file)"
  fi
done

# RULE 6: Config isolation - cannot depend on Input, SpatialState, LayoutEngine, LayoutLibrary, or WindowEngine
echo "Checking Config boundaries..."
for file in "$ROOT"/Config/**/*.swift; do
  if grep -q "import.*Input" "$file" 2>/dev/null; then
    fail "Config cannot import Input (violation in $file)"
  fi
  if grep -q "import.*SpatialState" "$file" 2>/dev/null; then
    fail "Config cannot import SpatialState (violation in $file)"
  fi
  if grep -q "import.*LayoutEngine" "$file" 2>/dev/null; then
    fail "Config cannot import LayoutEngine (violation in $file)"
  fi
  if grep -q "import.*LayoutLibrary" "$file" 2>/dev/null; then
    fail "Config cannot import LayoutLibrary (violation in $file)"
  fi
  if grep -q "import.*WindowEngine" "$file" 2>/dev/null; then
    fail "Config cannot import WindowEngine (violation in $file)"
  fi
done

echo "✅ Architecture clean"
