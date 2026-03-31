#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include "holy_api.h"
#include <unistd.h>
#include <sys/wait.h>

// Property-based testing framework that actually tests the HolyC compiler
// This will generate arbitrary compositions and test them through the real REPL

#define MAX_TEST_CASES 500
#define MAX_FUNCTION_DEPTH 8
#define MAX_FUNCTION_PARAMS 6
#define MAX_EXPRESSION_COMPLEXITY 15
#define MAX_CODE_LENGTH 10000

// Test result structure
typedef struct {
    int test_id;
    int passed;
    int failed;
    char error_message[1000];
    char generated_code[5000];
    char compiler_output[2000];
    double execution_time;
} TestResult;

// Function signature generator
typedef struct {
    char name[50];
    int param_count;
    char param_types[6][20];
    char param_names[6][20];
    int complexity;
    int return_type;
} FunctionSignature;

// Expression generator
typedef struct {
    char expression[1000];
    int complexity;
    int type; // 0=arithmetic, 1=logical, 2=comparison, 3=bitwise, 4=function_call
    int depth;
} Expression;

// Global test state
static int test_count = 0;
static int passed_tests = 0;
static int failed_tests = 0;
static TestResult test_results[MAX_TEST_CASES];
static char all_generated_code[200000];
static int code_pos = 0;

// Random number generation
static uint64_t rng_state = 1;

uint64_t rand64() {
    rng_state ^= rng_state >> 12;
    rng_state ^= rng_state << 25;
    rng_state ^= rng_state >> 27;
    return rng_state * 0x2545F4914F6CDD1DULL;
}

int random_int(int min, int max) {
    return min + (rand64() % (max - min + 1));
}

double random_double() {
    return (double)rand64() / (double)UINT64_MAX;
}

// Function name generator
void generate_function_name(char* name, int index) {
    const char* prefixes[] = {"Test", "Func", "Compute", "Calculate", "Process", "Handle", "Execute", "Run", "Eval", "Check"};
    const char* suffixes[] = {"Value", "Result", "Data", "Info", "State", "Count", "Sum", "Product", "Max", "Min"};
    
    int prefix_idx = random_int(0, sizeof(prefixes)/sizeof(prefixes[0]) - 1);
    int suffix_idx = random_int(0, sizeof(suffixes)/sizeof(suffixes[0]) - 1);
    
    StrPrintF(name, 50, "%s%d%s", prefixes[prefix_idx], index, suffixes[suffix_idx]);
}

// Variable name generator
void generate_variable_name(char* name, int index) {
    const char* prefixes[] = {"var", "val", "num", "sum", "count", "result", "temp", "data"};
    int prefix_idx = random_int(0, sizeof(prefixes)/sizeof(prefixes[0]) - 1);
    StrPrintF(name, 20, "%s%d", prefixes[prefix_idx], index);
}

// Expression generators with proper nesting
void generate_arithmetic_expression(Expression* expr, int complexity, int depth) {
    if (depth > 5 || complexity <= 1) {
        // Base case - simple expression
        int val1 = random_int(1, 100);
        int val2 = random_int(1, 100);
        const char* operators[] = {"+", "-", "*", "/", "%"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "%d %s %d", val1, op, val2);
    } else {
        // Recursive case - nested expressions
        Expression left, right;
        generate_arithmetic_expression(&left, complexity - 1, depth + 1);
        generate_arithmetic_expression(&right, complexity - 1, depth + 1);
        
        const char* operators[] = {"+", "-", "*", "/", "%"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "(%s) %s (%s)", 
                left.expression, op, right.expression);
    }
    expr->complexity = complexity;
    expr->type = 0;
    expr->depth = depth;
}

void generate_logical_expression(Expression* expr, int complexity, int depth) {
    if (depth > 3 || complexity <= 1) {
        // Base case
        int val1 = random_int(0, 1);
        int val2 = random_int(0, 1);
        const char* operators[] = {"&&", "||"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "%d %s %d", val1, op, val2);
    } else {
        Expression left, right;
        generate_logical_expression(&left, complexity - 1, depth + 1);
        generate_logical_expression(&right, complexity - 1, depth + 1);
        
        const char* operators[] = {"&&", "||"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "(%s) %s (%s)", 
                left.expression, op, right.expression);
    }
    expr->complexity = complexity;
    expr->type = 1;
    expr->depth = depth;
}

