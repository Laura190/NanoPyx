# cython: infer_types=True, wraparound=False, nonecheck=False, boundscheck=False, cdivision=True, language_level=3, profile=False, autogen_pxd=False
import time
import scipy
import numpy as np
cimport numpy as np

from cython.parallel import prange
from libc.math cimport pow, sqrt
from scipy.interpolate import interp1d

from ...__liquid_engine__ import LiquidEngine
from .ccm cimport _calculate_ccm
from ..transform._le_interpolation_bicubic import ShiftAndMagnify
from .estimate_shift import GetMaxOptimizer
from .ccm_helper_functions cimport _check_even_square, _make_even_square


class DriftEstimator(LiquidEngine):
    """@public
    Drift estimator class for estimating drift in image stacks.

    This class provides methods for estimating drift in image stacks using cross-correlation.
    """

    def __init__(self, clear_benchmarks=False, testing=False, verbose=True):
        self._designation = "DriftEstimator"
        super().__init__(
            clear_benchmarks=clear_benchmarks, testing=testing, verbose=verbose)

    def run(self, image, time_averaging: int = 2, max_drift: int = 5, ref_option: int = 0, run_type=None):
        return self._run(np.asarray(image).astype(np.float32), time_averaging=time_averaging, max_drift=max_drift, ref_option=ref_option, run_type=run_type)

    def benchmark(self, image, time_averaging: int = 2, max_drift: int = 5, ref_option: int = 0):
        return super().benchmark(image, time_averaging=time_averaging, max_drift=max_drift, ref_option=ref_option)

    def _run_unthreaded(self, float[:, :, :] image,  int time_averaging=2, int max_drift=5, int ref_option=0):
        """
        @cpu
        @cython
        """
        if not _check_even_square(image):
            image = _make_even_square(image)

        # get image dimensions, should already be an even square
        cdef int n_slices = image.shape[0]
        cdef int n_rows = image.shape[1]
        cdef int n_cols = image.shape[2]

        # ensures time averaging has an acceptable value
        if time_averaging < 1:
            time_averaging = 1
        elif time_averaging > (n_slices//2):
            time_averaging = n_slices//2

        cdef int n_blocks = n_slices // time_averaging
        
        averaged = np.empty((n_blocks, n_rows, n_cols), dtype=np.float32)

        cdef int idx
        if time_averaging == 1:
            averaged = image
        else:
            for idx in range(n_blocks):
                averaged[idx, :, :] = np.mean(image[idx*time_averaging:(idx+1)*time_averaging, :, :], axis=0)

        cdef float[:, :, :] ccm
        cdef int row_start
        cdef int col_start
        if max_drift > 0 and max_drift * 2 + 1 < n_rows and max_drift * 2 + 1 < n_cols:
            row_start = int(n_rows / 2 - max_drift)
            col_start = int(n_cols / 2 - max_drift)
            ccm = _calculate_ccm(averaged, ref_option)[:, row_start : row_start + (max_drift * 2), col_start : col_start + (max_drift * 2)]
        else:
            ccm = _calculate_ccm(averaged, ref_option)

        cdef float[:, :] drift_table = np.zeros((n_blocks, 2), dtype=np.float32)
        
        cdef float[:, :] output = np.zeros((image.shape[0], 3), dtype=np.float32)

        cdef float bias_row = 0.0
        cdef float bias_col = 0.0
        cdef float shift_x, shift_y

        cdef int i
        for i in range(n_blocks):

            optimizer = GetMaxOptimizer(np.ascontiguousarray(ccm[i], dtype=np.float32))
            shift_y, shift_x = optimizer.get_max()

            drift_table[i, 0] = round((ccm.shape[1]/2) - shift_y - 0.5, 3)
            drift_table[i, 1] = round((ccm.shape[2]/2) - shift_x - 0.5, 3)

            if i == 0:
                bias_row = drift_table[i, 0]
                bias_col = drift_table[i, 1]
            drift_table[i, 0] = drift_table[i, 0] - bias_row
            drift_table[i, 1] = drift_table[i, 1] - bias_col

            if ref_option == 1 and i > 0:
                drift_table[i, 0] = drift_table[i, 0] + drift_table[i-1, 0]
                drift_table[i, 1] = drift_table[i, 1] + drift_table[i-1, 1]

        cdef float[:] drift_x, drift_y
        if time_averaging > 1:
            lin = np.linspace(1, image.shape[0], num=drift_table.shape[0], endpoint=True, dtype=int)
            x_interpolator = interp1d(
                lin, np.array(drift_table[:, 1]), kind="cubic"
            ) 
            y_interpolator = interp1d(
                lin, np.array(drift_table[:, 0]), kind="cubic"
            )

            drift_x = np.asarray(x_interpolator(range(1, image.shape[0]+1)), dtype=np.float32).reshape(n_slices)
            output[:, 1] = drift_x
            drift_y = np.asarray(y_interpolator(range(1, image.shape[0]+1)), dtype=np.float32).reshape(n_slices)
            output[:, 2] = drift_y

        else:
            output[:, 1] = drift_table[:, 1] # switch order of rows and cols
            output[:, 2] = drift_table[:, 0] # switch order of rows and cols

        cdef int s
        with nogil:
            for s in range(n_slices):
                output[s, 0] = sqrt((output[s, 1]*output[s, 1]) + (output[s, 2] * output[s, 2]))

        return np.asarray(output).astype(np.float32)
    def _run_threaded(self, float[:, :, :] image,  int time_averaging=2, int max_drift=5, int ref_option=0):
        """
        @cpu
        @threaded
        @cython
        """
        if not _check_even_square(image):
            image = _make_even_square(image)

        # get image dimensions, should already be an even square
        cdef int n_slices = image.shape[0]
        cdef int n_rows = image.shape[1]
        cdef int n_cols = image.shape[2]

        # ensures time averaging has an acceptable value
        if time_averaging < 1:
            time_averaging = 1
        elif time_averaging > (n_slices//2):
            time_averaging = n_slices//2

        cdef int n_blocks = n_slices // time_averaging
        
        averaged = np.empty((n_blocks, n_rows, n_cols), dtype=np.float32)

        cdef int idx
        if time_averaging == 1:
            averaged = image
        else:
            for idx in range(n_blocks):
                averaged[idx, :, :] = np.mean(image[idx*time_averaging:(idx+1)*time_averaging, :, :], axis=0)

        cdef float[:, :, :] ccm
        cdef int row_start
        cdef int col_start
        if max_drift > 0 and max_drift * 2 + 1 < n_rows and max_drift * 2 + 1 < n_cols:
            row_start = int(n_rows / 2 - max_drift)
            col_start = int(n_cols / 2 - max_drift)
            ccm = _calculate_ccm(averaged, ref_option)[:, row_start : row_start + (max_drift * 2), col_start : col_start + (max_drift * 2)]
        else:
            ccm = _calculate_ccm(averaged, ref_option)

        cdef float[:, :] drift_table = np.zeros((n_blocks, 2), dtype=np.float32)
        
        cdef float[:, :] output = np.zeros((image.shape[0], 3), dtype=np.float32)

        cdef float bias_row = 0.0
        cdef float bias_col = 0.0
        cdef float shift_x, shift_y

        cdef int i
        for i in range(n_blocks):

            optimizer = GetMaxOptimizer(np.ascontiguousarray(ccm[i], dtype=np.float32))
            shift_y, shift_x = optimizer.get_max()

            drift_table[i, 0] = round((ccm.shape[1]/2) - shift_y - 0.5, 3)
            drift_table[i, 1] = round((ccm.shape[2]/2) - shift_x - 0.5, 3)

            if i == 0:
                bias_row = drift_table[i, 0]
                bias_col = drift_table[i, 1]
            drift_table[i, 0] = drift_table[i, 0] - bias_row
            drift_table[i, 1] = drift_table[i, 1] - bias_col

            if ref_option == 1 and i > 0:
                drift_table[i, 0] = drift_table[i, 0] + drift_table[i-1, 0]
                drift_table[i, 1] = drift_table[i, 1] + drift_table[i-1, 1]

        cdef float[:] drift_x, drift_y
        if time_averaging > 1:
            lin = np.linspace(1, image.shape[0], num=drift_table.shape[0], endpoint=True, dtype=int)
            x_interpolator = interp1d(
                lin, np.array(drift_table[:, 1]), kind="cubic"
            ) 
            y_interpolator = interp1d(
                lin, np.array(drift_table[:, 0]), kind="cubic"
            )

            drift_x = np.asarray(x_interpolator(range(1, image.shape[0]+1)), dtype=np.float32).reshape(n_slices)
            output[:, 1] = drift_x
            drift_y = np.asarray(y_interpolator(range(1, image.shape[0]+1)), dtype=np.float32).reshape(n_slices)
            output[:, 2] = drift_y

        else:
            output[:, 1] = drift_table[:, 1] # switch order of rows and cols
            output[:, 2] = drift_table[:, 0] # switch order of rows and cols

        cdef int s
        with nogil:
            for s in prange(n_slices):
                output[s, 0] = sqrt((output[s, 1]*output[s, 1]) + (output[s, 2] * output[s, 2]))

        return np.asarray(output).astype(np.float32)
