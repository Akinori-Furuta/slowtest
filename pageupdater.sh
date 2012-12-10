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

function BytesToShowBytes() {
	echo $1 | awk 'BEGIN {u[0]="";u[1]="Ki";u[2]="Mi";u[3]="Gi";u[4]="Ti";u[5]="Pi";u[6]="Ei";}\
	{a=$1;lk=log(a)/log(1024);m=int(lk);i=0;a=a/(exp(log(1024)*m));d=log(a)/log(10);f=3-d;printf("%4.*f%s\n",f,a,u[m]);}'
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
	log_files=(`ls -t`)
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

Year4=`date +%Y`
Year01Part=${Year4:0:2}
Year23Part=${Year4:2:2}
DateOffset=`date +%Z`

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
echo "<TABLE border=1>"
echo "<TR><TH>Test log<TH>Pass<TH>Fail<TH>Written bytes<TH>Read bytes<TH>Accumulated written bytes<TH>Accumulated read bytes</TR>"
WriteBytesAll=0
ReadBytesAll=0
i=0
for d in ${log_dirs[*]}
do
	i=$(( ${i} + 1 ))
	DirectoryDate=`echo ${d} | cut -d - -f 3`
	DirectoryDateY2=${DirectoryDate:0:2}
	if (( ${DirectoryDateY2} > ${Year23Part} ))
	then
		Year01Part=$(( ${Year01Part} - 1 ))
	fi

	DirectoryDateFormed=`echo ${Year01Part}${DirectoryDate} ${DateOffset} \
		| awk '{printf("%s/%s/%s %s:%s:%s %s", \
		substr($1,1,4),  substr($1,5,2),  substr($1,7,2), \
		substr($1,9,2), substr($1,11,2), substr($1,13,2), \
		$2 \
		);}'`

	PassCount=0
	pass_count_file="${d}/pass_count_all.tmp"
	if [[ -f ${pass_count_file} ]]
	then
		PassCount=`cat ${pass_count_file}`
	fi

	FailCount=0
	fail_count_file="${d}/fail_count_all.tmp"
	if [[ -f ${fail_count_file} ]]
	then
		FailCount=`cat ${fail_count_file}`
	fi

	WriteBytesRound=0
	write_bytes_round_file="${d}/total_written_bytes.tmp"
	if [[ -f "${write_bytes_round_file}" ]]
	then
		WriteBytesRound=`cat "${write_bytes_round_file}"`
	fi

	ReadBytesRound=0
	read_bytes_round_file="${d}/total_read_bytes.tmp"
	if [[ -f "${read_bytes_round_file}" ]]
	then
		ReadBytesRound=`cat "${read_bytes_round_file}"`
	fi

	echo "<TR>"
	echo -n "<TD><A href=\"${d}/index.html\">TestDate: ${DirectoryDateFormed}, Round: ${i}</A>"
	echo -n "<TD align="center">${PassCount}<TD align="center">${FailCount}"
	echo -n "<TD>`BytesToShowBytes ${WriteBytesRound}`(${WriteBytesRound})"
	echo -n "<TD>`BytesToShowBytes  ${ReadBytesRound}`(${ReadBytesRound})"
	WriteBytesAll=$(( ${WriteBytesAll} + ${WriteBytesRound} ))
	ReadBytesAll=$(( ${ReadBytesAll} + ${ReadBytesRound} ))
	echo -n "<TD>`BytesToShowBytes ${WriteBytesAll}`(${WriteBytesAll})"
	echo -n "<TD>`BytesToShowBytes ${ReadBytesAll}`(${ReadBytesAll})"
	echo "</TR>"
done
echo "</TABLE>"
echo "</BODY>"
echo "</HTML>"