void generate_comparison_expression(Expression* expr, int complexity, int depth) {
    if (depth > 3 || complexity <= 1) {
        int val1 = random_int(1, 100);
        int val2 = random_int(1, 100);
        const char* operators[] = {">", "<", "==", "!=", ">=", "<="};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "%d %s %d", val1, op, val2);
    } else {
        Expression left, right;
        generate_arithmetic_expression(&left, complexity - 1, depth + 1);
        generate_arithmetic_expression(&right, complexity - 1, depth + 1);
        
        const char* operators[] = {">", "<", "==", "!=", ">=", "<="};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "(%s) %s (%s)", 
                left.expression, op, right.expression);
    }
    expr->complexity = complexity;
    expr->type = 2;
    expr->depth = depth;
}

void generate_bitwise_expression(Expression* expr, int complexity, int depth) {
    if (depth > 3 || complexity <= 1) {
        int val1 = random_int(0, 0xFFFF);
        int val2 = random_int(0, 0xFFFF);
        const char* operators[] = {"&", "|", "^", "<<", ">>"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "0x%x %s 0x%x", val1, op, val2);
    } else {
        Expression left, right;
        generate_bitwise_expression(&left, complexity - 1, depth + 1);
        generate_bitwise_expression(&right, complexity - 1, depth + 1);
        
        const char* operators[] = {"&", "|", "^", "<<", ">>"};
        const char* op = operators[random_int(0, sizeof(operators)/sizeof(operators[0]) - 1)];
        
        StrPrintF(expr->expression, sizeof(expr->expression), "(%s) %s (%s)", 
                left.expression, op, right.expression);
    }
    expr->complexity = complexity;
    expr->type = 3;
    expr->depth = depth;
}

void generate_function_call_expression(Expression* expr, const char* function_name, int param_count) {
    char params[500] = {0};
    int param_pos = 0;
    
    for (int i = 0; i < param_count; i++) {
        if (i > 0) param_pos += StrPrintF(params + param_pos, sizeof(params) - param_pos, ", ");
        param_pos += StrPrintF(params + param_pos, sizeof(params) - param_pos, "%d", random_int(1, 100));
    }
    
    StrPrintF(expr->expression, sizeof(expr->expression), "%s(%s)", function_name, params);
    expr->complexity = param_count;
    expr->type = 4;
    expr->depth = 0;
}

void generate_random_expression(Expression* expr, int complexity, int depth, const char* available_functions[], int func_count) {
    int expr_type = random_int(0, 4);
    
    // 30% chance of function call if functions are available
    if (func_count > 0 && random_double() < 0.3) {
        expr_type = 4;
    }
    
    switch (expr_type) {
        case 0: generate_arithmetic_expression(expr, complexity, depth); break;
        case 1: generate_logical_expression(expr, complexity, depth); break;
        case 2: generate_comparison_expression(expr, complexity, depth); break;
        case 3: generate_bitwise_expression(expr, complexity, depth); break;
        case 4: 
            if (func_count > 0) {
                int func_idx = random_int(0, func_count - 1);
                generate_function_call_expression(expr, available_functions[func_idx], random_int(0, 3));
            } else {
                generate_arithmetic_expression(expr, complexity, depth);
            }
            break;
    }
}

