from ..workflow import Workflow
from ...core.transform import Radiality, CRShiftAndMagnify


import numpy as np


def SRRF(image, magnification=5, ringRadius=0.5, border=0, radialityPositivityConstraint=True, doIntensityWeighting=True, _force_run_type=None):
    """
    SRRF analysis of a single image
    """



    _SRRF = Workflow((CRShiftAndMagnify(),(image, 0,0,magnification,magnification),{}),
                    (Radiality(),(image, 'PREV_RETURN_VALUE_0_0'),{'magnification':magnification, 'ringRadius':ringRadius, 'border':border,'radialityPositivityConstraint':radialityPositivityConstraint,'doIntensityWeighting':doIntensityWeighting}))
    
    
    return _SRRF.calculate(_force_run_type=_force_run_type)