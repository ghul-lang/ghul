; The foreign side of the extern-own-deallocator test: text allocated with
; malloc, and a deallocator of the library's own that counts its calls before
; freeing.
;
; Built by build/llvm-test-objects.sh, which the llvm test runs need first.

@fx_released_count = global i32 0
@fx_text = private constant [5 x i8] c"made\00"

declare ptr @strdup(ptr)
declare void @free(ptr)

define ptr @fx_make() {
  %p = call ptr @strdup(ptr @fx_text)
  ret ptr %p
}

define void @fx_release(ptr %p) {
  %n = load i32, ptr @fx_released_count
  %m = add i32 %n, 1
  store i32 %m, ptr @fx_released_count
  call void @free(ptr %p)
  ret void
}

define i32 @fx_released() {
  %n = load i32, ptr @fx_released_count
  ret i32 %n
}
