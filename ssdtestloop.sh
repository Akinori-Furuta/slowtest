#!/bin/bash
# Run loop test.
#
#  Copyright 2012 Akinori Furuta<afuruta@m7.dion.ne.jp>.
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
my_dir=`readlink -f "${my_dir}"`

source "${my_dir}/ssdtestcommon.sh"

uuid=`cat /proc/sys/kernel/random/uuid`

# Parse Argument

function Help() {
	#     0         1         2         3         4         5         6         7
	#     01234567890123456789012345678901234567890123456789012345678901234567890123456789
	echo "Run SSD performance test loop."
	echo "$0 [-L OptionalLabel] [-h] [-C num] test_file_or_directory"
	echo "-L OptionalLabel : Jam string into log directory path."
	echo "-C num : Run test num times."
	echo "-h : Show this help."
	echo "test_file_or_directory: "
	echo "  Test file name to read and write, or test directory to create"
	echo "  temporal test file to read and write."
	echo "This script create logs ./log-\${OptionalLabel}{StorageModelName}-{DateCode}"
	exit 1

}

parsed_arg=( `getopt C:h $*` )
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
		(-C) # Loop Count.
			i=$(( ${i} + 1 ))
			LoopCount="${parsed_arg[${i}]}"
		;;
		(-L) # OptionalLabel
			i=$(( ${i} + 1 ))
			OptionalLabel="${parsed_arg[${i}]}"
		;;
		(-h) # Help.
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

if [[ -z ${LoopCount} ]]
then
	echo "$0: No loop count (-C num) option. Specify loop count with -C num."
	exit 1
fi

LoopCountFile="${my_base%.*}_$$_loop.txt"
echo ${LoopCount} > "${LoopCountFile}"
echo "${LoopCountFile}: To up or down test times, edit number in this file."
L_OptionLabel=""

if [[ -n ${OptionLabel} ]]
then
	L_OptionLabel="-L ${OptionLabel}"
fi

done_flag=${my_base%.sh}_done.tmp

rm "${done_flag}"
i=0
while (( ${i} < ${LoopCount} ))
do
	${my_dir}/ssdtest.sh ${L_OptionLabel} ${TestFile}

	i=$(( ${i} + 1 ))

	if [[ -f "${LoopCountFile}" ]]
	then
		loop_count=`cat "${LoopCountFile}"`
		if ( echo ${loop_count} | grep -q '^[0-9][0-9]*$' )
		then
			LoopCount=${loop_count}
		fi
	fi
done
echo ${i} > "${done_flag}"
echo "$0: Done loop test."
rm "${LoopCountFile}"
