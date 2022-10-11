# ./examples/vck190/multi_mmult_i32_2x2/mmult.py -*- Python -*-

# Copyright (C) 2022, Xilinx Inc.
# Copyright (C) 2022, Advanced Micro Devices, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

import torch
import torch_mlir

shape = [128,128]
dtype = torch.int32
class model(torch.nn.Module):
    def __init__(self):
        super().__init__()

    def forward(self, t0, t1, t2):
        t3 = torch.mm(t0, t1)
        t4 = torch.mm(t3, t2)
        return t4

program = model()

module = torch_mlir.compile(
    program,
    (torch.ones(shape, dtype=dtype), torch.ones(shape, dtype=dtype), torch.ones(shape, dtype=dtype)),
    output_type=torch_mlir.OutputType.LINALG_ON_TENSORS
)

print(module)