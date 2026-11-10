; The foreign side of the extern-widths test. A small argument is declared
; extended, so these callees rely on the caller having extended it; a small
; result is returned as the callee leaves it, with the upper bits of the
; register whatever the computation left there.
;
; Built by build/llvm-test-objects.sh, which the llvm test runs need first.

define i32 @fx_widen_i8(i8 signext %x) {
  %r = sext i8 %x to i32
  ret i32 %r
}

define i32 @fx_widen_u8(i8 zeroext %x) {
  %r = zext i8 %x to i32
  ret i32 %r
}

define i32 @fx_widen_i16(i16 signext %x) {
  %r = sext i16 %x to i32
  ret i32 %r
}

define i32 @fx_widen_u16(i16 zeroext %x) {
  %r = zext i16 %x to i32
  ret i32 %r
}

define i32 @fx_widen_bool(i1 zeroext %x) {
  %r = zext i1 %x to i32
  ret i32 %r
}

define i8 @fx_ret_i8(i32 %x) {
  %r = trunc i32 %x to i8
  ret i8 %r
}

define i8 @fx_ret_u8(i32 %x) {
  %r = trunc i32 %x to i8
  ret i8 %r
}

define i16 @fx_ret_i16(i32 %x) {
  %r = trunc i32 %x to i16
  ret i16 %r
}

define i16 @fx_ret_u16(i32 %x) {
  %r = trunc i32 %x to i16
  ret i16 %r
}

define i1 @fx_ret_bool(i32 %x) {
  %r = trunc i32 %x to i1
  ret i1 %r
}

define i32 @fx_sum_u32(i32 %a, i32 %b) {
  %r = add i32 %a, %b
  ret i32 %r
}

define i64 @fx_sum_i64(i64 %a, i64 %b) {
  %r = add i64 %a, %b
  ret i64 %r
}

define i64 @fx_sum_u64(i64 %a, i64 %b) {
  %r = add i64 %a, %b
  ret i64 %r
}

define float @fx_sum_f32(float %a, float %b) {
  %r = fadd float %a, %b
  ret float %r
}

define double @fx_sum_f64(double %a, double %b) {
  %r = fadd double %a, %b
  ret double %r
}

; More arguments than registers, mixed kinds, to check the stack layout.
define i64 @fx_many(i8 signext %a, i16 zeroext %b, i32 %c, i64 %d, double %e, i32 %f, i32 %g, i32 %h, i32 %i, i64 %j) {
  %a64 = sext i8 %a to i64
  %b64 = zext i16 %b to i64
  %c64 = sext i32 %c to i64
  %e64 = fptosi double %e to i64
  %f64 = sext i32 %f to i64
  %g64 = sext i32 %g to i64
  %h64 = sext i32 %h to i64
  %i64 = sext i32 %i to i64
  %s1 = add i64 %a64, %b64
  %s2 = add i64 %s1, %c64
  %s3 = add i64 %s2, %d
  %s4 = add i64 %s3, %e64
  %s5 = add i64 %s4, %f64
  %s6 = add i64 %s5, %g64
  %s7 = add i64 %s6, %h64
  %s8 = add i64 %s7, %i64
  %s9 = add i64 %s8, %j
  ret i64 %s9
}
