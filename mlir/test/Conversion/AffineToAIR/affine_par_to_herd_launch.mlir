// RUN: air-opt -affine-to-air %s | FileCheck %s

// CHECK-LABEL: func @foo
// CHECK: %[[C0:.*]] = constant 1 : index
// CHECK air.launch_herd tile ({{.*}}, {{.*}}) in ({{.*}}=[[C0]], {{.*}}=[[C0]])
module  {
  func @foo()  {
    affine.parallel (%x,%y) = (0,0) to (1,1) {
      %2 = addi %x, %y : index
      affine.yield
    }
    return
  }
}