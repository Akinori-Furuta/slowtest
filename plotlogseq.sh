#!/bin/bash
# plot sequential-write, and sequential-read performance from log files.
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

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`


if [[ -z ${GDFONTPATH} ]]
then
	# set font path suit for fedora and ubuntu.
	export GDFONTPATH=/usr/share/fonts/dejavu:/usr/share/fonts/truetype/ttf-dejavu
fi

if [[ -z ${SEQUENTIAL_TRANSFER_SPEED_MIN} ]]
then
	SEQUENTIAL_TRANSFER_SPEED_MIN="0"
fi

if [[ -z ${SEQUENTIAL_TRANSFER_SPEED_MAX} ]]
then
	SEQUENTIAL_TRANSFER_SPEED_MAX="6.0e+8"
fi

if [[ -z ${RANDOM_TRANSFER_SPEED_MIN} ]]
then
	RANDOM_TRANSFER_SPEED_MIN="1.0e+5"
fi

if [[ -z ${RANDOM_TRANSFER_SPEED_MAX} ]]
then
	RANDOM_TRANSFER_SPEED_MAX="1.0e+10"
fi

# Parse Argument

function Help() {
	echo "Plot sequential log."
	echo "$0 test_log_directory"
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

if [[ -n ${parsed_arg[${i}]} ]]
then
	LogDirectory="${parsed_arg[${i}]}"
else
	LogDirectory="."
fi

cd "${LogDirectory}"

for f in *.txt
do
	header=${TempPath}/${uuid}-`basename ${f%.*}-hd.txt`
	sed -n '1,/Seed(-s):/ {p}' ${f} > ${header}

	Model=`grep 'Model=' ${header} | cut -d ',' -f 1 | cut -d '=' -f 2`
	FileSize=`grep 'FileSize(-f):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
	BlockSize=`grep 'BlockSize(-b):' ${header} | cut -d ':' -f 2`
	SequentialRWBlocks=`grep 'SequentialRWBlocks(-u):' ${header} | cut -d ':' -f 2`
	BlocksMin=`grep 'BlocksMin(-i):' ${header} | cut -d ':' -f 2`
	BlocksMax=`grep 'BlocksMax(-a):' ${header} | cut -d ':' -f 2`
	DoDirect=`grep 'DoDirect(-d):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
	FillFile=`grep 'FillFile(-p):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
	DoRandomAccess=`grep 'DoReadFile(-x):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
	DoReadFile=`grep 'DoReadFile(-r):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
	Repeats=`grep 'Repeats(-n):' ${header} | cut -d ':' -f 2`
	LBASectors=`sed -n '/LBAsects/ s/.*LBAsects=\([0-9][0-9]*\)/\1/p' ${header}`

	if [[ -z ${FileSize} ]]
	then
		echo "${f}: Not access log, skip. FileSize not found."
		rm ${header}
		continue
	fi

	if [[ -z ${FillFile} ]]
	then
		echo "${f}: Not access log, skip. FillFile not found."
		rm ${header}
		continue
	fi

	if [[ -z ${Repeats} ]]
	then
		echo "${f}: Not access log, skip. Repeats not found."
		rm ${header}
		continue
	fi

	if [[ -z ${DoReadFile} ]]
	then
		echo "${f}: Not access log, skip. DoReadFile not found."
		rm ${header}
		continue
	fi

	if [[ ( "${FillFile}" != "y" ) && ( "${DoReadFile}" != "y" ) ]]
	then
		echo "${f}: Not contain sequential access log."
		rm ${header}
		continue
	fi

	FileSizeMi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 ) ) }"`
	FileSizeGi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`

	if (( ${FileSizeMi} < 20480 ))
	then
		FileSizeShow="${FileSizeMi}Mi"
	else
		FileSizeShow="${FileSizeGi}Gi"
	fi

	RWBytes=$(( ${BlockSize} * ${SequentialRWBlocks} ))
	RWBytesKi=`awk "BEGIN { print  ${RWBytes} / 1024 }"`
	RWBytesMi=`awk "BEGIN { print  ${RWBytesKi} / 1024 }"`

	RandomRWMinBytes=$(( ${BlockSize} * ${BlocksMin} ))
	RandomRWMaxBytes=$(( ${BlockSize} * ${BlocksMax} ))

	RandomRWMinBytesKi=`awk "BEGIN { print  ${RandomRWMinBytes} / 1024 }"`
	RandomRWMaxBytesKi=`awk "BEGIN { print  ${RandomRWMaxBytes} / 1024 }"`

	if [[ -n ${LBASectors} ]]
	then
		CapacityGB=`awk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `
	else
		CapacityGB="Unknown"
	fi

	DoDirectSequential='with O_DIRECT'
	if ( echo ${DoDirect} | grep -q 'n' )
	then
		DoDirectSequential='without O_DIRECT'
	fi

	rm ${header}

	GnuplotVarFile=${TempPath}/${uuid}-`basename ${f%.*}-gp.txt`
	part_data_file=${TempPath}/${uuid}-`basename ${f%.*}-pd.txt`

	if [[ "${FillFile}" == "y" ]]
	then
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes, sequential write\\n\
${RWBytesMi}Mi bytes per one write() call, \
up to ${FileSizeShow} bytes, ${DoDirectSequential}\\ntransfer speed - progress"
pointcolor="#ff0000"
set yrange [ ${SEQUENTIAL_TRANSFER_SPEED_MIN} : ${SEQUENTIAL_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		sw_png=${f%.*}-sw.png
		echo "${f}: ${sw_png}: Plot sequential write."
		sed -n '/Twrite/,/close/ {p}' ${f} \
			| grep '^[0-9][.]' \
			| sed -n 's/,//gp' \
			| sed -n 's/%//gp' \
			> ${part_data_file}
		part_data_file_size=`stat --format=%s ${part_data_file}`
		if (( ${part_data_file_size} > 0 ))
		then
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/sequential_tspeed_prog.gnuplot\"; quit" \
				> ${sw_png}
		else
			echo "${f}: Empty sequential write log."
		fi
		rm ${part_data_file}
	fi

	if [[ "${DoReadFile}" != "n" ]]
	then
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes, sequential read\\n\
${RWBytesMi}Mi bytes per one read() call, up to ${FileSizeShow} bytes, \
${DoDirectSequential}\\ntransfer speed - progress"
pointcolor="#00c000"
set yrange [ ${SEQUENTIAL_TRANSFER_SPEED_MIN} : ${SEQUENTIAL_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		sr_png=${f%.*}-sr.png
		echo "${f}: ${sr_png}: Plot sequential read."
		sed -n '/Tread/,/close/ {p}' ${f} \
			| grep '^[0-9][.]' \
			| sed -n 's/,//gp' \
			| sed -n 's/%//gp' \
			> ${part_data_file}
		part_data_file_size=`stat --format=%s ${part_data_file}`
		if (( ${part_data_file_size} > 0 ))
		then
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/sequential_tspeed_prog.gnuplot\"; quit" \
				> ${sr_png}
		else
			echo "${f}: Empty sequential read log."
		fi

		rm "${part_data_file}"
	fi
	if [[ -f ${GnuplotVarFile} ]]
	then
		rm ${GnuplotVarFile}
	fi
done
