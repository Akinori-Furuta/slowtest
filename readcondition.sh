#!/bin/bash
# Bind plot graphs to html page.
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

function SHelp() {
	#     0         1         2         3         4         5         6         7
	#     01234567890123456789012345678901234567890123456789012345678901234567890123456789
	echo "$0 log_file_name"
	echo "log_file_name: Log file name to extract test condition."
	echo "This script is helper script. htmlplot.sh and pageupdater.sh source this."
	exit 1
}

s_my_base=`basename "$0"`
s_my_dir=`dirname "$0"`
s_my_dir=`readlink -f "${s_my_dir}"`


STempPath=/dev/shm
s_uuid=`cat /proc/sys/kernel/random/uuid`

# Parse Argument
s_parsed_arg=( `getopt h $*` )
if (( $? != 0 ))
then
	SHelp
fi

s_parsed_arg_n=${#s_parsed_arg[*]}

s_i=0
while (( ${s_i} < ${s_parsed_arg_n} ))
do
	s_opt="${s_parsed_arg[${s_i}]}"
	case ${s_opt} in
		(-h) # Help.
			SHelp
			exit 1
		;;
		(--)
			s_i=$(( ${s_i} + 1 ))
			break
		;;
	esac
	s_i=$(( ${s_i} + 1 ))
done

SLogFile=${s_parsed_arg[${s_i}]}

if [[ -z ${SLogFile} ]]
then
	echo "$0: Specify log_file_name"
	exit 1
fi

s_header=${STempPath}/${s_uuid}-`basename ${SLogFile%.*}-hd.txt`
sed -n '1,/Seed(-s):/ {p}' ${SLogFile} > ${s_header}

Model=`grep 'Model=' ${s_header} | cut -d ',' -f 1 | cut -d '=' -f 2`
FileSize=`grep 'FileSize(-f):' ${s_header} | cut -d ':' -f 2 | tr -d [[:space:]]`
BlockSize=`grep 'BlockSize(-b):' ${s_header} | cut -d ':' -f 2`
SequentialRWBlocks=`grep 'SequentialRWBlocks(-u):' ${s_header} | cut -d ':' -f 2`
BlocksMin=`grep 'BlocksMin(-i):' ${s_header} | cut -d ':' -f 2`
BlocksMax=`grep 'BlocksMax(-a):' ${s_header} | cut -d ':' -f 2`
DoDirect=`grep 'DoDirect(-d):' ${s_header} | cut -d ':' -f 2 | tr -d [[:space:]]`
FillFile=`grep 'FillFile(-p):' ${s_header} | cut -d ':' -f 2 | tr -d [[:space:]]`
DoRandomAccess=`grep 'DoReadFile(-x):' ${s_header} | cut -d ':' -f 2 | tr -d [[:space:]]`
DoReadFile=`grep 'DoReadFile(-r):' ${s_header} | cut -d ':' -f 2 | tr -d [[:space:]]`
Repeats=`grep 'Repeats(-n):' ${s_header} | cut -d ':' -f 2`
LBASectors=`sed -n '/LBAsects/ s/.*LBAsects=\([0-9][0-9]*\)/\1/p' ${s_header}`

FileSizeMi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 ) ) }"`
FileSizeGi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`

if (( ${FileSizeMi} < 20480 ))
then
	FileSizeShow="${FileSizeMi}Mi"
else
	FileSizeShow="${FileSizeGi}Gi"
fi

if [[ -n ${LBASectors} ]]
then
	CapacityGB=`awk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `
	CapacityGBTitle="${CapacityGB}G bytes(test file size ${FileSizeShow} bytes)"
else
	CapacityGB=0
	CapacityGBTitle="Unknown capacity (test file size ${FileSizeShow} bytes)"
fi

rm ${s_header}

