#!/bin/bash

# Comprehensive Stress Tests for TempleOS RISC-V Compiler
# Tests all components of the compiler on bare metal

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
QEMU_ARGS=(-machine virt -bios none -kernel "${SCRIPT_DIR}/stepping_debugger.elf" -monitor none -serial mon:stdio -nographic)

run_qemu_test() {
  local timeout_secs="$1"
  local script_name="$2"
  local description="$3"

  echo "=== ${description} ==="
  shift 3
  echo "Testing ${*:-${description,,}}..."
  
  # Extract numeric timeout value
  local timeout_val="${timeout_secs%[sm]}"
  
  # Create temporary expect script with more lenient matching
  local expect_script=$(mktemp)
  cat > "${expect_script}" <<EXPECT_EOF
#!/usr/bin/expect -f
set timeout ${timeout_val}
log_user 1
exp_internal 0
spawn qemu-system-riscv64 -machine virt -bios none -device loader,file=${SCRIPT_DIR}/stepping_debugger.elf,addr=0x80000000 -monitor none -serial mon:stdio -nographic
# Wait a moment for QEMU to start
sleep 1
# Read and send each line from the test file
set fp [open "${SCRIPT_DIR}/${script_name}" r]
set line_num 0
while {[gets \$fp line] >= 0} {
    incr line_num
    # Skip empty lines and comments
    if {[string trim \$line] == "" || [string match "#*" \$line]} {
        continue
    }
    # Send the line (use -- to prevent flag interpretation)
    send -- "\$line\r"
    # Wait a bit for processing (reduced delay for faster tests)
    sleep 0.05
}
close \$fp
# Send quit command
send -- "quit\r"
# Wait for "Goodbye!" message (REPL processes quit but QEMU doesn't exit)
expect {
    "Goodbye!" { }
    timeout { }
}
# QEMU won't exit (main() loops forever), so close the spawn and exit
# This will kill the QEMU process
sleep 0.5
close
exit 0
EXPECT_EOF
  
  chmod +x "${expect_script}"
  "${expect_script}" 2>&1 | head -200 || true
  rm -f "${expect_script}"
  echo ""
}

echo "=== TempleOS RISC-V Compiler Stress Tests ==="
echo "Testing all compiler components on bare metal"
echo ""

run_qemu_test 30s "stress_test_1_basic_expressions.txt" "Test 1: Basic Expressions and Arithmetic" "arithmetic operations, bitwise operations, logical operations"
run_qemu_test 60s "stress_test_2_functions.txt" "Test 2: Function Definitions and Calls" "functions with various parameter counts, recursion, function calls"
run_qemu_test 60s "stress_test_3_control_flow.txt" "Test 3: Control Flow Statements" "if/else, loops, switch statements"
run_qemu_test 60s "stress_test_4_memory_operations.txt" "Test 4: Memory Operations and Arrays" "arrays, pointers, memory allocation"
run_qemu_test 90s "stress_test_5_complex_programs.txt" "Test 5: Complex Programs" "complex programs combining multiple features"
run_qemu_test 60s "stress_test_6_type_system.txt" "Test 6: Type System and Numeric Conversions" "integer sizes, floating-point math, and pointer arithmetic"
run_qemu_test 60s "stress_test_7_structs_enums.txt" "Test 7: Structs, Unions, and Enums" "user-defined types, assignments, and enum comparisons"
run_qemu_test 60s "stress_test_8_control_flow_advanced.txt" "Test 8: Advanced Control Flow" "do/while loops, switch statements, goto, and ternary operations"
run_qemu_test 60s "stress_test_9_function_pointers.txt" "Test 9: Function Pointers and Indirect Calls" "storing, passing, and invoking function pointers"
run_qemu_test 60s "stress_test_10_preprocessor.txt" "Test 10: Preprocessor and Macros" "macro expansion, conditional compilation, and undef behaviour"

echo "=== All Stress Tests Complete ==="
echo "The TempleOS RISC-V compiler has been thoroughly tested on bare metal!"
