#!/bin/bash
# Will be sourced by bash.
# for USB / Card memory plot settings.

my_base=`basename "$0"`
my_dir=`dirname "$0"`

export	SEQUENTIAL_TRANSFER_SPEED_MIN="0.0"
export	SEQUENTIAL_TRANSFER_SPEED_MAX="5.0e+7"

export	RANDOM_TRANSFER_SPEED_MIN="1.0e+3"
export	RANDOM_TRANSFER_SPEED_MAX="1.0e+10"

${my_dir}/plotlogmix.sh $*
