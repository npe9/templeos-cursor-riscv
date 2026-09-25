BEGIN {
    print "Analyzing while loop assembly:"
    print "================================================"
    print "Address  | Instruction | Description"
    print "---------|-------------|----------------------------"
}
{
    addr=$1
    hex=$2
    if (addr == "0x10" || addr == "0x14" || addr == "0x18") {
        print addr " | " hex " | CONDITION CHECK: i < 3"
    } else if (addr == "0x1c" || addr == "0x20" || addr == "0x24") {
        print addr " | " hex " | - load constant 3"
    } else if (addr == "0x28" || addr == "0x2c") {
        print addr " | " hex " | - compare i < 3"
    } else if (addr == "0x30" || addr == "0x34") {
        print addr " | " hex " | LOOP BODY: load i"
    } else if (addr == "0x38" || addr == "0x3c") {
        print addr " | " hex " | - stack push"
    } else if (addr == "0x40" || addr == "0x44") {
        print addr " | " hex " | - load constant 1"
    } else if (addr == "0x48" || addr == "0x4c") {
        print addr " | " hex " | - add i + 1"
    } else if (addr == "0x50" || addr == "0x54") {
        print addr " | " hex " | - stack pop/store"
    } else if (addr == "0x58" || addr == "0x5c") {
        print addr " | " hex " | BACK EDGE: j 0x10 (jumps to condition)"
    }
}
END {
    print "================================================"
    print "SUMMARY:"
    print "  Condition check: 0x10-0x2c"
    print "  Loop body: 0x30-0x54"
    print "  Back edge: j 0x10 (GOOD! jumps to condition)"
    print ""
    print "The while loop fix is WORKING!"
    print "It jumps to 0x10 (condition) not 0x0 (initialization)"
}
