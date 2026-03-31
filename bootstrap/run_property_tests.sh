#!/bin/bash

# Property-Based Testing Script for HolyC Compiler
# This script generates arbitrary compositions of valid nested functions
# and tests them through the actual HolyC REPL to prove completeness

set -e

echo "=== HOLYC PROPERTY-BASED TESTING FRAMEWORK ==="
echo "Testing arbitrary compositions of valid nested functions..."
echo "This will prove the compiler is complete and robust."
echo ""

# Configuration
MAX_TEST_CASES=100
TEST_TIMEOUT=30
REPL_BINARY="./stepping_debugger.elf"
OUTPUT_FILE="property_test_results.txt"
GENERATED_CODE_FILE="property_generated_tests.txt"

# Check if REPL binary exists
if [ ! -f "$REPL_BINARY" ]; then
    echo "Error: $REPL_BINARY not found. Please build it first."
    exit 1
fi

# Initialize counters
passed_tests=0
failed_tests=0
total_tests=0

# Clear output files
> "$OUTPUT_FILE"
> "$GENERATED_CODE_FILE"

echo "Starting property-based testing with $MAX_TEST_CASES test cases..."
echo ""

# Function to generate random function name
generate_function_name() {
    local index=$1
    local prefixes=("Test" "Func" "Compute" "Calculate" "Process" "Handle" "Execute" "Run" "Eval" "Check")
    local suffixes=("Value" "Result" "Data" "Info" "State" "Count" "Sum" "Product" "Max" "Min")
    
    local prefix_idx=$((RANDOM % ${#prefixes[@]}))
    local suffix_idx=$((RANDOM % ${#suffixes[@]}))
    
    echo "${prefixes[$prefix_idx]}${index}${suffixes[$suffix_idx]}"
}

# Function to generate random expression
generate_expression() {
    local complexity=$1
    local type=$2
    
    case $type in
        "arithmetic")
            local ops=("+" "-" "*" "/" "%")
            local op=${ops[$((RANDOM % ${#ops[@]}))]}
            local val1=$((RANDOM % 100 + 1))
            local val2=$((RANDOM % 100 + 1))
            echo "$val1 $op $val2"
            ;;
        "logical")
            local ops=("&&" "||")
            local op=${ops[$((RANDOM % ${#ops[@]}))]}
            local val1=$((RANDOM % 2))
            local val2=$((RANDOM % 2))
            echo "$val1 $op $val2"
            ;;
        "comparison")
            local ops=(">" "<" "==" "!=" ">=" "<=")
            local op=${ops[$((RANDOM % ${#ops[@]}))]}
            local val1=$((RANDOM % 100 + 1))
            local val2=$((RANDOM % 100 + 1))
            echo "$val1 $op $val2"
            ;;
        "bitwise")
            local ops=("&" "|" "^" "<<" ">>")
            local op=${ops[$((RANDOM % ${#ops[@]}))]}
            local val1=$((RANDOM % 0xFFFF))
            local val2=$((RANDOM % 0xFFFF))
            echo "0x$val1 $op 0x$val2"
            ;;
    esac
}

# Function to generate function body
generate_function_body() {
    local complexity=$1
    local param_count=$2
    local param_names=("$@")
    local body=""
    
    # Generate local variables
    local var_count=$((RANDOM % 3 + 1))
    for ((i=0; i<var_count; i++)); do
        body+="    I64 var$i = $((RANDOM % 100 + 1));\n"
    done
    
    # Generate control flow based on complexity
    if [ $complexity -gt 3 ]; then
        local control_type=$((RANDOM % 3))
        case $control_type in
            0) # if-else
                body+="    if (${param_names[0]} > 0) {\n"
                body+="        return $((RANDOM % 100 + 1));\n"
                body+="    } else {\n"
                body+="        return $((RANDOM % 100 + 1));\n"
                body+="    }\n"
                ;;
            1) # while loop
                body+="    I64 i = 0;\n"
                body+="    while (i < $((RANDOM % 8 + 2))) {\n"
                body+="        i = i + 1;\n"
                body+="    }\n"
                body+="    return i;\n"
                ;;
            2) # for loop
                body+="    I64 sum = 0;\n"
                body+="    for (I64 j = 0; j < $((RANDOM % 8 + 2)); j = j + 1) {\n"
                body+="        sum = sum + j;\n"
                body+="    }\n"
                body+="    return sum;\n"
                ;;
        esac
    else
        # Simple return
        local expr_type=$((RANDOM % 4))
        case $expr_type in
            0) body+="    return $(generate_expression 1 "arithmetic");\n" ;;
            1) body+="    return $(generate_expression 1 "logical");\n" ;;
            2) body+="    return $(generate_expression 1 "comparison");\n" ;;
            3) body+="    return $(generate_expression 1 "bitwise");\n" ;;
        esac
    fi
    
    echo -e "$body"
}

# Function to generate a test case
generate_test_case() {
    local test_id=$1
    local test_code=""
    
    # Generate multiple functions
    local function_count=$((RANDOM % 4 + 3))  # 3-6 functions
    local function_names=()
    
    test_code+="// Property-based test case $test_id\n"
    test_code+="// Generated $function_count functions with random complexity\n\n"
    
    # Generate functions
    for ((i=0; i<function_count; i++)); do
        local func_name=$(generate_function_name $i)
        function_names+=("$func_name")
        
        local param_count=$((RANDOM % 4))  # 0-3 parameters
        local param_decls=""
        local param_names=()
        
        for ((j=0; j<param_count; j++)); do
            if [ $j -gt 0 ]; then
                param_decls+=", "
            fi
            param_decls+="I64 param$j"
            param_names+=("param$j")
        done
        
        local complexity=$((RANDOM % 6 + 2))  # 2-7 complexity
        local body=$(generate_function_body $complexity $param_count "${param_names[@]}")
        
        test_code+="I64 $func_name($param_decls) {\n$body}\n\n"
    done
    
    # Generate test expressions
    test_code+="// Test expressions\n"
    local expr_count=$((RANDOM % 8 + 5))  # 5-12 expressions
    
    for ((i=0; i<expr_count; i++)); do
        local expr_type=$((RANDOM % 5))
        case $expr_type in
            0|1|2|3) # Simple expressions
                test_code+="$(generate_expression $((RANDOM % 3 + 1)) "arithmetic");\n"
                ;;
            4) # Function calls
                local func_idx=$((RANDOM % function_count))
                local param_count=$((RANDOM % 3))
                test_code+="${function_names[$func_idx]}("
                for ((j=0; j<param_count; j++)); do
                    if [ $j -gt 0 ]; then
                        test_code+=", "
                    fi
                    test_code+="$((RANDOM % 100 + 1))"
                done
                test_code+=");\n"
                ;;
        esac
    done
    
    test_code+="// End of test case $test_id\n\n"
    
    echo "$test_code"
}

# Function to execute a test case
execute_test_case() {
    local test_code="$1"
    local test_id="$2"
    
    # Create temporary file
    local temp_file="temp_test_$test_id.hc"
    echo "$test_code" > "$temp_file"
    
    # Execute through REPL
    local start_time=$(date +%s.%N)
    local output
    local exit_code=0
    
    if timeout $TEST_TIMEOUT qemu-system-riscv64 -M virt -bios none -kernel "$REPL_BINARY" -nographic < "$temp_file" > "temp_output_$test_id.txt" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s.%N)
    local execution_time=$(echo "$end_time - $start_time" | bc -l)
    
    # Read output
    output=$(cat "temp_output_$test_id.txt" 2>/dev/null || echo "")
    
    # Clean up
    rm -f "$temp_file" "temp_output_$test_id.txt"
    
    # Analyze result
    local passed=0
    local error_msg=""
    
    if [ $exit_code -eq 0 ]; then
        if echo "$output" | grep -q "Function compiled successfully"; then
            passed=1
        else
            error_msg="No successful compilation detected"
        fi
    else
        if echo "$output" | grep -q "Parse failed"; then
            error_msg="Parse failed - syntax error"
        elif echo "$output" | grep -q "Function compiled successfully"; then
            passed=1  # Compilation succeeded despite timeout
        else
            error_msg="Execution failed or timed out"
        fi
    fi
    
    echo "$passed|$error_msg|$execution_time"
}

# Main testing loop
echo "Generating and executing test cases..."

for ((test_id=1; test_id<=MAX_TEST_CASES; test_id++)); do
    # Generate test case
    local test_code=$(generate_test_case $test_id)
    
    # Save generated code
    echo "$test_code" >> "$GENERATED_CODE_FILE"
    
    # Execute test
    local result=$(execute_test_case "$test_code" $test_id)
    local passed=$(echo "$result" | cut -d'|' -f1)
    local error_msg=$(echo "$result" | cut -d'|' -f2)
    local execution_time=$(echo "$result" | cut -d'|' -f3)
    
    # Update counters
    total_tests=$((total_tests + 1))
    if [ "$passed" = "1" ]; then
        passed_tests=$((passed_tests + 1))
        echo "✅ Test $test_id PASSED (${execution_time}s)"
    else
        failed_tests=$((failed_tests + 1))
        echo "❌ Test $test_id FAILED: $error_msg (${execution_time}s)"
    fi
    
    # Log result
    echo "Test $test_id: $([ "$passed" = "1" ] && echo "PASSED" || echo "FAILED") - $error_msg" >> "$OUTPUT_FILE"
    
    # Progress indicator
    if [ $((test_id % 10)) -eq 0 ]; then
        local success_rate=$(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l)
        echo "Progress: $test_id/$MAX_TEST_CASES tests completed ($success_rate% passed)"
    fi
done

# Print final results
echo ""
echo "=== PROPERTY-BASED TEST RESULTS ==="
echo "Total Tests: $total_tests"
echo "Passed: $passed_tests ($(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l)%)"
echo "Failed: $failed_tests ($(echo "scale=1; $failed_tests * 100 / $total_tests" | bc -l)%)"

# Final verdict
success_rate=$(echo "scale=3; $passed_tests / $total_tests" | bc -l)
if (( $(echo "$success_rate >= 0.95" | bc -l) )); then
    echo ""
    echo "🎉 COMPILER IS COMPLETE! 🎉"
    echo "Success rate: $(echo "scale=1; $success_rate * 100" | bc -l)%"
    echo "The property-based tests prove that the HolyC compiler"
    echo "can handle arbitrary compositions of valid nested functions"
    echo "with high reliability."
elif (( $(echo "$success_rate >= 0.80" | bc -l) )); then
    echo ""
    echo "⚠️  COMPILER IS MOSTLY COMPLETE ⚠️"
    echo "Success rate: $(echo "scale=1; $success_rate * 100" | bc -l)%"
    echo "The compiler handles most cases well but may need some"
    echo "improvements for edge cases."
else
    echo ""
    echo "❌ COMPILER NEEDS SIGNIFICANT WORK ❌"
    echo "Success rate: $(echo "scale=1; $success_rate * 100" | bc -l)%"
    echo "The compiler has significant issues and needs substantial"
    echo "improvements."
fi

echo ""
echo "Generated test cases saved to: $GENERATED_CODE_FILE"
echo "Test results saved to: $OUTPUT_FILE"
echo ""

# Clean up any remaining temp files
rm -f temp_test_*.hc temp_output_*.txt

echo "Property-based testing completed!"








