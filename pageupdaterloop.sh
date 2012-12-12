#!/bin/bash
# Run page update loop.
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

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`

# Parse Argument

function Help() {
	#     0         1         2         3         4         5         6         7
	#     01234567890123456789012345678901234567890123456789012345678901234567890123456789
	echo "Repeat creating html pages from log directories."
	echo "$0 [-T seconds] [update-directory]"
	echo "update-directory: "
	echo "  Contains log-* directories."
	echo "-T seconds: Repeat interval time in seconds."
	exit 1

}

parsed_arg=( `getopt hT: $*` )
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
		(-T) # Interval Time.
			i=$(( ${i} + 1 ))
			IntervalTime=${parsed_arg[${i}]}
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


if [[ -z "${parsed_arg[${i}]}" ]]
then
	Help
	exit 1
fi

if [[ -z ${IntervalTime} ]]
then
	IntervalTime=60
fi

UpdateDirectory="${parsed_arg[${i}]}"

cd "${UpdateDirectory}"

function UpdateFile() {
	if [[ ! -e "$2" ]]
	then
		# 1st update
		mv "$1" "$2"
	else
		if ( ! cmp -s "$1" "$2" )
		then
			# Not same file.
			mv -f "$1" "$2"
		else
			# Same file.
			rm "$1"
		fi
	fi
}

while [[ ! -f "ssdtestloop_done.tmp" ]]
do
	${my_dir}/pageupdater.sh . > index.html.new
	UpdateFile index.html.new index.html
	sleep ${IntervalTime}
done
echo "$0: Terminated loop."
