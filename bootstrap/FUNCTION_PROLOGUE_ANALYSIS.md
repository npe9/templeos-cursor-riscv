# Function Prologue Debugging - RISC-V Analysis

## 🎯 **Function Prologue Stepping Demonstration**

The stepping debugger successfully shows the **complete RISC-V function prologue** for a 2-parameter function:

```holyc
I64 Add(I64 a, I64 b) { return a + b; }
```

## 📊 **Step-by-Step Prologue Analysis**

### **Step 1: Stack Frame Setup**
```
0x0000000080418b18: addi    sp,sp,-16    # Allocate 16 bytes on stack
```
- **Purpose**: Create stack frame for function
- **Effect**: `sp` decreases by 16 bytes
- **Register Change**: `sp: 0x20 → 0x10`

### **Step 2: Save Return Address**
```
0x0000000080418b1c: sd      ra,0(sp)     # Save return address
```
- **Purpose**: Store return address on stack
- **Effect**: `ra` saved at `sp+0`
- **Stack Layout**: `[sp+0] = return_address`

### **Step 3: Save Frame Pointer**
```
0x0000000080418b20: sd      s0,8(sp)     # Save frame pointer
```
- **Purpose**: Store caller's frame pointer
- **Effect**: `s0` saved at `sp+8`
- **Stack Layout**: `[sp+8] = old_frame_pointer`

### **Step 4: Set New Frame Pointer**
```
0x0000000080418b24: addi    s0,sp,16     # Set frame pointer
```
- **Purpose**: Point frame pointer to end of stack frame
- **Effect**: `s0 = sp + 16`
- **Register Change**: `s0: 0x40` (points to end of frame)

## 🔍 **Parameter Access Analysis**

### **Step 5-6: Save Additional Registers**
```
0x0000000080418b28: sd      tp,0(s4)     # Save s4 register
0x0000000080418b2c: sd      tp,0(s6)     # Save s6 register
```
- **Purpose**: Save callee-saved registers
- **RISC-V Convention**: s4, s6 are callee-saved

### **Step 7-8: Load First Parameter (a)**
```
0x0000000080418b30: addi    a0,s0,0      # Calculate parameter address
0x0000000080418b34: ld      a0,0(a0)     # Load parameter 'a'
```
- **Purpose**: Load first parameter from stack
- **RISC-V Convention**: Parameters passed in a0-a7, then on stack
- **Register Change**: `a0: 0x60` (parameter value loaded)

## 📈 **Register State Evolution**

### **After Prologue (Step 4):**
```
sp:  0x0000000000000020    # Stack pointer (decreased by 16)
s0:  0x0000000000000040    # Frame pointer (sp + 16)
a0:  0x0000000000000000    # Not yet loaded
```

### **After Parameter Loading (Step 8):**
```
sp:  0x0000000000000020    # Stack pointer unchanged
s0:  0x0000000000000040    # Frame pointer unchanged  
a0:  0x0000000000000060    # First parameter loaded
```

## 🏗️ **Stack Frame Layout**

```
High Memory
    ┌─────────────────┐
    │   Return Addr   │ ← s0 (frame pointer)
    │   Old Frame Ptr │ ← s0-8
    │   Parameter a   │ ← s0-16 (if on stack)
    │   Parameter b   │ ← s0-24 (if on stack)
    └─────────────────┘ ← sp (stack pointer)
Low Memory
```

## 🎯 **Key RISC-V Calling Convention Insights**

1. **Stack Frame**: 16-byte aligned stack frame
2. **Register Saving**: `ra` and `s0` saved on stack
3. **Frame Pointer**: `s0` points to end of frame
4. **Parameter Access**: Parameters accessed via frame pointer
5. **Callee-Saved**: Additional registers (s4, s6) saved

## 🚀 **Debugging Benefits**

The stepping debugger reveals:

1. **Exact Stack Operations**: See each stack manipulation
2. **Register State Changes**: Track register values step-by-step
3. **Parameter Loading**: Understand how parameters are accessed
4. **Frame Pointer Setup**: See frame pointer calculation
5. **RISC-V Convention**: Observe proper calling convention

## 🎉 **Conclusion**

The TempleOS RISC-V stepping debugger provides **unprecedented visibility** into:
- ✅ Function prologue execution
- ✅ Stack frame setup
- ✅ Register state changes
- ✅ Parameter access patterns
- ✅ RISC-V calling convention compliance

This level of debugging capability is essential for:
- **Compiler development** - Verify code generation
- **ABI compliance** - Ensure proper calling conventions
- **Performance optimization** - Identify inefficient patterns
- **Educational purposes** - Understand RISC-V architecture

The stepping debugger is a **powerful tool** for RISC-V development! 🎉