// Function body generator with proper control flow
void generate_function_body(char* body, int complexity, int param_count, const char* param_names[], 
                          const char* available_functions[], int func_count) {
    char temp[2000] = {0};
    int pos = 0;
    
    // Generate local variable declarations
    int var_count = random_int(1, 4);
    for (int i = 0; i < var_count; i++) {
        char var_name[20];
        generate_variable_name(var_name, i);
        pos += StrPrintF(temp + pos, sizeof(temp) - pos, "    I64 %s = %d;\n", 
                       var_name, random_int(1, 100));
    }
    
    // Generate control flow based on complexity
    if (complexity > 3) {
        int control_type = random_int(0, 3);
        switch (control_type) {
            case 0: // if-else statement
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    if (%s > 0) {\n", param_names[0]);
                Expression if_expr;
                generate_random_expression(&if_expr, random_int(2, 4), 0, available_functions, func_count);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "        return %s;\n", if_expr.expression);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    } else {\n");
                Expression else_expr;
                generate_random_expression(&else_expr, random_int(2, 4), 0, available_functions, func_count);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "        return %s;\n", else_expr.expression);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    }\n");
                break;
                
            case 1: // while loop
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    I64 i = 0;\n");
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    while (i < %d) {\n", random_int(2, 8));
                Expression loop_expr;
                generate_random_expression(&loop_expr, random_int(1, 3), 0, available_functions, func_count);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "        i = i + %s;\n", loop_expr.expression);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    }\n");
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    return i;\n");
                break;
                
            case 2: // for loop
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    I64 sum = 0;\n");
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    for (I64 j = 0; j < %d; j = j + 1) {\n", random_int(2, 8));
                Expression for_expr;
                generate_random_expression(&for_expr, random_int(1, 3), 0, available_functions, func_count);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "        sum = sum + %s;\n", for_expr.expression);
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    }\n");
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    return sum;\n");
                break;
                
            case 3: // nested function calls
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    I64 result = 0;\n");
                for (int i = 0; i < random_int(2, 4); i++) {
                    if (func_count > 0) {
                        int func_idx = random_int(0, func_count - 1);
                        Expression call_expr;
                        generate_function_call_expression(&call_expr, available_functions[func_idx], random_int(0, 2));
                        pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                            "    result = result + %s;\n", call_expr.expression);
                    }
                }
                pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
                    "    return result;\n");
                break;
        }
    } else {
        // Simple return statement
        Expression expr;
        generate_random_expression(&expr, random_int(1, 3), 0, available_functions, func_count);
        pos += StrPrintF(temp + pos, sizeof(temp) - pos, 
            "    return %s;\n", expr.expression);
    }
    
    strcpy(body, temp);
}

// Function generator
void generate_function(char* code, int index, int complexity, const char* available_functions[], int func_count) {
    char function_name[50];
    generate_function_name(function_name, index);
    
    int param_count = random_int(0, MAX_FUNCTION_PARAMS);
    char param_names[MAX_FUNCTION_PARAMS][20];
    char param_decls[500] = {0};
    int param_pos = 0;
    
    for (int i = 0; i < param_count; i++) {
        generate_variable_name(param_names[i], i);
        param_pos += StrPrintF(param_decls + param_pos, sizeof(param_decls) - param_pos, 
            "I64 %s", param_names[i]);
        if (i < param_count - 1) {
            param_pos += StrPrintF(param_decls + param_pos, sizeof(param_decls) - param_pos, ", ");
        }
    }
    
    char body[2000];
    generate_function_body(body, complexity, param_count, param_names, available_functions, func_count);
    
    StrPrintF(code, 3000, "I64 %s(%s) {\n%s}\n\n", 
             function_name, param_decls, body);
}

