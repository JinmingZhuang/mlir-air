//===- Passes.td -------------------------------------------*- tablegen -*-===//
//
// Copyright (C) 2022, Xilinx Inc. All rights reserved.
// Copyright (C) 2022, Advanced Micro Devices, Inc. All rights reserved.
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#ifndef AIR_CONVERSION_PASSES
#define AIR_CONVERSION_PASSES

include "mlir/Pass/PassBase.td"

def ParallelToHerd : Pass<"air-par-to-herd", "ModuleOp"> {
  let summary = "Convert parallel loops to air.herd";
  let constructor = "xilinx::air::createParallelToHerdPass()";
  let description =  [{
    This pass converts parallel loop operations to air `herd` operations. The
    parallel loops can be `scf.parallel` or `affine.parallel` operations with 1
    or 2 dimensional iteration spaces. The iteration space of the parallel loop
    will be normalized and will become the spacial iteration space of the new
    `herd`. If nested parallel loops are present then the `depth` option can
    to used to specify which loop depth to convert.
  }];
  let options = [
    Option<"clAssignDepth", "depth", "int",
          /*default=*/"-1",
          "Given a nest of parallel for loops, which depth to map to air.herd">,
    Option<"clFirstDim", "first-dim", "int",
          /*default=*/"0",
          "Which herd dimension to map to first. Can be zero or one. If set to "
          "zero, the 0th dimension of the scf.parallel will be mapped to the x "
          "dimension of the herd. If set to one, the 0th dimension of the "
          "scf.parallel will be mapped to the y dimension of the herd.">
  ];
}

def ParallelToLaunch : Pass<"air-par-to-launch", "ModuleOp"> {
  let summary = "Convert parallel loops to air.launch";
  let constructor = "xilinx::air::createParallelToLaunchPass()";
  let description =  [{
    This pass converts parallel loop operations to air `launch` operations. The
    parallel loops can be `scf.parallel` or `affine.parallel` operations. The
    iteration space of the parallel loops will be normalized and will become the
    iteration space of the new `launch`. If nested parallel loops are present
    then the `depth` option can to used to specify which loop depth to convert.
    An air `segment` operation can optionally be inserted at the top level of
    the generated `launch` operations with the `has-air-segment` option.
  }];
  let options = [
    Option<"clAssignDepth", "depth", "int",
          /*default=*/"-1",
          "Given a nest of parallel for loops, which depth to map to air.launch">,
    Option<"clHasSegment", "has-air-segment", "bool", /*default=*/"false",
           "Whether to create an air.segment op in generated air.launch "
           "regions">,
  ];
}

def CopyToDma : Pass<"air-copy-to-dma", "ModuleOp"> {
  let summary = "Convert memcpy to air.dma_memcpy_nd";
  let constructor = "xilinx::air::createCopyToDmaPass()";
  let description =  [{
    Converts memory operations to optimize data transfer through Direct Memory 
    Access (DMA) operations.
  }];
}

