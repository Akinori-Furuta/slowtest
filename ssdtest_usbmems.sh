#!/bin/bash
# This script warap ssdtest.sh

my_base=`basename "$0"`
my_dir=`dirname "$0"`

export SEQUENTIAL_DIRECT=y
export SEQUENTIAL_BLOCKS=16384
export RANDOM_MAX_BLOCKS_MAG=8
export RANDOM_MAX_BLOCKS_BASE=128
export RANDOM_MAX_BLOCKS_LEVEL=4

${my_dir}/ssdtest.sh $*