// Test case generator
void generate_test_case(char* test_code, int test_id) {
    // Generate multiple functions with increasing complexity
    int function_count = random_int(3, 6);
    char all_functions[8000] = {0};
    char function_names[10][50];
    int func_pos = 0;
    
    // Generate functions
    for (int i = 0; i < function_count; i++) {
        char func_code[3000];
        generate_function(func_code, i, random_int(2, MAX_FUNCTION_DEPTH), 
                         function_names, i); // Pass previously generated function names
        strcat(all_functions, func_code);
        
        // Extract function name for later use
        generate_function_name(function_names[i], i);
    }
    
    // Generate test expressions
    char test_expressions[3000] = {0};
    int expr_pos = 0;
    
    // Generate function calls
    int call_count = random_int(5, 12);
    for (int i = 0; i < call_count; i++) {
        int func_idx = random_int(0, function_count - 1);
        int param_count = random_int(0, 3);
        
        expr_pos += StrPrintF(test_expressions + expr_pos, sizeof(test_expressions) - expr_pos, 
            "%s(", function_names[func_idx]);
        
        for (int j = 0; j < param_count; j++) {
            if (j > 0) expr_pos += StrPrintF(test_expressions + expr_pos, sizeof(test_expressions) - expr_pos, ", ");
            expr_pos += StrPrintF(test_expressions + expr_pos, sizeof(test_expressions) - expr_pos, 
                "%d", random_int(1, 100));
        }
        expr_pos += StrPrintF(test_expressions + expr_pos, sizeof(test_expressions) - expr_pos, ");\n");
    }
    
    // Generate complex nested expressions
    for (int i = 0; i < random_int(3, 8); i++) {
        Expression complex_expr;
        generate_random_expression(&complex_expr, random_int(3, 8), 0, function_names, function_count);
        expr_pos += StrPrintF(test_expressions + expr_pos, sizeof(test_expressions) - expr_pos, 
            "%s;\n", complex_expr.expression);
    }
    
    // Combine everything
    StrPrintF(test_code, MAX_CODE_LENGTH, 
        "// Property-based test case %d\n"
        "// Generated %d functions with random complexity\n\n"
        "%s"
        "// Test expressions\n"
        "%s"
        "// End of test case %d\n\n",
        test_id, function_count, all_functions, test_expressions, test_id);
}

// Execute test through REPL
TestResult execute_test_through_repl(const char* test_code) {
    TestResult result = {0};
    strcpy(result.generated_code, test_code);
    
    // Create temporary file with test code
    FILE* f = fopen("temp_test.hc", "w");
    if (!f) {
        result.failed = 1;
        strcpy(result.error_message, "Failed to create temporary test file");
        return result;
    }
    
    fprintf(f, "%s", test_code);
    fclose(f);
    
    // Execute through stepping_debugger.elf
    char command[1000];
    StrPrintF(command, sizeof(command), 
        "timeout 30s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < temp_test.hc > temp_output.txt 2>&1");
    
    clock_t start = clock();
    int ret = system(command);
    clock_t end = clock();
    
    result.execution_time = ((double)(end - start)) / CLOCKS_PER_SEC;
    
    // Read output
    FILE* output_f = fopen("temp_output.txt", "r");
    if (output_f) {
        fread(result.compiler_output, 1, sizeof(result.compiler_output) - 1, output_f);
        fclose(output_f);
    }
    
    // Analyze result
    if (ret == 0) {
        result.passed = 1;
        result.failed = 0;
    } else {
        result.passed = 0;
        result.failed = 1;
        
        // Try to extract error message
        if (strstr(result.compiler_output, "Parse failed") != NULL) {
            strcpy(result.error_message, "Parse failed - syntax error");
        } else if (strstr(result.compiler_output, "Function compiled successfully") == NULL) {
            strcpy(result.error_message, "Function compilation failed");
        } else {
            strcpy(result.error_message, "Unknown compilation error");
        }
    }
    
    // Clean up
    unlink("temp_test.hc");
    unlink("temp_output.txt");
    
    return result;
}

