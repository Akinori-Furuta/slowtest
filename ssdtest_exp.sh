#!/bin/bash
# Test SSD performance with exponential distribution.
# This script wraps ssdtest.sh
#
#  Copyright 2012, 2015 Akinori Furuta<afuruta@m7.dion.ne.jp>.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
#  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
#  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
#  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

my_base=`basename "$0"`
my_dir=`dirname "$0"`

function Help() {
	echo "Test SSD performance."
	echo "$0 [-L OptionalLabel] [-h] test_file_or_directory"
	echo "-L OptionalLabel : Jam string into log directory path."
	echo "-h : Show this help."
	echo "test_file_or_directory: "
	echo "  Test file name to read and write, or test directory to create"
	echo "  temporal test file to read and write."
	echo "This script create logs ./log-\${OptionalLabel}{StorageModelName}-{DateCode}"
	exit 1
}

# Parse Argument

parsed_arg=( `getopt L:h $*` )
if (( $? != 0 ))
then
	Help
fi

OptionalLabel=""

parsed_arg_n=${#parsed_arg[*]}

i=0
while (( ${i} < ${parsed_arg_n} ))
do
	opt="${parsed_arg[${i}]}"
	case ${opt} in
		(-L)
			i=$(( ${i} + 1 ))
			OptionalLabel="${parsed_arg[${i}]}"
		;;
		(-h)
			Help
			exit 1
		;;
		(--)
			i=$(( ${i} + 1 ))
			break
		;;
	esac
	i=$(( ${i} + 1 ))
done

if [[ -z ${parsed_arg[${i}]} ]]
then
	Help
	exit 1
fi

TestFile="${parsed_arg[${i}]}"

export SEQUENTIAL_WRITE_EXTRA_OPTIONS="-i exp"
export RANDOM_EXTRA_OPTIONS="-i exp"
export SEQUENTIAL_READ_EXTRA_OPTIONS="-i exp"

OptionLabelArg=""
if [[ -n "${OptionLabel}" ]]
then
	OptionLabelArg="-L \"${OptionLabel}\""
fi

${my_dir}/ssdtest.sh ${OptionLabelArg} ${TestFile}
