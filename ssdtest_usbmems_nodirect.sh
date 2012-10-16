#!/bin/bash
# Will be sourced by bash.

export MAX_SECTORS_RANDOM_LONG=131072
export MAX_SECTORS_RANDOM_MIDDLE=4096
export MAX_SECTORS_RANDOM_SHORT=128
export RANDOM_REPEATS=8192
export DEF_CONFIG_RA_L="-py -xb -rn -my -dn -b 512 -i 1 -a ${MAX_SECTORS_RANDOM_LONG}   -n ${RANDOM_REPEATS}"
export DEF_CONFIG_RA_M="-pn -xb -rn -my -dn -b 512 -i 1 -a ${MAX_SECTORS_RANDOM_MIDDLE} -n ${RANDOM_REPEATS}"
export DEF_CONFIG_RA_S="-pn -xb -ry -my -dn -b 512 -i 1 -a ${MAX_SECTORS_RANDOM_SHORT}  -n ${RANDOM_REPEATS}"