def DmaToChannel : Pass<"air-dma-to-channel", "ModuleOp"> {
  let summary = "Convert air.dma_memcpy_nd to air.channel";
  let constructor = "xilinx::air::createDmaToChannelPass()";
  let description =  [{
    Transforms direct memory access (DMA) operations into channel-based 
    communications, consisting of a series of channel put and get operations 
    via shared channel constructs.

    Example:

    Input:
    ```mlir
    %0 = air.launch async [%async_token_0, %async_token_3, %async_token_6] (%arg0, %arg1) in (%arg2=%c4, %arg3=%c4) args(%arg4=%results_5, %arg5=%results, %arg6=%results_2) : memref<512x512xi32>, memref<512x1024xi32>, memref<1024x512xi32> attributes {id = 3 : i32} {
      %1 = air.segment @segment_0 async  args(%arg7=%arg0, %arg8=%arg1, %arg9=%arg4, %arg10=%arg5, %arg11=%arg6) : index, index, memref<512x512xi32>, memref<512x1024xi32>, memref<1024x512xi32> attributes {id = 2 : i32} {
        ...
        %3 = scf.for %arg12 = %c0_8 to %c1024 step %c256 iter_args(%arg13 = %2) -> (!air.async.token) {
          %8 = air.dma_memcpy_nd async [%arg13, %arg13] (%results_14[%c0_8, %arg12] [%c128, %c256] [%c1024, %c1], %arg10[%results_10, %arg12] [%c128, %c256] [%c1024, %c1]) {id = 1 : i32} : (memref<128x1024xi32, 1 : i32>, memref<512x1024xi32>)
          ...
        }
        %6 = air.herd @herd_0 async [%async_token_13, %async_token_15, %async_token_17]  tile (%arg12, %arg13) in (%arg14=%c4_7, %arg15=%c4_7) args(%arg16=%results_14, %arg17=%results_16, %arg18=%results_18) : memref<128x1024xi32, 1 : i32>, memref<1024x128xi32, 1 : i32>, memref<128x128xi32, 1 : i32> attributes {id = 1 : i32} {
          ...
          %9 = scf.for %arg19 = %c0_23 to %c128_26 step %c4_24 iter_args(%arg20 = %8) -> (!air.async.token) {
            ...
            %16 = air.dma_memcpy_nd async [%async_token_37, %async_token_35, %arg20] (%results_38[%c0_23] [%c1024_22] [%c1_25], %arg16[%c0_44, %c0_43, %results_36] [%c4_24, %c32, %c8] [%c8, %c1024_22, %c1_25]) {broadcast_set = affine_set<()[s0, s1] : (s0 == 0, s1 >= 0, -s1 + 3 >= 0)>, id = 3 : i32} : (memref<4x8x4x8xi32, 2 : i32>, memref<128x1024xi32, 1 : i32>)
            ...
          }
          ...
          air.herd_terminator
        }
        ...
        air.segment_terminator
      }
      air.launch_terminator
    }
    ```

    Output:
    ```mlir
    ...
    air.channel @channel_8 [1, 1]
    ...
    air.channel @channel_0 [1, 1] {broadcast_shape = [1, 4]}
    ...
    %0 = air.launch async [%async_token_0, %async_token_3, %async_token_6] (%arg0, %arg1) in (%arg2=%c4, %arg3=%c4) args(%arg4=%results_5, %arg5=%results, %arg6=%results_2) : memref<512x512xi32>, memref<512x1024xi32>, memref<1024x512xi32> attributes {id = 3 : i32} {
      ...
      %2 = scf.for %arg7 = %c0_7 to %c1024 step %c256 iter_args(%arg8 = %1) -> (!air.async.token) {
        ...
        %17 = air.channel.put async [%async_token_8, %arg8]  @channel_8[] (%arg5[%results_9, %arg7] [%c128, %c256] [%c1024, %c1]) : (memref<512x1024xi32>)
        ...
      }
      ...
      %16 = air.segment @segment_0 async  args(%arg7=%arg0, %arg8=%arg1, %arg9=%arg4, %arg10=%arg5, %arg11=%arg6) : index, index, memref<512x512xi32>, memref<512x1024xi32>, memref<1024x512xi32> attributes {id = 2 : i32} {
        ...
        %18 = scf.for %arg12 = %c0_32 to %c1024_33 step %c256_34 iter_args(%arg13 = %17) -> (!air.async.token) {
          %49 = air.channel.get async [%arg13, %arg13]  @channel_8[] (%results_40[%c0_32, %arg12] [%c128_30, %c256_34] [%c1024_33, %c1_29]) : (memref<128x1024xi32, 1 : i32>)
          ...
        }
        ...
        %23 = scf.for %arg12 = %c0_47 to %c128_50 step %c4_48 iter_args(%arg13 = %22) -> (!air.async.token) {
          ...
          %49 = air.channel.put async [%async_token_160, %async_token_39, %arg13]  @channel_0[] (%results_40[%c0_163, %c0_162, %results_161] [%c4_48, %c32, %c8] [%c8, %c1024_46, %c1_49]) : (memref<128x1024xi32, 1 : i32>)
          ...
        }
        ...
        %47 = air.herd @herd_0 async [%async_token_39, %async_token_41, %async_token_43]  tile (%arg12, %arg13) in (%arg14=%c4_31, %arg15=%c4_31) args(%arg16=%results_40, %arg17=%results_42, %arg18=%results_44) : memref<128x1024xi32, 1 : i32>, memref<1024x128xi32, 1 : i32>, memref<128x128xi32, 1 : i32> attributes {id = 1 : i32} {
          ...
          %50 = scf.for %arg19 = %c0_155 to %c128_159 step %c4_156 iter_args(%arg20 = %49) -> (!air.async.token) {
            ...
            %57 = air.channel.get async [%async_token_170, %async_token_168, %arg20]  @channel_0[%arg12, %arg13] (%results_171[%c0_155] [%c1024_154] [%c1_158]) : (memref<4x8x4x8xi32, 2 : i32>)
            ...
          }
          ...
          air.herd_terminator
        }
        air.segment_terminator
      }
      air.launch_terminator
    }
    ```
  }];
}

