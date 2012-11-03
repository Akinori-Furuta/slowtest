#!/bin/bash
# Light test script.
# This script warap ssdtest.sh

my_base=`basename "$0"`
my_dir=`dirname "$0"`

export LOOP_MAX=1

${my_dir}/ssdtest.sh $*
