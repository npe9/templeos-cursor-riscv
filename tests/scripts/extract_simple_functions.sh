#!/bin/bash
# Extract simple I64 functions from TempleOS source

echo "Looking for simple I64 functions in Demo/*.HC..."
for file in Demo/*.HC Demo/*/*.HC; do
    # Extract functions with I64 return type
    grep -A 10 "^I64 " "$file" 2>/dev/null | head -20
done | head -100
