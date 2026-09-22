#!/usr/bin/env python3
"""
fmt_parity_audit.py — C Format-String Directive / Argument Parity Auditor
Project Xenolift — Regression QA Tool (WARDEN)

Scans C source code for fprintf/printf/sprintf/snprintf calls and verifies
that the number of directives in the format string matches the number of
top-level arguments passed after the format string.

Handles:
  - Ignored calls in comments (//, /* */) and #if 0 blocks
  - Escaped %% (must not count as a directive)
  - Length modifiers (%ld, %zu, %08X, %llu, %hd, etc.)
  - Adjacent C string-literal concatenation ("a %u" "b %d")
  - Multi-line function calls
  - Nested parens/casts/commas in arguments: (unsigned)(x & 3u), func(a, b)
  - Ternaries with string literals as arguments: active ? "ENABLED" : "DISABLED"
  - Ternary format strings: cond ? "fmt1 %d" : "fmt2 %d"
"""

import sys
import os
import re

def count_directives(fmt_str):
    """
    Counts printf format directives in a format string.
    Correctly ignores '%%' escapes and parses C format specifiers.
    """
    i = 0
    n = len(fmt_str)
    count = 0
    while i < n:
        if fmt_str[i] == "%":
            if i + 1 < n and fmt_str[i + 1] == "%":
                i += 2  # skip %% escape
                continue
            i += 1
            # Parse flags
            while i < n and fmt_str[i] in "-+ #0'":
                i += 1
            # Parse field width
            if i < n and fmt_str[i] == "*":
                count += 1
                i += 1
            elif i < n and fmt_str[i].isdigit():
                while i < n and fmt_str[i].isdigit():
                    i += 1
            # Parse precision
            if i < n and fmt_str[i] == ".":
                i += 1
                if i < n and fmt_str[i] == "*":
                    count += 1
                    i += 1
                elif i < n and fmt_str[i].isdigit():
                    while i < n and fmt_str[i].isdigit():
                        i += 1
            # Parse length modifiers
            if i + 1 < n and fmt_str[i:i+2] in ("hh", "ll"):
                i += 2
            elif i < n and fmt_str[i] in "hljztL":
                i += 1
            # Parse conversion specifiers
            if i < n and fmt_str[i] in "diouxXeEfFgGaAcsptn":
                count += 1
                i += 1
        else:
            i += 1
    return count

def extract_string_literals(expr):
    """
    Extracts unescaped text content from all string literals in C expression `expr`.
    """
    lits = []
    i = 0
    n = len(expr)
    while i < n:
        if expr[i] == '"':
            i += 1
            content = []
            while i < n and expr[i] != '"':
                if expr[i] == '\\':
                    if i + 1 < n:
                        c = expr[i+1]
                        if c == 'n': content.append('\n')
                        elif c == 't': content.append('\t')
                        elif c == 'r': content.append('\r')
                        elif c == '"': content.append('"')
                        elif c == '\\': content.append('\\')
                        elif c == '%': content.append('%')
                        else: content.append(c)
                        i += 2
                    else:
                        i += 1
                else:
                    content.append(expr[i])
                    i += 1
            if i < n:
                i += 1
            lits.append("".join(content))
        else:
            i += 1
    return lits

