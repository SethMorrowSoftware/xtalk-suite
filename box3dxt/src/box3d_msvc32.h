/* box3d_msvc32.h - two intrinsics 32-bit MSVC does not have.
 *
 * Box3D calls _InterlockedExchangeAdd64 (src/platform.h) and __popcnt64
 * (src/ctz.h) whenever _MSC_VER is defined. cl provides both for x64 and
 * ARM64 only: for x86 it assumes an undeclared extern returning int, and the
 * link fails on __InterlockedExchangeAdd64 and ___popcnt64 (the first
 * windows-x86 run, 2026-11-20). CMakeLists.txt force-includes this file into
 * the Box3D target for that one compiler, so the pinned source is not patched.
 *
 * The add is a compare-exchange loop over cmpxchg8b, which 32-bit x86 does
 * have. The bit count is the plain SWAR form, so it asks nothing of the CPU.
 * Box3D's only 64-bit atomic is its allocated-byte counter; its 64-bit LOAD
 * on this target is two 32-bit loads (__iso_volatile_load64), so
 * b3GetByteCount can be torn while another thread allocates. That is a
 * statistic, read by the shim between steps.
 */
#ifndef BOX3D_MSVC32_H
#define BOX3D_MSVC32_H

#if defined(_MSC_VER) && !defined(__clang__) && defined(_M_IX86)

#include <intrin.h>

static __inline __int64 _InterlockedExchangeAdd64(__int64 volatile *pTarget, __int64 pValue)
{
    __int64 tOld;
    do
    {
        tOld = *pTarget;
    } while (_InterlockedCompareExchange64(pTarget, tOld + pValue, tOld) != tOld);
    return tOld;
}

static __inline unsigned __int64 __popcnt64(unsigned __int64 pBlock)
{
    pBlock = pBlock - ((pBlock >> 1) & 0x5555555555555555ULL);
    pBlock = (pBlock & 0x3333333333333333ULL) + ((pBlock >> 2) & 0x3333333333333333ULL);
    pBlock = (pBlock + (pBlock >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
    return (pBlock * 0x0101010101010101ULL) >> 56;
}

#endif
#endif