def AIRToAsync : Pass<"air-to-async", "ModuleOp"> {
  let summary = "AIR dialect lowering";
  let constructor = "xilinx::air::createAIRToAsyncPass()";
  let description = [{
  }];
}

def AIRLowering : Pass<"air-to-std", "ModuleOp"> {
  let summary = "AIR dialect lowering";
  let constructor = "xilinx::air::createAIRLoweringPass()";
  let description = [{
    This pass converts AIR dialect herd launch operations into loop nests
    representing the host-side control program for the herd. It also converts
    AIR dialect memcpy operations into AIRRt memcpy operations.

    ### Example - A 1x1 herd copying a 1024xi32 vector from L3 memory into an L1 buffer

    ### Input

    ```mlir
      module {
        func.func @f(%arg0: memref<1024xi32>, %arg1: memref<1024xi32>) {
          %c1 = arith.constant 1 : index
          air.herd @herd_0  tile (%arg2, %arg3) in (%arg4=%c1, %arg5=%c1) args(%arg6=%arg0, %arg7=%arg1) : memref<1024xi32>, memref<1024xi32> attributes {x_loc = 1 : i32, y_loc = 1 : i32} {
            %alloc = memref.alloc() : memref<1024xi32, 2>
            air.dma_memcpy_nd (%alloc[] [] [], %arg6[] [] []) {id = 1 : i32} : (memref<1024xi32, 2>, memref<1024xi32>)
            memref.dealloc %alloc : memref<1024xi32, 2>
            air.herd_terminator
          }
          return
        }
      }
    ```

    #### Output

    ```mlir
      func.func @f(%arg0: memref<1024xi32>, %arg1: memref<1024xi32>) {
        %c1 = arith.constant 1 : index
        %h = airrt.herd_load "herd_0" : i64
        affine.for %arg2 = 0 to 1 {
          affine.for %arg3 = 0 to 1 {
            %alloc = memref.alloc() : memref<1024xi32, 2>
            %c1_i32 = arith.constant 1 : i32
            %0 = arith.index_cast %arg3 : index to i64
            %1 = arith.index_cast %arg2 : index to i64
            %c0_i64 = arith.constant 0 : i64
            %c1_i64 = arith.constant 1 : i64
            airrt.dma_memcpy_nd(%c1_i32, %0, %1, %arg0[%c0_i64, %c0_i64, %c0_i64, %c0_i64], [%c1_i64, %c1_i64, %c1_i64, %c1_i64], [%c0_i64, %c0_i64, %c0_i64]) : (i32, i64, i64, memref<1024xi32>, [i64, i64, i64, i64], [i64, i64, i64, i64], [i64, i64, i64])
            memref.dealloc %alloc : memref<1024xi32, 2>
          } {air.herd = "inner"}
        } {air.herd = "outer"}
        return
      }
    ```
  }];
}

//===----------------------------------------------------------------------===//
// Custom version of upstream LinalgToFunc
//===----------------------------------------------------------------------===//

def AIRLinalgToFunc : Pass<"air-linalg-to-func", "ModuleOp"> {
  let summary = "Convert the operations from the linalg dialect into the "
                "function calls";
  let constructor = "xilinx::air::createAIRLinalgToFuncPass()";
  let dependentDialects = ["func::FuncDialect", "memref::MemRefDialect"];
  let options = [
    Option<"clLinkWith", "link-with", "std::string",
          /*default=*/"\"\"",
           "Path to the object file containing the functions that will be "
           "called in place of the linalg operations.">
  ];
}

