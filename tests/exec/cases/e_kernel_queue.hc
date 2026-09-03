// The kernel's doubly-linked-queue intrinsics: QueIns(entry,pred) inserts AFTER the predecessor
// (KernelB.HH), QueInsRev(entry,succ) inserts BEFORE the successor, QueRem unlinks. (These were
// swapped in the runtime — masked whenever only one item is queued, e.g. a lone keydev sink.)
#include "/Kernel/Kernel_RV.PRJ"
class Node
{
  Node *next, *last;
  I64 v;
};

I64 walk(Node *head)
{
  I64 s = 0;
  Node *p = head->next;
  while (p != head) {
    s = s * 10 + p->v;
    p = p->next;
  }
  return s;
}

I64 main()
{
  Node head;
  QueInit(&head);
  Node a, b, c;
  a.v = 1;
  b.v = 2;
  c.v = 3;
  QueIns(&a, &head);
  QueIns(&b, &a);
  QueIns(&c, &b);
  // after: head->a->b->c
  I64 s1 = walk(&head);
  // 123
  QueRem(&b);
  // head->a->c
  I64 s2 = walk(&head);
  // 13
  Node d;
  d.v = 9;
  QueInsRev(&d, &head);
  // before head (tail): head->a->c->d
  I64 s3 = walk(&head);
  // 139
  return (s1 == 123) * 1 + (s2 == 13) * 2 + (s3 == 139) * 4;
  // 7
}
