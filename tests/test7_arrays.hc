// Test array subscripting
I64 TestArray() {
  I64 arr[5];
  arr[0] = 10;
  arr[1] = 20;
  return arr[0] + arr[1];
}

I64 SimpleArray(I64 idx) {
  I64 nums[3];
  return nums[idx];
}
