#!/bin/bash
echo "═══════════════════════════════════════════════════════════"
echo "1:1 AUDIT: My Implementation vs Original TempleOS"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "Original TempleOS Compiler Line Counts:"
wc -l Compiler/Lex.HC Compiler/PrsExp.HC Compiler/PrsStmt.HC Compiler/PrsVar.HC Compiler/CHash.HC | tail -1
echo ""

echo "My C Implementation Line Counts:"
wc -l lexer.c parser.c compiler.c hash_table.c hash_table.h | tail -1
echo ""

echo "Checking what's in the original but not in mine..."
echo ""