def split_call_args(text, start_paren):
    """
    Parses C function call arguments inside parentheses starting at `start_paren`.
    Returns (args_list, end_index) or (None, end_index) if unparseable.
    """
    i = start_paren
    n = len(text)
    
    depth = 0
    bracket_depth = 0
    brace_depth = 0
    
    args = []
    current_arg = []
    
    in_string = False
    in_char = False
    
    while i < n:
        c = text[i]
        
        if in_string:
            current_arg.append(c)
            if c == '\\':
                if i + 1 < n:
                    current_arg.append(text[i+1])
                    i += 2
                    continue
            elif c == '"':
                in_string = False
            i += 1
            continue
            
        if in_char:
            current_arg.append(c)
            if c == '\\':
                if i + 1 < n:
                    current_arg.append(text[i+1])
                    i += 2
                    continue
            elif c == "'":
                in_char = False
            i += 1
            continue
            
        if c == '"':
            in_string = True
            current_arg.append(c)
            i += 1
            continue
        elif c == "'":
            in_char = True
            current_arg.append(c)
            i += 1
            continue
            
        if c == '(':
            if depth > 0:
                current_arg.append(c)
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                args.append("".join(current_arg).strip())
                return args, i + 1
            else:
                current_arg.append(c)
        elif c == '[':
            bracket_depth += 1
            current_arg.append(c)
        elif c == ']':
            bracket_depth -= 1
            current_arg.append(c)
        elif c == '{':
            brace_depth += 1
            current_arg.append(c)
        elif c == '}':
            brace_depth -= 1
            current_arg.append(c)
        elif c == ',' and depth == 1 and bracket_depth == 0 and brace_depth == 0:
            args.append("".join(current_arg).strip())
            current_arg = []
        else:
            if depth > 0:
                current_arg.append(c)
        i += 1
        
    return None, n

def strip_comments_and_if0(text):
    """
    Replaces C comments and #if 0 blocks with spaces while preserving line numbers (\n).
    """
    out = list(text)
    n = len(text)
    i = 0
    state = "NORMAL"
    if0_depth = 0
    
    while i < n:
        if state == "NORMAL":
            if text[i:i+2] == "//":
                out[i] = " "
                out[i+1] = " "
                i += 2
                while i < n and text[i] != "\n":
                    out[i] = " "
                    i += 1
                continue
            elif text[i:i+2] == "/*":
                out[i] = " "
                out[i+1] = " "
                i += 2
                while i < n and text[i:i+2] != "*/":
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
                if i < n:
                    out[i] = " "
                    out[i+1] = " "
                    i += 2
                continue
            elif text[i] == '"':
                i += 1
                while i < n and text[i] != '"':
                    if text[i] == "\\":
                        i += 2
                    else:
                        i += 1
                if i < n:
                    i += 1
                continue
            elif text[i] == "'":
                i += 1
                while i < n and text[i] != "'":
                    if text[i] == "\\":
                        i += 2
                    else:
                        i += 1
                if i < n:
                    i += 1
                continue
            elif text[i] == "#":
                line_start = text.rfind("\n", 0, i) + 1
                prefix = text[line_start:i]
                if prefix.strip() == "":
                    m = re.match(r"^#\s*if\s+0\b", text[i:])
                    if m:
                        state = "IF0"
                        if0_depth = 1
                        end_m = i + m.end()
                        for k in range(i, end_m):
                            if text[k] != "\n":
                                out[k] = " "
                        i = end_m
                        continue
            i += 1
        elif state == "IF0":
            if text[i] == "#":
                line_start = text.rfind("\n", 0, i) + 1
                prefix = text[line_start:i]
                if prefix.strip() == "":
                    if re.match(r"^#\s*if", text[i:]):
                        if0_depth += 1
                    elif re.match(r"^#\s*endif", text[i:]):
                        if0_depth -= 1
                        if if0_depth == 0:
                            state = "NORMAL"
                    elif if0_depth == 1 and re.match(r"^#\s*(else|elif)", text[i:]):
                        state = "NORMAL"
            if state == "IF0" and text[i] != "\n":
                out[i] = " "
            i += 1
            
    return "".join(out)