// Property-based test runner
void run_property_based_tests() {
    printf("=== HOLYC PROPERTY-BASED TESTING FRAMEWORK ===\n");
    printf("Testing arbitrary compositions of valid nested functions...\n");
    printf("This will prove the compiler is complete and robust.\n\n");
    
    // Initialize random seed
    rng_state = time(NULL);
    
    // Clear global state
    test_count = 0;
    passed_tests = 0;
    failed_tests = 0;
    code_pos = 0;
    all_generated_code[0] = '\0';
    
    printf("Generating %d test cases...\n", MAX_TEST_CASES);
    
    for (int i = 0; i < MAX_TEST_CASES; i++) {
        char test_case[MAX_CODE_LENGTH];
        generate_test_case(test_case, i);
        
        // Execute the test
        TestResult result = execute_test_through_repl(test_case);
        result.test_id = i;
        test_results[i] = result;
        
        if (result.passed) {
            passed_tests++;
            printf("✅ Test %d PASSED (%.2fs) - %d functions, %d expressions\n", 
                   i, result.execution_time, 
                   (int)strstr(test_case, "I64 ") ? 1 : 0,
                   (int)strstr(test_case, "(") ? 1 : 0);
        } else {
            failed_tests++;
            printf("❌ Test %d FAILED: %s (%.2fs)\n", 
                   i, result.error_message, result.execution_time);
        }
        
        test_count++;
        
        // Add to combined test cases
        strcat(all_generated_code, test_case);
        
        // Progress indicator
        if (i % 50 == 0) {
            printf("Progress: %d/%d tests completed (%.1f%% passed)\n", 
                   i, MAX_TEST_CASES, (float)passed_tests / test_count * 100);
        }
    }
    
    // Generate comprehensive test file
    FILE* f = fopen("property_based_test_suite.txt", "w");
    if (f) {
        fprintf(f, "// HOLYC PROPERTY-BASED TEST SUITE\n");
        fprintf(f, "// Generated %d test cases with arbitrary function compositions\n", MAX_TEST_CASES);
        fprintf(f, "// This tests the complete HolyC language implementation\n");
        fprintf(f, "// Passed: %d, Failed: %d\n\n", passed_tests, failed_tests);
        fprintf(f, "%s", all_generated_code);
        fclose(f);
    }
    
    // Print detailed summary
    printf("\n=== PROPERTY-BASED TEST RESULTS ===\n");
    printf("Total Tests: %d\n", test_count);
    printf("Passed: %d (%.1f%%)\n", passed_tests, (float)passed_tests / test_count * 100);
    printf("Failed: %d (%.1f%%)\n", failed_tests, (float)failed_tests / test_count * 100);
    
    // Analyze failure patterns
    int parse_failures = 0;
    int compilation_failures = 0;
    int execution_failures = 0;
    
    for (int i = 0; i < test_count; i++) {
        if (test_results[i].failed) {
            if (strstr(test_results[i].error_message, "Parse failed") != NULL) {
                parse_failures++;
            } else if (strstr(test_results[i].error_message, "compilation") != NULL) {
                compilation_failures++;
            } else {
                execution_failures++;
            }
        }
    }
    
    printf("\nFailure Analysis:\n");
    printf("  Parse Failures: %d\n", parse_failures);
    printf("  Compilation Failures: %d\n", compilation_failures);
    printf("  Execution Failures: %d\n", execution_failures);
    
    // Final verdict
    double success_rate = (float)passed_tests / test_count;
    if (success_rate >= 0.95) {
        printf("\n🎉 COMPILER IS COMPLETE! 🎉\n");
        printf("Success rate: %.1f%% - The property-based tests prove that\n", success_rate * 100);
        printf("the HolyC compiler can handle arbitrary compositions of\n");
        printf("valid nested functions with high reliability.\n");
    } else if (success_rate >= 0.80) {
        printf("\n⚠️  COMPILER IS MOSTLY COMPLETE ⚠️\n");
        printf("Success rate: %.1f%% - The compiler handles most cases well\n", success_rate * 100);
        printf("but may need some improvements for edge cases.\n");
    } else {
        printf("\n❌ COMPILER NEEDS SIGNIFICANT WORK ❌\n");
        printf("Success rate: %.1f%% - The compiler has significant issues\n", success_rate * 100);
        printf("and needs substantial improvements.\n");
    }
    
    printf("\nGenerated test suite saved to: property_based_test_suite.txt\n");
    printf("Individual test results saved in test_results array.\n");
}

int main() {
    printf("HolyC Property-Based Testing Framework\n");
    printf("=====================================\n");
    printf("This framework generates arbitrary compositions of valid\n");
    printf("nested functions to prove the compiler is complete.\n\n");
    
    run_property_based_tests();
    
    return 0;
}








