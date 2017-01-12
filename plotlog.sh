#!/bin/bash
#plot log file as sequential-write, random-read/write, and sequential-read parts.

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
	ModelSmart="`grep 'Device[[:space:]]*Model' ${header} \
		| awk 'BEGIN {FS=\":\";} {print $2;}' \
		| sed -e 's/^[[:space:]]*//' \
		| sed -e 's/[[:space:]]*$//' \
		| tr ' ' '_'`"
	ModelLen=${#Model}
	ModelSmartLen=${#ModelSmart}
	if (( ${ModelLen} < ${ModelSmartLen} ))
	then
		Model="${ModelSmart}"
	fi
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

	if [[ -z  ${FileSize} ]]
	then
		echo "${f}: Not access log, skip."
		rm ${header}
		continue
	fi

	contain_plot_data=0
	if [[ "${FillFile}x" == "yx" ]]
	then
		contain_plot_data=1
	fi

	if [[ -n ${Repeats} ]]
	then
		if (( ${Repeats} > 0 ))
		then
			contain_plot_data=1
		fi
	else
		Repeats=0
	fi

	if [[ "${DoReadFile}x" != "nx" ]]
	then
		contain_plot_data=1
	fi

	if (( ${contain_plot_data} == 0 ))
	then
		echo "${f}: Not access log, skip."
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

	DoDirectRandom='with O_DIRECT'
	if ( echo ${DoDirect} | grep -q 'N' )
	then
		DoDirectRandom='without O_DIRECT'
	fi

	rm ${header}

	GnuplotVarFile=${TempPath}/${uuid}-`basename ${f%.*}-gp.txt`
	part_data_file=${TempPath}/${uuid}-`basename ${f%.*}-pd.txt`

	if [[ "${FillFile}x" == "yx" ]]
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

	if (( ${Repeats} > 0 ))
	then
		ra_file=${TempPath}/${uuid}-`basename ${f%.*}-ra.txt`
		sed -n '/^i,[[:space:]]/,/close/ {p}' ${f} | grep '^[[:space:]]*[0-9]' | sed -n 's/,//gp' > ${ra_file}
		ra_file_size=`stat --format=%s ${ra_file}`
		if (( ${ra_file_size} > 0 ))
		then
			ra_r_tspeed_at_png=${f%.*}-rr-ts_at.png
			echo "${f}: ${ra_r_tspeed_at_png}: Plot random read transfer speed - access time."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot reads of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read() call, \
${DoDirectRandom}\\ntransfer speed - access time"
pointcolor="#00c000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
			grep 'r' "${ra_file}"  > ${part_data_file}
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				load \"${my_dir}/random-ts_at.gnuplot\"; quit" \
				> ${ra_r_tspeed_at_png}


			ra_r_tlength_at_png=${f%.*}-rr-tl_at.png
			echo "${f}: ${ra_r_tlength_at_png}: Plot random read transfer length - access time."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot reads of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read() call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#00c000"
EOF
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
				> ${ra_r_tlength_at_png}

			ra_r_tspeed_tlength_png=${f%.*}-rr-ts_tl.png
			echo "${f}: ${ra_r_tspeed_tlength_png}: Plot random read transfer speed - transfer length."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot reads of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read() call, \
${DoDirectRandom}\\ntransfer speed - transfer length"
pointcolor="#00c000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/random-ts_tl.gnuplot\"; quit" \
				> ${ra_r_tspeed_tlength_png}

			rm ${part_data_file}

			ra_w_tspeed_at_png=${f%.*}-rw-ts_at.png
			echo "${f}: ${ra_w_tspeed_at_png}: Plot random write transfer speed - access time."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot writes of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write() call, \
${DoDirectRandom}\\ntransfer speed - access time"
pointcolor="#ff0000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
			grep 'w' "${ra_file}" > ${part_data_file}
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/random-ts_at.gnuplot\"; quit" \
				> ${ra_w_tspeed_at_png}

			ra_w_tlength_at_png=${f%.*}-rw-tl_at.png
			echo "${f}: ${ra_w_tlength_at_png}: Plot random write transfer length - access time."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot writes of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write() call, \
${DoDirectRandom}\\ntransfer length - access time"
pointcolor="#ff0000"
EOF
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/random_tlength_at.gnuplot\"; quit" \
				> ${ra_w_tlength_at_png}

			ra_w_tspeed_tlength_png=${f%.*}-rw-ts_tl.png
			echo "${f}: ${ra_w_tspeed_tlength_png}: Plot random write transfer speed - transfer length."
			cat << EOF > ${GnuplotVarFile}
set title "${Model} ${CapacityGB}G bytes,\\n\
plot writes of random read/write\\n\
${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write() call, \
${DoDirectRandom}\\ntransfer speed - transfer length"
pointcolor="#ff0000"
set yrange [ ${RANDOM_TRANSFER_SPEED_MIN} : ${RANDOM_TRANSFER_SPEED_MAX} ] noreverse nowriteback
EOF
			gnuplot -e "log_file=\"${part_data_file}\"; load \"${GnuplotVarFile}\"; \
				    load \"${my_dir}/random-ts_tl.gnuplot\"; quit" \
				> ${ra_w_tspeed_tlength_png}

			rm "${part_data_file}"
			rm "${ra_file}"
		else
			echo "${f}: Empty random access log."
		fi
	fi

	if [[ "${DoReadFile}x" != "nx" ]]
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
