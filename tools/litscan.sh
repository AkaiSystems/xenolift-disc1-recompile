#!/bin/sh
# litscan - R1171 COMPILER-WARNING AUDIT (NOT a validated guest-address scanner).
#
# Known limits (Jos c361), stated not hidden:
#   1. Matches warning CLASSES, not helper-argument identity - a narrowing
#      warning is a candidate site, not proof the value reaches a guest-
#      address helper. Verify the literal's call site before acting.
#   2. The compiler's exit status IS checked: a failed compilation reports
#      errors separately and never reports "clean".
#   3. Warning wording varies between GCC and Clang and across versions;
#      the counts are an audit hint, not proof. Full output is retained.
#
# Usage (from tree root): sh tools/litscan.sh
# Exit: 0 = no narrowing warnings, 1 = candidate sites listed,
#       2 = compilation errors (audit not meaningful).

CC=cc
command -v gcc >/dev/null 2>&1 && CC=gcc
command -v clang >/dev/null 2>&1 && CC=clang

OUT=$($CC -fsyntax-only -Woverflow -Iruntime runtime/runtime.c 2>&1)
RC=$?

if [ $RC -ne 0 ]; then
    echo "litscan: COMPILATION ERRORS (compiler=$CC exit=$RC) - audit not meaningful."
    echo "litscan: error lines:"
    echo "$OUT" | grep "error" | head -20
    echo "litscan: full compiler output retained below:"
    echo "$OUT"
    exit 2
fi

NARROW=$(echo "$OUT" | grep -c "changes value")
echo "litscan: compiler=$CC exit=0; narrowing warnings: $NARROW (audit hint, not proof)"
if [ "$NARROW" -gt 0 ]; then
    echo "litscan: FULL compiler output retained below:"
    echo "$OUT"
    echo "litscan: each warning line is a CANDIDATE site; confirm the literal is"
    echo "litscan: actually passed to a guest-address helper. Table: docs/literal-class.md"
    exit 1
fi
exit 0