def AIRToAIE : Pass<"air-to-aie", "ModuleOp"> {
  let summary = "Lower air.launch_herd to AIE dialect";
  let constructor = "xilinx::air::createAIRToAIEPass()";
  let options = [
    Option<"clRowOffset", "row-offset", "unsigned", /*default=*/"1",
           "The default start row for any herds without 'y_loc' attribute.">,
    Option<"clColOffset", "col-offset", "unsigned", /*default=*/"1",
           "The default start column for any herds without 'x_loc' attribute.">,
    Option<"clEmitWhileLoop", "emit-while-loop", "bool",
           /*default=*/"false",
           "Emit a while(1) around the herd code in generated AIR.core ops.">,
    Option<"clEmitHerdLock", "emit-herd-lock", "bool",
           /*default=*/"false",
           "Acquire and release a lock at the start and end of herd execution. "
           "The default is to acquire lock 0 with value zero and release it "
           "with value 0. "
           "There is currently no way to override the default behavior.">,
    Option<"clTestPatterns", "test-patterns", "std::string",
          /*default=*/"\"\"",
           "Test the given patterns.">,
    Option<"clDevice", "device", "std::string",
          /*default=*/"\"xcvc1902\"",
           "AIE device to target.">,
    Option<"clUseObjFifo", "use-objectfifo", "bool",
           /*default=*/"false",
           "Choose whether to lower data movement ops to aie.objectFifo, or "
           "directly to aie.locks.">,
    Option<"clGenerateShimDMA", "generate-shim-dma", "bool",
           /*default=*/"false",
           "Choose whether to schedule shim data movement via generating AIE "
           " shim DMA program, or AIR runtime.">,
  ];
  let description = [{
    This pass converts AIR dialect `herd` and `segment` operations into AIE
    dialect modules and AIRRt dialect metadata.

    One AIE dialect module is generated for each `segment` in the input
    module. Any `herd` without a parent `segment` will will also generate
    an AIE dialect module as if the `herd` has an implicit segment.

    For each `herd` in a segment a 2d array of `aie.tile` operations is
    generated. The physical placement of the tiles is specified using the
    `herd` operation placement attributes or with `row-offset` and `col-offset`
    options to the pass. `aie.core` operations are generated for each `aie.tile`
    and the `herd` body is cloned into each core. 

    After generating `aie.core` operations, several other conversions are run:

    * `memref.alloc` operations returning L1 memory are converted into static
    allocations using `aie.buffer` operations.

    * `dma_memcpy_nd` operations in each core are lowered to `aie.mem`
    operations to perform the transfers and `aie.locks` are allocated to
    synchronize between the cores and the tile DMAs. As part of this 
    conversion tile DMA schedules and channel allocations are generated
    for the `aie.mem` bodies. L3 or L2 DMA channels are allocated for
    sending or receiving data to the tile DMAs. `aie.flow` operations
    are allocated to connect the DMAs.

    * `affine.if` operations with tile id operands are specialized, as these
    are now constants. This allows an upstream user or transformation to
    specialize parts of each `aie.core` according to its location in the herd.

    * `air.execute` and `air.wait_all` operations are optimized away or
    transformed into sequential code.
 
    The pass will insert AIRRt metadata into the original module to describe the
    segments, herds and DMA allocations that were generated in the AIE dialect
    output modules. Runtime code for configuration and control of segments is
    generated from the AIRRt metadata by the `air-to-std` pass.

    ### Example - A 1x1 herd copying a 1024xi32 vector from L3 memory into an L1 buffer

    ### Input

    ```mlir
      func.func @f(%arg0: memref<1024xi32>, %arg1: memref<1024xi32>) {
        %c1 = arith.constant 1 : index
        air.herd @herd_0  tile (%arg2, %arg3) in (%arg4=%c1, %arg5=%c1) args(%arg6=%arg0, %arg7=%arg1) : memref<1024xi32>, memref<1024xi32> {
          %alloc = memref.alloc() : memref<1024xi32, 2>
          air.dma_memcpy_nd (%alloc[] [] [], %arg6[] [] []) {id = 1 : i32} : (memref<1024xi32, 2>, memref<1024xi32>)
          memref.dealloc %alloc : memref<1024xi32, 2>
          air.herd_terminator
        }
        return
      }
    ```

    #### Output

    The AIE resource allocation,
    ```mlir
    module @aie.segment_0 {
      %0 = aie.tile(1, 1)
      %1 = aie.tile(2, 0)
      %2 = aie.lock(%0, 0)
      %3 = aie.buffer(%0) {sym_name = "buf0"} : memref<1024xi32, 2>
      aie.flow(%1, DMA : 0, %0, DMA : 0)
    ```
    the AIE DMA program,
    ```mlir
    %4 = aie.mem(%0) {
      %6 = aie.dma_start(S2MM, 0, ^bb1, ^bb2)
    ^bb1:  // 2 preds: ^bb0, ^bb1
      aie.use_lock(%2, Acquire, 0)
      aie.dma_bd(%3 : memref<1024xi32, 2>, 0, 1)
      aie.use_lock(%2, Release, 1)
      cf.br ^bb1
    ^bb2:  // pred: ^bb0
      aie.end
    }
    ```
    the AIE Core program,
    ```mlir
    %5 = aie.core(%0) {
      cf.br ^bb1
    ^bb1:  // pred: ^bb0
      cf.br ^bb2
    ^bb2:  // pred: ^bb1
      aie.use_lock(%2, Acquire, 1)
      aie.use_lock(%2, Release, 0)
      aie.end
    }
    ```
    and the AIRRt metadata,
    ```mlir
    airrt.module_metadata{
      airrt.segment_metadata attributes {sym_name = "segment_0"}{
        airrt.herd_metadata {dma_allocations = [{channel = 2 : i64, col = 0 : i64, id = 1 : i64, location = 2 : i64, row = 0 : i64} ], sym_name = "herd_0"}
      }
    }
    ```
  }];
}

