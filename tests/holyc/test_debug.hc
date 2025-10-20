I64 Test1() { return 42; }
I64 Test2() { return 10+20; }
I64 Test3() { return (10+20); }
I64 Main() {
    I64 r1 = Test1();
    I64 r2 = Test2();
    I64 r3 = Test3();
    return r1 + r2 + r3;
}
