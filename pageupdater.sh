#!/bin/bash
# Run test loop.
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
	echo "Create html pages from log directories."
	echo "$0 [update-directory]"
	echo "update-directory: "
	echo "  Contains log-* directories."
	exit 1

}

parsed_arg=( `getopt h $*` )
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

log_dirs=(`ls -d -F log-* | grep '/$' | sed -n 's!/$!!p'`)

i=0
for d in ${log_dirs[*]}
do
	i=$(( ${i} + 1 ))
	TestDone="${d}/.mark_ssdtest_done"
	PlotDone="${d}/.mark_plot_done"
	PlotTemporal="${d}/.mark_plot_temporal"
	if [[ -f "${PlotDone}" ]]
	then
		continue
	fi

	final_plot=0
	update_plot=0
	if [[ -f "${TestDone}" ]]
	then
		final_plot=1
		update_plot=1
	fi
	cd "${d}"
	log_files=(`ls -t | grep -v [.]html$`)
	if [[ ${log_files[0]} == *.txt ]]
	then
		update_plot=1
	fi
	if (( ${update_plot} != 0 ))
	then
		${my_dir}/plotlogseq.sh
		${my_dir}/plotlogmix.sh
		${my_dir}/htmlplot.sh -C ${i} > index.html.new
		UpdateFile index.html.new index.html
	fi
	cd ".."

	if (( ${final_plot} != 0 ))
	then
		touch "${PlotDone}"
	else
		touch "${PlotTemporal}"
	fi
done

# @note It slightly buggy, I don't care at acrossing 2099 to 2100.
YearX100Part=`date +%Y | cut -c1-2`

first_log=""

d=${log_dirs[0]}

if [[ -d ${d} ]]
then
	cd "${d}"
	log_files=( *.txt )
	cd ..
	if [[ -f ${d}/${log_files[0]} ]]
	then
		first_log=${d}/${log_files[0]}
	fi
fi

if [[ -n "${first_log}" ]]
then
	source ${my_dir}/readcondition.sh ${first_log}
fi

echo "<HTML>"
echo "<HEAD>"
echo "<TITLE>Model: ${Model} ${CapacityGBTitle} - Continous access test</TITLE>"
echo "</HEAD>"
echo "<BODY>"
echo "<H1>Model: ${Model} ${CapacityGBTitle} - Continous access test</H1>"
echo "<HR>"
echo "<TABLE>"
i=0
for d in ${log_dirs[*]}
do
	i=$(( ${i} + 1 ))
	DirectoryDate=`echo ${d} | cut -d - -f 3`
	DateOffset=`date +%Z`

	DirectoryDateFormed=`echo ${YearX100Part}${DirectoryDate} ${DateOffset} \
		| awk '{printf("%s/%s/%s %s:%s:%s %s", \
		substr($1,1,4),  substr($1,5,2),  substr($1,7,2), \
		substr($1,9,2), substr($1,11,2), substr($1,13,2), \
		$2 \
		);}'`

	echo "<TR>"
	echo "<TD><A href=\"${d}/index.html\">TestDate: ${DirectoryDateFormed}, Round: ${i}</A>"
	echo "</TR>"
done
echo "</TABLE>"
echo "</BODY>"
echo "</HTML>"
