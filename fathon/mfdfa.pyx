#    mfdfa.pyx - mfdfa algorithm of fathon package
#    Copyright (C) 2019-2020  Stefano Bianchi
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

#cython: language_level=3

import numpy as np
cimport numpy as np
cimport cython
import ctypes

cdef extern from "cLoops.h" nogil:
    double flucMFDFAForwCompute(double *y, int curr_win_size, double q, int N, int pol_ord)
    double flucMFDFAForwBackwCompute(double *y, int curr_win_size, double q, int N, int pol_ord)

cdef class MFDFA:
    """MultiFractal Detrended Fluctuation Analysis class.

    Parameters
    ----------
    n : numpy ndarray
        Array of window's sizes used for the computation.
    tsVec : iterable
        Time series used for the analysis.
    F : numpy ndarray
        Array containing the values of the fluctuations in every window.
    listH : numpy ndarray
        Array containing the values of the slope of the fit at every q-order.
    qList : numpy ndarray
        Array containing the values of the q-orders.
    nStep : int
        Value of the step between two consecutive window's sizes in `n`.
    isComputed : bool
        Boolean value to know if `F` has been computed in order to prevent the computation of other functions that need `F`.
    """

    cdef:
        np.ndarray n
        np.ndarray tsVec, F, listH, qList
        int nStep
        bint isComputed

    def __init__(self, tsVec):
        self.tsVec = np.array(tsVec, dtype=float)
        self.tsVec = self.tsVec[~np.isnan(self.tsVec)]
        self.isComputed = False

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cdef cy_computeFlucVec(self, int tsLen, int nMin, np.ndarray[np.float64_t, ndim=1, mode='c'] q_list, int nMax, int polOrd, int nStep, bint revSeg):
        cdef Py_ssize_t i, j
        cdef int nLen
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] mtxf, vects
        cdef np.ndarray[int, ndim=1, mode='c'] vecn

        self.qList = q_list
        self.nStep = nStep
        vecn = np.arange(nMin, nMax + 1, nStep, dtype=ctypes.c_int)
        nLen = len(vecn)
        mtxf = np.zeros((len(q_list) * nLen, ), dtype=ctypes.c_double)
        vects = np.array(self.tsVec, dtype=ctypes.c_double)
        q_list_len = len(q_list)
        with nogil:
            if revSeg:
                for i in range(q_list_len):
                    for j in range(nLen):
                        mtxf[i*nLen+j] = flucMFDFAForwBackwCompute(&vects[0], vecn[j], q_list[i], tsLen, polOrd)
            else:
                for i in range(q_list_len):
                    for j in range(nLen):
                        mtxf[i*nLen+j] = flucMFDFAForwCompute(&vects[0], vecn[j], q_list[i], tsLen, polOrd)
        return vecn, np.reshape(mtxf, (len(self.qList), nLen))

    def computeFlucVec(self, nMin, qList, nMax=-999, polOrd=1, nStep=1, revSeg=False):
        """Computation of the fluctuations in every window for every q-order.

        Parameters
        ----------
        nMin : int
            Size of the smaller window used to compute `F`.
        qList : float or iterable or numpy ndarray
            List of q-orders used to compute `F`.
        nMax : int, optional
            Size of the bigger window used to compute `F` (default : len(`tsVec`)/4)).
        polOrd : int, optional
            Order of the polynomial to be fitted in every window (default : 1).
        nStep : int, optional
            Step between two consecutive window's sizes (default : 1).
        revSeg : bool, optional
            If True, the computation of `F` is repeated starting from the end of the time series (default : False).

        Returns
        -------
        numpy ndarray
            Array `n` of window's sizes.
        numpy ndarray
            qxn array `F` containing the values of the fluctuations in every window for every q-order.
        """
        tsLen = len(self.tsVec)

        if polOrd < 1:
            raise ValueError('Error: Polynomial order must be greater than 0.')
        if nStep < 1:
            raise ValueError('Error: Step for scales must be greater than 0.')
        if nMax == -999:
            nMax = int(tsLen / 4)
        if nMax < 3 or nMin < 3:
            raise ValueError('Error: Variable nMin and nMax must be at least equal to 3.')
        if nMax <= nMin:
            raise ValueError('Error: Variable nMax must be greater than variable nMin.')
        if nMax > tsLen:
            raise ValueError('Error: Variable nMax must be less than the input vector length.')
        if nMin < (polOrd + 2):
            raise ValueError('Error: Variable nMin must be at least equal to {}.'.format(polOrd + 2))

        if isinstance(qList, float):
            qList = np.array([qList], dtype=ctypes.c_double)
        elif isinstance(qList, list) or isinstance(qList, np.ndarray):
            qList = np.array(qList, dtype=ctypes.c_double)
        else:
            raise ValueError('Error: q_list type is {}. Expected float, list, or numpy array.'.format(type(q_list)))
            
        self.n, self.F = self.cy_computeFlucVec(tsLen, nMin, qList, nMax, polOrd, nStep, revSeg)
        self.isComputed = True
        
        return self.n, self.F

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    cpdef fitFlucVec(self, int nStart=-999, int nEnd=-999, float logBase=np.e, bint verbose=False):
        """Fit of the fluctuations values.

        Parameters
        ----------
        nStart : int, optional
            Size of the smaller window used to fit `F` at every q-order (default : first value of `n`).
        nEnd : int, optional
            Size of the bigger window used to fit `F` at every q-order (default : last value of `n`).
        logBase : float, optional
            Base of the logarithm for the log-log fit of `n` vs `F` (default : e).
        verbose : bool, optional
            Verbosity (default : False).

        Returns
        -------
        numpy ndarray
            Slope of the fit for every q-order.
        numpy ndarray
            Intercept of the fit for every q-order.
        """
        cdef int start, end, qLen
        cdef Py_ssize_t i
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] log_fit, list_H_intercept

        if self.isComputed:
            if nStart == -999:
                nStart = self.n[0]
            if nEnd == -999:
                nEnd = self.n[-1]
            if nStart > nEnd:
                raise ValueError('Error: Variable nEnd must be greater than variable nStart.')
            if (nStart < self.n[0]) or (nEnd > self.n[-1]):
                raise ValueError('Error: Fit limits must be included in interval [{}, {}].'.format(self.n[0], self.n[-1]))
            if (nStart not in self.n) or (nEnd not in self.n):
                raise ValueError('Error: Fit limits must be included in the n vector.')

            qLen = len(self.qList)
            start = int((nStart - self.n[0]) / self.nStep)
            end = int((nEnd - self.n[0]) / self.nStep)
            self.listH = np.zeros((qLen, ), dtype=ctypes.c_double)
            list_H_intercept = np.zeros((qLen, ), dtype=ctypes.c_double)
            if verbose:
                print('Fit limits: [{}, {}]'.format(nStart, nEnd))
                
            for i in range(qLen):
                log_fit = np.polyfit(np.log(self.n[start:end+1]) / np.log(logBase) , np.log(self.F[i, start:end+1]) / np.log(logBase), 1)
                self.listH[i] = log_fit[0]
                list_H_intercept[i] = log_fit[1]
                if verbose:
                    print('Fit result for q = {:.2f}: H intercept = {:.2f}, H = {:.2f}'.format(self.qList[i], list_H_intercept[i], self.listH[i]))
                    
            return self.listH, list_H_intercept
        else:
            print('Nothing to fit, fluctuations vector has not been computed yet.')

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef computeMassExponents(self):
        """Computation of the mass exponents.

        Returns
        -------
        numpy ndarray
            Mass exponents.
        """
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] tau

        if self.isComputed:
            tau = self.listH * self.qList - 1
            
            return tau
        else:
            print('Nothing to fit, fluctuations vector has not been computed yet.')

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    cpdef computeMultifractalSpectrum(self):
        """Computation of the multifractal spectrum.

        Returns
        -------
        numpy ndarray
            Singularity strengths.
        numpy ndarray
            Multifractal spectrum.
        """
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] tau, alpha, mfSpect

        if self.isComputed:
            if len(self.qList) > 1:
                tau = self.computeMassExponents()
                alpha = np.diff(tau) / (self.qList[1] - self.qList[0])
                mfSpect = self.qList[0:-1] * alpha - tau[0:-1]
                
                return alpha, mfSpect
            else:
                raise ValueError('Error: Number of q moments must be greater than one to compute multifractal spectrum.')
        else:
            print('Nothing to fit, fluctuations vector has not been computed yet.')
