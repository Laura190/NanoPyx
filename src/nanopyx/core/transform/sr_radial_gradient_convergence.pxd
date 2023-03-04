cdef extern from "_c_sr_radial_gradient_convergence.h":
    double _c_calculate_dw(double distance, double tSS) nogil
    double _c_calculate_dk(double Gx, double Gy, double dx, double dy, double distance, double tSS) nogil

# pyx2pxd: starting point
# autogenerated by pyx2pxd - https://github.com/HenriquesLab/pyx2pxd

cdef class RadialGradientConvergence:
    cdef int magnification
    cdef float fwhm
    cdef float sensitivity
    cdef float tSS # two sigma squared
    cdef float tSO # two sigma plus one
    cdef bint doIntensityWeighting
    cdef void _single_frame_RGC_map(self, float[:,:] imRaw, float[:,:] imRad, float[:,:] imInt, float[:,:] imGx, float[:,:] imGy)
    cdef void _calculate_gradient(self, float[:,:] image, float[:,:] imGx, float[:,:] imGy)
    cdef float _calculateRGC(self, int xM, int yM, float[:,:] imGx, float[:,:] imGy) nogil
    cdef float _calculateDW(self, float distance) nogil
    cdef float _calculateDk(self, float Gx, float Gy, float dx, float dy, float distance) nogil
