; ModuleID = '/Users/sazzadsowmik/Documents/Personal/dr_hao_zheng/HiVeGen/code/inputs/kernel_gemm.c'
source_filename = "/Users/sazzadsowmik/Documents/Personal/dr_hao_zheng/HiVeGen/code/inputs/kernel_gemm.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @gemm(i32 noundef %0, i32 noundef %1, i32 noundef %2, ptr noundef readonly captures(none) %3, ptr noundef readonly captures(none) %4, ptr noundef writeonly captures(none) %5) local_unnamed_addr #0 {
  %7 = icmp sgt i32 %0, 0
  br i1 %7, label %8, label %25

8:                                                ; preds = %6
  %9 = icmp sgt i32 %1, 0
  %10 = icmp sgt i32 %2, 0
  %11 = zext i32 %1 to i64
  %12 = zext i32 %1 to i64
  %13 = zext nneg i32 %0 to i64
  %14 = zext nneg i32 %1 to i64
  %15 = zext nneg i32 %2 to i64
  br label %16

16:                                               ; preds = %8, %30
  %17 = phi i64 [ 0, %8 ], [ %31, %30 ]
  br i1 %9, label %18, label %30

18:                                               ; preds = %16
  %19 = mul nuw nsw i64 %17, %12
  %20 = trunc i64 %17 to i32
  %21 = mul i32 %2, %20
  %22 = zext i32 %21 to i64
  %23 = getelementptr inbounds float, ptr %3, i64 %22
  %24 = getelementptr inbounds float, ptr %5, i64 %19
  br label %26

25:                                               ; preds = %30, %6
  ret void

26:                                               ; preds = %18, %33
  %27 = phi i64 [ 0, %18 ], [ %36, %33 ]
  br i1 %10, label %28, label %33

28:                                               ; preds = %26
  %29 = getelementptr inbounds float, ptr %4, i64 %27
  br label %38

30:                                               ; preds = %33, %16
  %31 = add nuw nsw i64 %17, 1
  %32 = icmp eq i64 %31, %13
  br i1 %32, label %25, label %16, !llvm.loop !6

33:                                               ; preds = %38, %26
  %34 = phi float [ 0.000000e+00, %26 ], [ %46, %38 ]
  %35 = getelementptr inbounds float, ptr %24, i64 %27
  store float %34, ptr %35, align 4, !tbaa !9
  %36 = add nuw nsw i64 %27, 1
  %37 = icmp eq i64 %36, %14
  br i1 %37, label %30, label %26, !llvm.loop !13

38:                                               ; preds = %28, %38
  %39 = phi i64 [ 0, %28 ], [ %47, %38 ]
  %40 = phi float [ 0.000000e+00, %28 ], [ %46, %38 ]
  %41 = getelementptr inbounds float, ptr %23, i64 %39
  %42 = load float, ptr %41, align 4, !tbaa !9
  %43 = mul nuw nsw i64 %39, %11
  %44 = getelementptr inbounds float, ptr %29, i64 %43
  %45 = load float, ptr %44, align 4, !tbaa !9
  %46 = tail call float @llvm.fmuladd.f32(float %42, float %45, float %40)
  %47 = add nuw nsw i64 %39, 1
  %48 = icmp eq i64 %47, %15
  br i1 %48, label %33, label %38, !llvm.loop !14
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare float @llvm.fmuladd.f32(float, float, float) #1

attributes #0 = { nofree norecurse nosync nounwind ssp memory(argmem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 15, i32 5]}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 8, !"PIC Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 1}
!4 = !{i32 7, !"frame-pointer", i32 1}
!5 = !{!"Homebrew clang version 21.1.3"}
!6 = distinct !{!6, !7, !8}
!7 = !{!"llvm.loop.mustprogress"}
!8 = !{!"llvm.loop.unroll.disable"}
!9 = !{!10, !10, i64 0}
!10 = !{!"float", !11, i64 0}
!11 = !{!"omnipotent char", !12, i64 0}
!12 = !{!"Simple C/C++ TBAA"}
!13 = distinct !{!13, !7, !8}
!14 = distinct !{!14, !7, !8}
