from .nearest_neighbor cimport Interpolator as InterpolatorNearestNeighbor

cdef double _interpolate(float[:,:] image, double x, double y, int taps) nogil
cdef double _lanczos_kernel(double x, int taps) nogil

cdef class Interpolator(InterpolatorNearestNeighbor):
    cdef int taps
    cdef float _interpolate(self, float x, float y) nogil
