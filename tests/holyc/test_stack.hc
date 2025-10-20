I64 NoParens() { return 10+20; }
I64 WithParens() { return (10+20); }
I64 Main() {
    return NoParens() + WithParens();
}