def scan_c_file(content):
    """
    Scans C content for printf/fprintf/sprintf/snprintf calls.
    Returns (results, total_calls) where each result is a dict with details.
    """
    cleaned = strip_comments_and_if0(content)
    
    func_pattern = re.compile(r"\b(fprintf|printf|sprintf|snprintf)\b")
    
    fmt_idx_map = {
        "printf": 0,
        "fprintf": 1,
        "sprintf": 1,
        "snprintf": 2,
    }
    
    results = []
    total_calls = 0
    
    for m in func_pattern.finditer(cleaned):
        func_name = m.group(1)
        start_pos = m.start()
        line_num = content[:start_pos].count("\n") + 1
        
        paren_pos = cleaned.find("(", m.end())
        if paren_pos == -1:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "UNPARSEABLE",
                "reason": "No opening parenthesis found"
            })
            continue
            
        between = cleaned[m.end():paren_pos]
        if between.strip() != "":
            # Not a function call
            continue
            
        args, end_pos = split_call_args(cleaned, paren_pos)
        if args is None:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "UNPARSEABLE",
                "reason": "Unbalanced parentheses"
            })
            continue
            
        total_calls += 1
        fmt_idx = fmt_idx_map[func_name]
        
        if len(args) <= fmt_idx:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "MISMATCH",
                "directives": 0,
                "args": len(args),
                "reason": f"Too few call arguments ({len(args)} args provided, format index is {fmt_idx})"
            })
            continue
            
        fmt_expr = args[fmt_idx]
        actual_args = args[fmt_idx + 1:]
        num_actual_args = len(actual_args)
        
        # Check for ternary expression in format string argument
        if "?" in fmt_expr and ":" in fmt_expr and not fmt_expr.startswith('"'):
            parts = fmt_expr.split("?", 1)
            rest = parts[1].split(":", 1)
            lits1 = extract_string_literals(rest[0])
            lits2 = extract_string_literals(rest[1])
            if lits1 and lits2:
                dirs1 = count_directives("".join(lits1))
                dirs2 = count_directives("".join(lits2))
                if dirs1 != num_actual_args or dirs2 != num_actual_args:
                    results.append({
                        "line": line_num,
                        "func": func_name,
                        "status": "MISMATCH",
                        "directives_branch1": dirs1,
                        "directives_branch2": dirs2,
                        "args": num_actual_args,
                        "reason": f"Ternary format mismatch: branch1={dirs1} dirs, branch2={dirs2} dirs, got {num_actual_args} args"
                    })
                else:
                    results.append({
                        "line": line_num,
                        "func": func_name,
                        "status": "MATCH",
                        "directives": dirs1,
                        "args": num_actual_args
                    })
                continue
                
        lits = extract_string_literals(fmt_expr)
        if not lits:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "UNPARSEABLE",
                "reason": f"Non-literal format string: {fmt_expr}"
            })
            continue
            
        concat_fmt = "".join(lits)
        num_directives = count_directives(concat_fmt)
        
        if num_directives != num_actual_args:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "MISMATCH",
                "directives": num_directives,
                "args": num_actual_args,
                "reason": f"Format directive count ({num_directives}) != argument count ({num_actual_args})"
            })
        else:
            results.append({
                "line": line_num,
                "func": func_name,
                "status": "MATCH",
                "directives": num_directives,
                "args": num_actual_args
            })
            
    return results, total_calls


SELF_TEST_SUITE = [
    {
        "name": "Known-Good 1: Multi-line call",
        "type": "good",
        "code": """
void test_multiline(FILE *stderr, int p, int v) {
    fprintf(stderr,
        "[io] write 0x%08X = 0x%08X\\n",
        p,
        v);
}
"""
    },
    {
        "name": "Known-Good 2: Adjacent-literal concatenation",
        "type": "good",
        "code": """
void test_concat(unsigned val, int count) {
    printf("a %u " "b %d\\n", val, count);
}
"""
    },
    {
        "name": "Known-Good 3: Ternaries with string literals as args",
        "type": "good",
        "code": """
void test_ternary_arg(FILE *stderr, int active, int mode) {
    fprintf(stderr, "[status] %s mode=%d\\n", active ? "ENABLED" : "DISABLED", mode);
}
"""
    },
    {
        "name": "Known-Good 4: Casts in arguments",
        "type": "good",
        "code": """
void test_casts(char *buf, unsigned x, int y) {
    sprintf(buf, "mask 0x%02X val %u\\n", (unsigned)(x & 3u), (int)y);
}
"""
    },
    {
        "name": "Known-Bad 1: Missing argument (too few args)",
        "type": "bad",
        "code": """
void test_missing_arg(FILE *stderr, int err_code) {
    fprintf(stderr, "[err] code 0x%08X msg %s\\n", err_code);
}
"""
    },
    {
        "name": "Known-Bad 2: Extra argument (too many args)",
        "type": "bad",
        "code": """
void test_extra_arg(int a, int b) {
    printf("val %d\\n", a, b);
}
"""
    },
    {
        "name": "Known-Bad 3: Directive inside %% escape",
        "type": "bad",
        "code": """
void test_pct_escape(FILE *stderr, int x, int y) {
    fprintf(stderr, "percent %%d val %d\\n", x, y);
}
"""
    },
    {
        "name": "Known-Bad 4: Adjacent-literal miscount",
        "type": "bad",
        "code": """
void test_concat_miscount(int arg1, char *arg2) {
    printf("part1 %d " "part2 %s %u\\n", arg1, arg2);
}
"""
    },
    {
        "name": "Sanity-Check: Ignore fprintf inside comments and #if 0",
        "type": "good",
        "code": """
void test_comments(FILE *stderr, int x) {
    /* fprintf(stderr, "bad %d %d\\n", x); */
    // fprintf(stderr, "bad %d %d\\n", x);
#if 0
    fprintf(stderr, "bad %d %d\\n", x);
#endif
    fprintf(stderr, "good %d\\n", x);
}
"""
    }
]


