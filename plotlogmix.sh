#!/bin/bash
# plot random-read/write performance from composite of log files.
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

function Help() {
	echo "Plot random access log."
	echo "$0 [-D] [-h] test_log_directory"
	echo "test_log_directory:"
	echo "  Directory contains log files created by ssdtest.sh tool."
	echo "  Graph plots will be stored in this directory."
	echo "-D   : Debug mode."
	echo "-h   : Print this help."
	exit 1
}

my_base=`basename "$0"`
my_dir=`dirname "$0"`

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`


if [[ -z ${GDFONTPATH} ]]
then
	# set font path suit for fedora and ubuntu.
	export GDFONTPATH=/usr/share/fonts/dejavu:/usr/share/fonts/truetype/ttf-dejavu
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


parsed_arg=( `getopt Dh $*` )
if (( $? != 0 ))
then
	Help
fi

OptionalLabel=""
Debug=0

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
		(-D)
			Debug=1
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

ReadBytes=0
WriteBytes=0

FileGroups=(`ls *.txt | grep -v 'bytes.txt$' | awk 'BEGIN{FS="-"} {printf("%s-%s\n", $2, $3);}' | uniq`)

for g in ${FileGroups[*]}
do
	BlocksMinMin=4294967295
	BlocksMaxMax=0
	FileSizePrev=0
	ModelPrev=""
	DoDirectPrev=""
	DoDirectRandomPrev=""

	if (( ${Debug} == 0 ))
	then
		GnuplotVarFile=${TempPath}/${uuid}-`basename ${g%.*}-gp.txt`
		part_rand_file=${TempPath}/${uuid}-`basename ${g%.*}-prand.txt`
		part_read_file=${TempPath}/${uuid}-`basename ${g%.*}-pread.txt`
		part_write_file=${TempPath}/${uuid}-`basename ${g%.*}-pwrite.txt`
	else
		# note: GnuplotVarFile will be overridden.
		GnuplotVarFile=${LogDirectory}/`basename ${g%.*}-gp.tmp`
		part_rand_file=${LogDirectory}/`basename ${g%.*}-prand.tmp`
		part_read_file=${LogDirectory}/`basename ${g%.*}-pread.tmp`
		part_write_file=${LogDirectory}/`basename ${g%.*}-pwrite.tmp`
	fi

	echo -n > ${part_rand_file}

	for f in `ls *-${g}-*.txt | grep -v 'bytes.txt$'`
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

		if [[ -z "${FileSize}" || -z "${BlocksMin}" || -z "${BlocksMax}"  ]]
		then
			echo "${f}: Not access log, skip."
			rm ${header}
			break
		fi

		if [[ -n ${Repeats} ]]
		then
			if (( ${Repeats} <= 0 ))
			then
				echo "${f}: No random access log."
				continue
			fi
		else
			echo "${f}: Not access log, skip."
			continue
		fi

		if (( ${BlocksMinMin} > ${BlocksMin} ))
		then
			BlocksMinMin=${BlocksMin}
		fi

		if (( ${BlocksMaxMax} < ${BlocksMax} ))
		then
			BlocksMaxMax=${BlocksMax}
		fi

		if [[ "${ModelPrev}x" != "${Model}x" ]]
		then
			if [[ -z "${ModelPrev}" ]]
			then
				ModelPrev="${Model}"
			else
				echo "${f}: Model not match. Model=${Model}, ModelPrev=${ModelPrev}"
				rm ${header}
				break
			fi
		fi

		if (( ${FileSizePrev} != ${FileSize} ))
		then
			if (( ${FileSizePrev} >= 0 ))
			then
				FileSizePrev=${FileSize}
			else
				echo "${f}: FileSize not match. FileSize=${FileSize}, FileSizePrev=${FileSizePrev}"
				rm ${header}
				break
			fi
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

		RandomRWMinBytes=$(( ${BlockSize} * ${BlocksMinMin} ))
		RandomRWMaxBytes=$(( ${BlockSize} * ${BlocksMaxMax} ))

		RandomRWMinBytesKi=`awk "BEGIN { print  ${RandomRWMinBytes} / 1024 }"`
		RandomRWMaxBytesKi=`awk "BEGIN { print  ${RandomRWMaxBytes} / 1024 }"`

		if [[ -n ${LBASectors} ]]
		then
			CapacityGB=`awk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `
			CapacityGBTitle="${CapacityGB}G bytes(test file size ${FileSizeShow})"
		else
			CapacityGB=0
			CapacityGBTitle="Unknown capacity (test file size ${FileSizeShow})"
		fi

		DoDirectSequential='with O_DIRECT'
		if ( echo ${DoDirect} | grep -q 'n' )
		then
			DoDirectSequential='without O_DIRECT'
		fi

		DoDirectRandom='with O_DIRECT'
		if ( echo ${DoDirect} | grep -q 'N' )
		then
			DoDirectRandom='without O_DIRECT'
		fi

		if [[ "${DoDirectRandomPrev}x" != "${DoDirectRandom}x" ]]
		then
			if [[ -z ${DoDirectRandomPrev} ]]
			then
				DoDirectRandomPrev="${DoDirectRandom}"
			else
				echo "${f}: DoDirectRandom not match. ${DoDirectRandom}=\"${DoDirectRandom}\", ${DoDirectRandomPrev}=\"${DoDirectRandomPrev}\""
				rm ${header}
				break
			fi
		fi

		rm ${header}

		if (( ${Repeats} <= 0 ))
		then
			echo "${f}: No random access part."
			continue
		fi

		sed -n '/^i,[[:space:]]/,/close/ {p}' ${f} \
			| grep '^[[:space:]]*[0-9]' \
			| sed -n 's/,//gp' >> ${part_rand_file}
	done

	grep 'r' "${part_rand_file}"  > ${part_read_file}
	grep 'w' "${part_rand_file}"  > ${part_write_file}

	if (( ${Debug} == 0 ))
	then
		rm ${part_rand_file}
	fi

	part_read_size=`stat --format=%s ${part_read_file}`
	if (( ${part_read_size} > 0 ))
	then
		ra_r_tspeed_at_png=${f%.*}-mr-ts_at.png
		echo "${f}: ${ra_r_tspeed_at_png}: Plot mixed random read transfer speed - access time."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mr-ts_at-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot reads of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read\(\) call, \
${DoDirectRandom}\\ntransfer speed - access time"
pointcolor="#00c000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		gnuplot -e "log_file=\"${part_read_file}\"; load \"${GnuplotVarFile}\"; \
			load \"${my_dir}/random_tspeed_at.gnuplot\"; quit" \
			>   ${ra_r_tspeed_at_png}.new
		UpdateFile "${ra_r_tspeed_at_png}.new" "${ra_r_tspeed_at_png}"

		ra_r_tlength_at_png=${f%.*}-mr-tl_at.png
		echo "${f}: ${ra_r_tlength_at_png}: Plot mixed random read transfer length - access time."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mr-tl_at-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot reads of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read\(\) call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#00c000"
EOF
		gnuplot -e "log_file=\"${part_read_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
			>   ${ra_r_tlength_at_png}.new
		UpdateFile "${ra_r_tlength_at_png}.new" "${ra_r_tlength_at_png}"

		ra_r_tspeed_tlength_png=${f%.*}-mr-ts_tl.png
		echo "${f}: ${ra_r_tspeed_tlength_png}: Plot mixed random read transfer speed - transfer length."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mr-ts_tl-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot reads of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read\(\) call, \
${DoDirectRandom}\\ntransfer speed - transfer length"
pointcolor="#00c000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		gnuplot -e "log_file=\"${part_read_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tspeed_tlength.gnuplot\"; quit" \
			>   ${ra_r_tspeed_tlength_png}.new
		UpdateFile "${ra_r_tspeed_tlength_png}.new" "${ra_r_tspeed_tlength_png}"

		if (( ${Debug} == 0 ))
		then
			rm ${GnuplotVarFile}
		fi
	else
		echo "${g}: No read record in random access records."
	fi

	ra_r_total_bytes_tmp=${f%.*}-mr-bytes.tmp
	awk 'BEGIN{total=0;} {total+=strtonum($5);} END{printf("%d",total);}' ${part_read_file} > ${ra_r_total_bytes_tmp}.new
	mv -f ${ra_r_total_bytes_tmp}.new ${ra_r_total_bytes_tmp}

	if (( ${Debug} == 0 ))
	then
		rm "${part_read_file}"
	fi

	part_write_size=`stat --format=%s ${part_write_file}`
	if (( ${part_write_size} > 0 ))
	then
		ra_w_tspeed_at_png=${f%.*}-mw-ts_at.png
		echo "${f}: ${ra_w_tspeed_at_png}: Plot mixed random write transfer speed - access time."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mw-ts_at-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot writes of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write\(\) call, \
${DoDirectRandom}\\ntransfer speed - access time"
pointcolor="#ff0000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		gnuplot -e "log_file=\"${part_write_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tspeed_at.gnuplot\"; quit" \
			>   ${ra_w_tspeed_at_png}.new
		UpdateFile "${ra_w_tspeed_at_png}.new" "${ra_w_tspeed_at_png}"

		ra_w_tlength_at_png=${f%.*}-mw-tl_at.png
		echo "${f}: ${ra_w_tlength_at_png}: Plot mixed random write transfer length - access time."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mw-tl_at-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot writes of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write\(\) call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#ff0000"
EOF
		gnuplot -e "log_file=\"${part_write_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
			>   ${ra_w_tlength_at_png}.new
		UpdateFile "${ra_w_tlength_at_png}.new" "${ra_w_tlength_at_png}"

		ra_w_tspeed_tlength_png=${f%.*}-mw-ts_tl.png
		echo "${f}: ${ra_w_tspeed_tlength_png}: Plot mixed random write transfer speed - transfer length."
		if (( ${Debug} != 0 ))
		then
			GnuplotVarFile=${f%.*}-mw-ts_tl-gp.tmp
		fi
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot writes of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write\(\) call, \
${DoDirectRandom}\\ntransfer speed - transfer length"
pointcolor="#ff0000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
		gnuplot -e "log_file=\"${part_write_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tspeed_tlength.gnuplot\"; quit" \
			>   ${ra_w_tspeed_tlength_png}.new
		UpdateFile "${ra_w_tspeed_tlength_png}.new" "${ra_w_tspeed_tlength_png}"

		if (( ${Debug} == 0 ))
		then
			rm "${GnuplotVarFile}"
		fi
	else
		echo "${g}: No write record in random access records."
	fi

	ra_w_total_bytes_tmp=${f%.*}-mw-bytes.tmp
	awk 'BEGIN{total=0;} {total+=strtonum($5);} END{printf("%d",total);}' ${part_write_file} > ${ra_w_total_bytes_tmp}.new
	mv -f ${ra_w_total_bytes_tmp}.new ${ra_w_total_bytes_tmp}

	if (( ${Debug} == 0 ))
	then
		rm "${part_write_file}"
	fi
done
