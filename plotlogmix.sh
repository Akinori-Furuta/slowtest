#!/bin/bash
#plot mixed log file random-read/write.

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

function Help() {
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

FileGroups=(`ls *.txt | gawk 'BEGIN{FS="-"} {printf("%s-%s\n", $2, $3);}' | uniq`)

for g in ${FileGroups[*]}
do
	BlocksMinMin=4294967295
	BlocksMaxMax=0
	FileSizePrev=0
	ModelPrev=""
	DoDirectPrev=""
	DoDirectRandomPrev=""

	GnuplotVarFile=${TempPath}/${uuid}-`basename ${g%.*}-gp.txt`
	part_rand_file=${TempPath}/${uuid}-`basename ${g%.*}-prand.txt`
	part_read_file=${TempPath}/${uuid}-`basename ${g%.*}-pread.txt`
	part_write_file=${TempPath}/${uuid}-`basename ${g%.*}-pwrite.txt`

	echo -n > ${part_rand_file}

	for f in *-${g}-*.txt
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

		FileSizeMi=`gawk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 ) ) }"`
		FileSizeGi=`gawk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`

		if (( ${FileSizeMi} < 20480 ))
		then
			FileSizeShow="${FileSizeMi}Mi"
		else
			FileSizeShow="${FileSizeGi}Gi"
		fi

		RWBytes=$(( ${BlockSize} * ${SequentialRWBlocks} ))
		RWBytesKi=`gawk "BEGIN { print  ${RWBytes} / 1024 }"`
		RWBytesMi=`gawk "BEGIN { print  ${RWBytesKi} / 1024 }"`

		RandomRWMinBytes=$(( ${BlockSize} * ${BlocksMinMin} ))
		RandomRWMaxBytes=$(( ${BlockSize} * ${BlocksMaxMax} ))

		RandomRWMinBytesKi=`gawk "BEGIN { print  ${RandomRWMinBytes} / 1024 }"`
		RandomRWMaxBytesKi=`gawk "BEGIN { print  ${RandomRWMaxBytes} / 1024 }"`

		if [[ -n ${LBASectors} ]]
		then
			CapacityGB=`gawk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `
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

	rm ${part_rand_file}

	part_read_size=`stat --format=%s ${part_read_file}`
	if (( ${part_read_size} > 0 ))
	then
		ra_r_tspeed_at_png=${f%.*}-mr-ts_at.png
		echo "${f}: ${ra_r_tspeed_at_png}: Plot mixed random read transfer speed - access time."
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
			> ${ra_r_tspeed_at_png}

		ra_r_tlength_at_png=${f%.*}-mr-tl_at.png
		echo "${f}: ${ra_r_tlength_at_png}: Plot mixed random read transfer length - access time."
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot reads of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read\(\) call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#00c000"
EOF
		gnuplot -e "log_file=\"${part_read_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
			> ${ra_r_tlength_at_png}

		ra_r_tspeed_tlength_png=${f%.*}-mr-ts_tl.png
		echo "${f}: ${ra_r_tspeed_tlength_png}: Plot mixed random read transfer speed - transfer length."
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
			> ${ra_r_tspeed_tlength_png}

		rm ${GnuplotVarFile}
	else
		echo "${g}: No read record in random access records."
	fi

	rm "${part_read_file}"

	part_write_size=`stat --format=%s ${part_write_file}`
	if (( ${part_write_size} > 0 ))
	then
		ra_w_tspeed_at_png=${f%.*}-mw-ts_at.png
		echo "${f}: ${ra_w_tspeed_at_png}: Plot mixed random write transfer speed - access time."
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
			> ${ra_w_tspeed_at_png}

		ra_w_tlength_at_png=${f%.*}-mw-tl_at.png
		echo "${f}: ${ra_w_tlength_at_png}: Plot mixed random write transfer length - access time."
		cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGBTitle},\\n\
plot writes of random read/write \(mixed size range\)\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write\(\) call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#ff0000"
EOF
		gnuplot -e "log_file=\"${part_write_file}\"; load \"${GnuplotVarFile}\"; \
			    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
			> ${ra_w_tlength_at_png}

		ra_w_tspeed_tlength_png=${f%.*}-mw-ts_tl.png
		echo "${f}: ${ra_w_tspeed_tlength_png}: Plot mixed random write transfer speed - transfer length."
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
			> ${ra_w_tspeed_tlength_png}

		rm "${GnuplotVarFile}"
	else
		echo "${g}: No write record in random access records."
	fi

	rm "${part_write_file}"
done
