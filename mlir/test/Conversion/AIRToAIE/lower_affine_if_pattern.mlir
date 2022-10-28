//===- lower_affine_if_pattern.mlir ----------------------------*- MLIR -*-===//
//
// Copyright (C) 2022, Xilinx Inc.
// Copyright (C) 2022, Advanced Micro Devices, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
//===----------------------------------------------------------------------===//

// RUN: air-opt %s -air-to-aie='test-patterns=specialize-affine-if'| FileCheck %s

// CHECK: [[T_0_0:%.*]] = AIE.tile(0, 0)
// CHECK: [[T_1_0:%.*]] = AIE.tile(1, 0)
// CHECK: [[T_0_1:%.*]] = AIE.tile(0, 1)
// CHECK: [[T_1_1:%.*]] = AIE.tile(1, 1)
// CHECK: [[C_1_1:%.*]] = AIE.core([[T_1_1]])
// CHECK: [[V1:%.*]] = arith.constant 6 : i32
// CHECK: [[V0:%.*]] = arith.constant 10 : i32
// CHECK: arith.addi %{{.*}}, [[V1]] : i32
// CHECK: arith.addi %{{.*}}, [[V0]] : i32
// CHECK: AIE.end
// CHECK: [[C_0_1:%.*]] = AIE.core([[T_0_1]])
// CHECK: [[V3:%.*]] = arith.constant 6 : i32
// CHECK: [[V2:%.*]] = arith.constant 8 : i32
// CHECK: arith.addi %{{.*}}, [[V3]] : i32
// CHECK: arith.addi %{{.*}}, [[V2]] : i32
// CHECK: AIE.end
// CHECK: [[C_1_0:%.*]] = AIE.core([[T_1_0]])
// CHECK: [[V5:%.*]] = arith.constant 4 : i32
// CHECK: [[V4:%.*]] = arith.constant 10 : i32
// CHECK: arith.addi %{{.*}}, [[V5]] : i32
// CHECK: arith.addi %{{.*}}, [[V4]] : i32
// CHECK: AIE.end
// CHECK: [[C_0_0:%.*]] = AIE.core([[T_0_0]])
// CHECK: [[V7:%.*]] = arith.constant 4 : i32
// CHECK: [[V6:%.*]] = arith.constant 8 : i32
// CHECK: arith.addi %{{.*}}, [[V7]] : i32
// CHECK: arith.addi %{{.*}}, [[V6]] : i32
// CHECK: AIE.end
#map = affine_map<(d0, d1) -> (d0, d1)>
#set0 = affine_set<()[s0, s1] : (s0 >= 0, s1 == 0)>
#set1 = affine_set<()[s0, s1] : (s0 == 0, s1 >= 0)>
module @aie.partition_0 {
  %0 = AIE.tile(0, 0)
  %1 = AIE.tile(1, 0)
  %2 = AIE.tile(0, 1)
  %3 = AIE.tile(1, 1)
  memref.global "public" @__air_herd_arg_9 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_10 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_11 : memref<64x64xi32>
  %4 = AIE.core(%3) {
    cf.br ^bb1
  ^bb1:  // pred: ^bb0
    %c1 = arith.constant 1 : index
    %c1_0 = arith.constant 1 : index
    cf.br ^bb2
  ^bb2:  // pred: ^bb1
    %c10_i32 = arith.constant 10 : i32
    %c8_i32 = arith.constant 8 : i32
    %c6_i32 = arith.constant 6 : i32
    %c4_i32 = arith.constant 4 : i32
    %8 = memref.alloc() : memref<32x32xi32, 2>
    %9 = memref.alloc() : memref<32x32xi32, 2>
    affine.if #set0()[%c1, %c1_0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c4_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c6_i32 : i32
        linalg.yield %10 : i32
      }
    }
    affine.if #set1()[%c1, %c1_0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c8_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c10_i32 : i32
        linalg.yield %10 : i32
      }
    }
    AIE.end
  } {elf_file = "partition_0_core_1_1.elf"}
  memref.global "public" @__air_herd_arg_6 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_7 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_8 : memref<64x64xi32>
  %5 = AIE.core(%2) {
    cf.br ^bb1
  ^bb1:  // pred: ^bb0
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    cf.br ^bb2
  ^bb2:  // pred: ^bb1
    %c10_i32 = arith.constant 10 : i32
    %c8_i32 = arith.constant 8 : i32
    %c6_i32 = arith.constant 6 : i32
    %c4_i32 = arith.constant 4 : i32
    %8 = memref.alloc() : memref<32x32xi32, 2>
    %9 = memref.alloc() : memref<32x32xi32, 2>
    affine.if #set0()[%c0, %c1] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c4_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c6_i32 : i32
        linalg.yield %10 : i32
      }
    }
    affine.if #set1()[%c0, %c1] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c8_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c10_i32 : i32
        linalg.yield %10 : i32
      }
    }
    AIE.end
  } {elf_file = "partition_0_core_0_1.elf"}
  memref.global "public" @__air_herd_arg_3 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_4 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_5 : memref<64x64xi32>
  %6 = AIE.core(%1) {
    cf.br ^bb1
  ^bb1:  // pred: ^bb0
    %c1 = arith.constant 1 : index
    %c0 = arith.constant 0 : index
    cf.br ^bb2
  ^bb2:  // pred: ^bb1
    %c10_i32 = arith.constant 10 : i32
    %c8_i32 = arith.constant 8 : i32
    %c6_i32 = arith.constant 6 : i32
    %c4_i32 = arith.constant 4 : i32
    %8 = memref.alloc() : memref<32x32xi32, 2>
    %9 = memref.alloc() : memref<32x32xi32, 2>
    affine.if #set0()[%c1, %c0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c4_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c6_i32 : i32
        linalg.yield %10 : i32
      }
    }
    affine.if #set1()[%c1, %c0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c8_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c10_i32 : i32
        linalg.yield %10 : i32
      }
    }
    AIE.end
  } {elf_file = "partition_0_core_1_0.elf"}
  memref.global "public" @__air_herd_arg_0 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_1 : memref<64x64xi32>
  memref.global "public" @__air_herd_arg_2 : memref<64x64xi32>
  %7 = AIE.core(%0) {
    cf.br ^bb1
  ^bb1:  // pred: ^bb0
    %c0 = arith.constant 0 : index
    %c0_0 = arith.constant 0 : index
    cf.br ^bb2
  ^bb2:  // pred: ^bb1
    %c10_i32 = arith.constant 10 : i32
    %c8_i32 = arith.constant 8 : i32
    %c6_i32 = arith.constant 6 : i32
    %c4_i32 = arith.constant 4 : i32
    %8 = memref.alloc() : memref<32x32xi32, 2>
    %9 = memref.alloc() : memref<32x32xi32, 2>
    affine.if #set0()[%c0, %c0_0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c4_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c6_i32 : i32
        linalg.yield %10 : i32
      }
    }
    affine.if #set1()[%c0, %c0_0] {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c8_i32 : i32
        linalg.yield %10 : i32
      }
    } else {
      linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel", "parallel"]} ins(%9 : memref<32x32xi32, 2>) outs(%8 : memref<32x32xi32, 2>) {
      ^bb0(%arg0: i32, %arg1: i32):
        %10 = arith.addi %arg0, %c10_i32 : i32
        linalg.yield %10 : i32
      }
    }
    AIE.end
  } {elf_file = "partition_0_core_0_0.elf"}
}
