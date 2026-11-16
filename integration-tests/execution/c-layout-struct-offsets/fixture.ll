; The foreign side of the c-layout-struct-offsets test. Every field is
; reached by its byte offset as C lays the struct out, never through an
; LLVM struct type, so a ghul layout that differs from C's reads or writes
; the wrong bytes.
;
;   struct mix   { int8_t a; int16_t b; int32_t c; double d;
;                  uint8_t e; float f; int64_t g; }        a 0, b 2, c 4,
;                                                           d 8, e 16, f 20,
;                                                           g 24; size 32
;   struct outer { uint8_t tag; struct mix m; uint16_t tail; }
;                                                           tag 0, m 8,
;                                                           tail 40; size 48
;   struct pair  { int32_t x; int32_t y; }                  x 0, y 4; size 8
;   struct refs  { int32_t a; void *text; bool flag; void *same; }
;                                                           a 0, text 8,
;                                                           flag 16, same 24;
;                                                           size 32
;
; Built by build/llvm-test-objects.sh, which the llvm test runs need first.

@fx_kept = global [32 x i8] zeroinitializer, align 8

define void @fx_fill_mix(ptr %p) {
  store i8 -3, ptr %p, align 1
  %b = getelementptr i8, ptr %p, i64 2
  store i16 -300, ptr %b, align 2
  %c = getelementptr i8, ptr %p, i64 4
  store i32 70000, ptr %c, align 4
  %d = getelementptr i8, ptr %p, i64 8
  store double 2.5, ptr %d, align 8
  %e = getelementptr i8, ptr %p, i64 16
  store i8 200, ptr %e, align 1
  %f = getelementptr i8, ptr %p, i64 20
  store float 1.5, ptr %f, align 4
  %g = getelementptr i8, ptr %p, i64 24
  store i64 1099511627776, ptr %g, align 8
  ret void
}

; a + b + c + e + g, with a, b, c sign-extended and e zero-extended
define i64 @fx_mix_integers(ptr %p) {
  %a = load i8, ptr %p, align 1
  %bp = getelementptr i8, ptr %p, i64 2
  %b = load i16, ptr %bp, align 2
  %cp = getelementptr i8, ptr %p, i64 4
  %c = load i32, ptr %cp, align 4
  %ep = getelementptr i8, ptr %p, i64 16
  %e = load i8, ptr %ep, align 1
  %gp = getelementptr i8, ptr %p, i64 24
  %g = load i64, ptr %gp, align 8
  %a64 = sext i8 %a to i64
  %b64 = sext i16 %b to i64
  %c64 = sext i32 %c to i64
  %e64 = zext i8 %e to i64
  %s1 = add i64 %a64, %b64
  %s2 = add i64 %s1, %c64
  %s3 = add i64 %s2, %e64
  %s4 = add i64 %s3, %g
  ret i64 %s4
}

; d + f
define double @fx_mix_reals(ptr %p) {
  %dp = getelementptr i8, ptr %p, i64 8
  %d = load double, ptr %dp, align 8
  %fp = getelementptr i8, ptr %p, i64 20
  %f = load float, ptr %fp, align 4
  %f64 = fpext float %f to double
  %s = fadd double %d, %f64
  ret double %s
}

define void @fx_fill_outer(ptr %p) {
  store i8 7, ptr %p, align 1
  %m = getelementptr i8, ptr %p, i64 8
  call void @fx_fill_mix(ptr %m)
  %t = getelementptr i8, ptr %p, i64 40
  store i16 65000, ptr %t, align 2
  ret void
}

; x * 10 + y summed over count pairs
define i32 @fx_sum_pairs(ptr %p, i32 %count) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %body ]
  %acc = phi i32 [ 0, %entry ], [ %acc2, %body ]
  %done = icmp eq i32 %i, %count
  br i1 %done, label %exit, label %body
body:
  %i64 = sext i32 %i to i64
  %off = mul i64 %i64, 8
  %xp = getelementptr i8, ptr %p, i64 %off
  %x = load i32, ptr %xp, align 4
  %yoff = add i64 %off, 4
  %yp = getelementptr i8, ptr %p, i64 %yoff
  %y = load i32, ptr %yp, align 4
  %x10 = mul i32 %x, 10
  %term = add i32 %x10, %y
  %acc2 = add i32 %acc, %term
  %next = add i32 %i, 1
  br label %loop
exit:
  ret i32 %acc
}

; A struct mix the library holds, filled, for the caller to read in place.
define i64 @fx_kept_mix() {
  call void @fx_fill_mix(ptr @fx_kept)
  %a = ptrtoint ptr @fx_kept to i64
  ret i64 %a
}

; Whether the struct mix the library holds has the values written by the
; caller: a = 9, b = 1000, g = 5.
define i32 @fx_kept_written() {
  %a = load i8, ptr @fx_kept, align 1
  %bp = getelementptr i8, ptr @fx_kept, i64 2
  %b = load i16, ptr %bp, align 2
  %gp = getelementptr i8, ptr @fx_kept, i64 24
  %g = load i64, ptr %gp, align 8
  %ok1 = icmp eq i8 %a, 9
  %ok2 = icmp eq i16 %b, 1000
  %ok3 = icmp eq i64 %g, 5
  %ok12 = and i1 %ok1, %ok2
  %ok = and i1 %ok12, %ok3
  %r = zext i1 %ok to i32
  ret i32 %r
}

; Copies text to same, and sets flag to whether a is 42.
define void @fx_fill_refs(ptr %p) {
  %a = load i32, ptr %p, align 4
  %tp = getelementptr i8, ptr %p, i64 8
  %t = load ptr, ptr %tp, align 8
  %sp = getelementptr i8, ptr %p, i64 24
  store ptr %t, ptr %sp, align 8
  %is = icmp eq i32 %a, 42
  %f = zext i1 %is to i8
  %fp = getelementptr i8, ptr %p, i64 16
  store i8 %f, ptr %fp, align 1
  ret void
}