def AIRRtToLLVM : Pass<"airrt-to-llvm", "ModuleOp"> {
  let summary = "Lower AIRRt dialect to LLVM dialect";
  let constructor = "xilinx::airrt::createAIRRtToLLVMPass()";
  let description =  [{
    This pass lowers AIRRt dialect to function calls and data structures
    matching those found in air_host.h.

    AIRRt static metadata is transformed to LLVM dialect data structures.
    The data is generated as a number of globals with external linkage.
    The data layout is closely tied the AIR runtime and the definitions in
    air_host.h.  Any changes to this pass must be reflected there.
  }];
  let options = [];
}

def AIRRtToIpu : Pass<"airrt-to-ipu", "ModuleOp"> {
  let summary = "Lower AIRRt dialect to AIEX.ipu dialect";
  let constructor = "xilinx::airrt::createAIRRtToIpuPass()";
  let description =  [{
    Converts the runtime program, described in AIRRt dialect, into 
    instruction sequence specific to the SHIM DMA controllers on Ryzen AI 
    platform.

    Example:

    Input:
    ```mlir
    module {
      aie.device(ipu) {
        ...
        aie.shim_dma_allocation @airMemcpyId78(S2MM, 0, 0)
        memref.global "public" @airMemcpyId78 : memref<32x128xi32, 1>
        ...
        aie.shim_dma_allocation @airMemcpyId19(MM2S, 0, 0)
        memref.global "public" @airMemcpyId19 : memref<32x256xi32, 1>
        ...
        aie.shim_dma_allocation @airMemcpyId15(MM2S, 0, 2)
        memref.global "public" @airMemcpyId15 : memref<256x32xi32, 1>
        ...
      } {sym_name = "segment_0"}
      ...
      func.func @matmul_512x512_1024xi32__dispatch_0_matmul_512x512x1024_i32() {
        ...
        affine.for %arg0 = affine_map<(d0) -> (d0)>(%c0) to affine_map<(d0) -> (d0 + 4)>(%c0) {
          affine.for %arg1 = affine_map<(d0) -> (d0)>(%c0_0) to affine_map<(d0) -> (d0 + 4)>(%c0_0) {
            ...
            %25 = airrt.dma_memcpy_nd(%c17_i32, %15, %16, %0[%c0_i64, %17, %18, %19], [%c1_i64, %22, %23, %24], [%c0_i64, %20, %21]) {metadata = @airMemcpyId19} : (i32, i64, i64, memref<512x1024xi32>, [i64, i64, i64, i64], [i64, i64, i64, i64], [i64, i64, i64]) : !airrt.event
            ...
            %74 = airrt.dma_memcpy_nd(%c13_i32, %67, %68, %3[%c0_i64_15, %c0_i64_15, %69, %70], [%c1_i64_16, %c1_i64_16, %72, %73], [%c0_i64_15, %c0_i64_15, %71]) {metadata = @airMemcpyId15} : (i32, i64, i64, memref<1024x512xi32>, [i64, i64, i64, i64], [i64, i64, i64, i64], [i64, i64, i64]) : !airrt.event
            ...
            %111 = airrt.dma_memcpy_nd(%c78_i32, %104, %105, %6[%c0_i64_26, %c0_i64_26, %106, %107], [%c1_i64_27, %c1_i64_27, %109, %110], [%c0_i64_26, %c0_i64_26, %108]) {metadata = @airMemcpyId78} : (i32, i64, i64, memref<512x512xi32>, [i64, i64, i64, i64], [i64, i64, i64, i64], [i64, i64, i64]) : !airrt.event
            ...
          }
        }
        return
      }
    }
    ```

    Output:
    ```mlir
    module {
      aie.device(ipu) {
        ...
        aie.shim_dma_allocation @airMemcpyId78(S2MM, 0, 0)
        memref.global "public" @airMemcpyId78 : memref<32x128xi32, 1>
        ...
        aie.shim_dma_allocation @airMemcpyId19(MM2S, 0, 0)
        memref.global "public" @airMemcpyId19 : memref<32x256xi32, 1>
        ...
        aie.shim_dma_allocation @airMemcpyId15(MM2S, 0, 2)
        memref.global "public" @airMemcpyId15 : memref<256x32xi32, 1>
        ...
        func.func @matmul_512x512_1024xi32__dispatch_0_matmul_512x512x1024_i32() {
          ...
          aiex.ipu.dma_memcpy_nd(0, 0, %arg0[0, 0, 0, 0][4, 4, 32, 256][0, 256, 1024]) {id = 0 : i64, metadata = @airMemcpyId19} : memref<512x1024xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg0[0, 0, 128, 0][4, 4, 32, 256][0, 256, 1024]) {id = 1 : i64, metadata = @airMemcpyId19} : memref<512x1024xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg0[0, 0, 256, 0][4, 4, 32, 256][0, 256, 1024]) {id = 2 : i64, metadata = @airMemcpyId19} : memref<512x1024xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg0[0, 0, 384, 0][4, 4, 32, 256][0, 256, 1024]) {id = 3 : i64, metadata = @airMemcpyId19} : memref<512x1024xi32>
          ...
          aiex.ipu.dma_memcpy_nd(0, 0, %arg1[0, 0, 0, 0][4, 2, 512, 32][128, 262144, 512]) {id = 0 : i64, metadata = @airMemcpyId15} : memref<1024x512xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg1[0, 0, 0, 0][4, 2, 512, 32][128, 262144, 512]) {id = 1 : i64, metadata = @airMemcpyId15} : memref<1024x512xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg1[0, 0, 0, 0][4, 2, 512, 32][128, 262144, 512]) {id = 2 : i64, metadata = @airMemcpyId15} : memref<1024x512xi32>
          aiex.ipu.dma_memcpy_nd(0, 0, %arg1[0, 0, 0, 0][4, 2, 512, 32][128, 262144, 512]) {id = 3 : i64, metadata = @airMemcpyId15} : memref<1024x512xi32>
          ...
          aiex.ipu.dma_memcpy_nd(0, 0, %arg2[0, 0, 0, 0][4, 4, 32, 128][65536, 128, 512]) {id = 8 : i64, metadata = @airMemcpyId78} : memref<512x512xi32>
          ...
          return
        }
      } {sym_name = "segment_0"}
    }
    ```

  }];
  let options = [];
  let dependentDialects = ["xilinx::AIEX::AIEXDialect"];
}