def run_selftest():
    print("=== fmt_parity_audit.py SELF-TEST SUITE ===")
    passed = 0
    failed = 0
    
    for idx, test in enumerate(SELF_TEST_SUITE, 1):
        name = test["name"]
        ttype = test["type"]
        code = test["code"]
        
        results, total_calls = scan_c_file(code)
        mismatches = [r for r in results if r["status"] == "MISMATCH"]
        unparseables = [r for r in results if r["status"] == "UNPARSEABLE"]
        
        test_passed = False
        if ttype == "good":
            if total_calls >= 1 and len(mismatches) == 0 and len(unparseables) == 0:
                test_passed = True
            else:
                detail = f"expected 0 mismatches/unparseables, got {len(mismatches)} mismatches, {len(unparseables)} unparseables"
        elif ttype == "bad":
            if len(mismatches) >= 1:
                test_passed = True
            else:
                detail = f"expected mismatch detection, but got {len(mismatches)} mismatches"
                
        if test_passed:
            print(f"[{idx}/9] PASS: {name}")
            passed += 1
        else:
            print(f"[{idx}/9] FAIL: {name} ({detail})")
            failed += 1
            
    print("==========================================")
    print(f"Self-Test Summary: {passed} PASSED, {failed} FAILED")
    if failed > 0:
        print("SELF-TEST FAILED!")
        sys.exit(1)
    else:
        print("SELF-TEST PASSED SUCCESSFULLY.")
        sys.exit(0)

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        run_selftest()
        
    if len(sys.argv) < 2:
        print("Usage: python3 fmt_parity_audit.py <file.c> | --selftest")
        sys.exit(1)
        
    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)
        
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        
    results, total_calls = scan_c_file(content)
    
    mismatches = [r for r in results if r["status"] == "MISMATCH"]
    unparseables = [r for r in results if r["status"] == "UNPARSEABLE"]
    matches = [r for r in results if r["status"] == "MATCH"]
    
    print(f"Audit Target: {filepath}")
    print(f"Total Calls Analyzed: {total_calls}")
    print(f"  MATCH:       {len(matches)}")
    print(f"  MISMATCH:    {len(mismatches)}")
    print(f"  UNPARSEABLE: {len(unparseables)}")
    print("-" * 60)
    
    if mismatches:
        print("MISMATCHES FOUND:")
        for m in mismatches:
            if "directives" in m:
                print(f"  Line {m['line']:5d}: {m['func']} -> {m['directives']} directives vs {m['args']} args ({m['reason']})")
            else:
                print(f"  Line {m['line']:5d}: {m['func']} -> {m['reason']}")
    else:
        print("STATUS: CLEAN (No format-string parity mismatches found)")
        
    if unparseables:
        print("\nUNPARSEABLE CALLS:")
        for u in unparseables:
            print(f"  Line {u['line']:5d}: {u['func']} -> {u['reason']}")

if __name__ == "__main__":
    main()
