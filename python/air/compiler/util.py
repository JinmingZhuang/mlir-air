
import air.mlir.ir
import air.mlir.passmanager
import air.mlir.all_passes_registration
import air.mlir._mlir_libs._airMlir

import tempfile
import os

__all__ = [
    "CostModel",
    "LINALG_TENSOR_TO_MEMREF_PIPELINE"
]

LINALG_TENSOR_TO_MEMREF_PIPELINE = ",".join([
    # Bufferize.
    "tensor-constant-bufferize",
    "builtin.func(scf-bufferize)",
    "builtin.func(linalg-bufferize)",
    "builtin.func(std-bufferize)",
    "builtin.func(tensor-bufferize)",
    "func-bufferize",
    "builtin.func(finalizing-bufferize)",
    "canonicalize",
    "cse"
])

class CostModel:
    def __init__(self):
        pass

    def _op_stats(self, air_module):
        with tempfile.NamedTemporaryFile(delete=False) as tmpfile:
            name = tmpfile.name
            with air_module.context:
                pipeline = f"air-linalg-op-stats{{outputfile={name}}}"
                pm = air.mlir.passmanager.PassManager.parse(pipeline)
                pm.run(air_module)
            stats = open(name).read()
            os.unlink(name)
        return stats

    def op_stats(self, module):
        """Return operation count information as JSON"""
        if not isinstance(module, air.mlir.ir.Module):
            air_module = air.mlir.ir.Module.parse(str(module),air.mlir.ir.Context())
        else:
            air_module = module
        return self._op_stats(air_module)