def AIRSplitDevices : Pass<"air-split-devices", "ModuleOp"> {
  let summary = "Split the input into one output per aie.device op";
  let constructor = "xilinx::air::createAIRSplitDevicesPass()";
  let options = [
    Option<"clOutputPrefix", "output-prefix", "std::string",
          /*default=*/"\"-\"",
           "File name prefix for split AIE modules. "
           "Set to \'-\' for stdout (default).">,
  ];
}

def AIRPipelineToAffine : Pass<"air-pipeline-to-affine", "ModuleOp"> {
  let summary = "Lower air.pipeline stages to affine.if";
  let constructor = "xilinx::air::createAIRPipelineToAffinePass()";
  let description =  [{
    Lower air.pipeline stages to affine.if
  }];
  let options = [
    Option<"clLoweringType", "lowering-type", "std::string", 
          /*default=*/"\"buffers\"",
          "Type of lowering to use for core-to-core communication. Can be 'buffer' or 'getput'">
  ];
}

def InsertEmptyLaunchOverHerd : Pass<"air-insert-launch-and-segment-around-herd", "ModuleOp"> {
  let summary = "Insert segment and launch ops around herd op";
  let constructor = "xilinx::air::createInsertEmptyLaunchOverHerdPass()";
  let description =  [{
    This pass inserts launch and segment operations around herd op, if a herd op 
    does not have a parent launch or segment operation.
  }];
}

#endif
