/* 
   A C-program for MT19937, with initialization improved 2002/1/26.
   Coded by Takuji Nishimura and Makoto Matsumoto.

   Before using, initialize the state by using init_genrand(seed)  
   or init_by_array(init_key, key_length).

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.                          
   Copyright (C) 2005, Mutsuo Saito,
   All rights reserved.                          

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

     1. Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

     2. Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

     3. The names of its contributors may not be used to endorse or promote 
        products derived from this software without specific prior written 
        permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


   Any feedback is very welcome.
   http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html
   email: m-mat @ math.sci.hiroshima-u.ac.jp (remove space)
*/

/* Change log.
   2012.10.14 introduce bit size specified int types.
              Akinori Furuta <afuruta@m7.dion.ne.jp>
   2012.10.14 introduce doxygen style comment. 
              Akinori Furuta <afuruta@m7.dion.ne.jp>
*/

#include <stdio.h>
#include "mt19937ar.h"

/* Period parameters */
#define N 624
#define M 397
#define MATRIX_A (uint32_t)(0x9908b0dfUL)   /*!< constant vector a */
#define UPPER_MASK (uint32_t)(0x80000000UL) /*!< most significant w-r bits */
#define LOWER_MASK (uint32_t)(0x7fffffffUL) /*!< least significant r bits */

static uint32_t mt[N]; /*!< the array for the state vector  */
static int mti=N+1; /* mti==N+1 means mt[N] is not initialized */

/*! initializes mt[N] with a seed
    @param s random seed.
*/
void init_genrand(uint32_t s)
{
    mt[0]= s;
    for (mti=1; mti<N; mti++) {
        mt[mti] = 
	    (1812433253UL * (mt[mti-1] ^ (mt[mti-1] >> 30)) + mti); 
        /* See Knuth TAOCP Vol2. 3rd Ed. P.106 for multiplier. */
        /* In the previous versions, MSBs of the seed affect   */
        /* only MSBs of the array mt[].                        */
        /* 2002/01/09 modified by Makoto Matsumoto             */
    }
}

/*! initialize by an array with array-length
    @param init_key points the array for initializing keys.
    @param  key_length the number of elements in array pointed by init_key
    @note   slight change for C++, 2004/2/26
*/
void init_by_array(uint32_t init_key[], int key_length)
{
    int i, j, k;
    init_genrand((uint32_t)(19650218UL));
    if (key_length<0) {
        printf("%s: Warning: key_length should be "
               "grater than zero. key_length=%d\n"
              , __func__, key_length
        );
        return;
    }
    i=1; j=0;
    k = (N>key_length ? N : key_length);
    for (; k; k--) {
        mt[i] = (mt[i] ^ ((mt[i-1] ^ (mt[i-1] >> 30)) * (uint32_t)(1664525UL)))
          + init_key[j] + j; /* non linear */
        i++; j++;
        if (i>=N) { mt[0] = mt[N-1]; i=1; }
        if (j>=key_length) j=0;
    }
    for (k=N-1; k; k--) {
        mt[i] = (mt[i] ^ ((mt[i-1] ^ (mt[i-1] >> 30)) * (uint32_t)(1566083941UL)))
          - i; /* non linear */
        i++;
        if (i>=N) { mt[0] = mt[N-1]; i=1; }
    }

    mt[0] = 0x80000000UL; /* MSB is 1; assuring non-zero initial array */ 
}

/*! generates a random number on [0,0xffffffff]-interval
    @return uint32_t generated random number.
*/
uint32_t genrand_uint32(void)
{
    uint32_t y;

#if (!defined(CONFIG_2SCOMP))
    static const uint32_t mag01[2]={0x0UL, MATRIX_A};
#endif /* (!defined(CONFIG_2SCOMP)) */
    /* mag01[x] = x * MATRIX_A  for x=0,1 */

    if (mti >= N) { /* generate N words at one time */
        int kk;

        if (mti == N+1)   /* if init_genrand() has not been called, */
            init_genrand((uint32_t)(5489UL)); /* a default initial seed is used */

        for (kk=0;kk<N-M;kk++) {
            y = (mt[kk]&UPPER_MASK)|(mt[kk+1]&LOWER_MASK);
#if (defined(CONFIG_2SCOMP))
            mt[kk] = mt[kk+M] ^ ((uint32_t)(0-(y & 0x1UL)) & MATRIX_A) ^ (y >> 1);
#else /* (defined(CONFIG_2SCOMP)) */
            mt[kk] = mt[kk+M] ^ (y >> 1) ^ mag01[y & 0x1UL];
#endif /* (defined(CONFIG_2SCOMP)) */
        }
        for (;kk<N-1;kk++) {
            y = (mt[kk]&UPPER_MASK)|(mt[kk+1]&LOWER_MASK);
#if (defined(CONFIG_2SCOMP))
            mt[kk] = mt[kk+(M-N)] ^ ((uint32_t)(0-(y & 0x1UL)) & MATRIX_A) ^ (y >> 1);
#else /* (defined(CONFIG_2SCOMP)) */
            mt[kk] = mt[kk+(M-N)] ^ (y >> 1) ^ mag01[y & 0x1UL];
#endif /* (defined(CONFIG_2SCOMP)) */
        }
        y = (mt[N-1]&UPPER_MASK)|(mt[0]&LOWER_MASK);
#if (defined(CONFIG_2SCOMP))
        mt[N-1] = mt[M-1] ^ ((uint32_t)(0-(y & 0x1UL)) & MATRIX_A) ^ (y >> 1);
#else /* (defined(CONFIG_2SCOMP)) */
        mt[N-1] = mt[M-1] ^ (y >> 1) ^ mag01[y & 0x1UL];
#endif /* (defined(CONFIG_2SCOMP)) */

        mti = 0;
    }
  
    y = mt[mti++];

    /* Tempering */
    y ^= (y >> 11);
    y ^= (y << 7) & 0x9d2c5680UL;
    y ^= (y << 15) & 0xefc60000UL;
    y ^= (y >> 18);

    return y;
}

/*! generates a random number on [0,0x7fffffff]-interval
    @return int32_t generated random number.
*/
int32_t genrand_int31(void)
{
    return (int32_t)(genrand_uint32()>>1);
}

/*! generates a random number on [0,1]-real-interval 
    @return double generated random number.
*/
double genrand_real1(void)
{
    return genrand_uint32()*(1.0/4294967295.0); 
    /* divided by 2^32-1 */ 
}

/*! generates a random number on [0,1)-real-interval 
    @return double generated random number.
*/
double genrand_real2(void)
{
    return genrand_uint32()*(1.0/4294967296.0); 
    /* divided by 2^32 */
}

/*! generates a random number on (0,1)-real-interval
    @return double generated random number.
*/
double genrand_real3(void)
{
    return (((double)genrand_uint32()) + 0.5)*(1.0/4294967296.0); 
    /* divided by 2^32 */
}

/*! generates a random number on [0,1) with 53-bit resolution
    @return double generated random number.
*/
double genrand_res53(void) 
{ 
    uint32_t a=genrand_uint32()>>5, b=genrand_uint32()>>6; 
    return(a*67108864.0+b)*(1.0/9007199254740992.0); 
} 
/* These real versions are due to Isaku Wada, 2002/01/09 added */
