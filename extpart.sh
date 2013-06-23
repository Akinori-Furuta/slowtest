#!/bin/bash
#spilt log file into sequential-write, random-read/write, and sequential-read parts.

my_base=`basename "$0"`
my_dir=`dirname "$0"`

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`

SATA6R0G=600e+6
SATA3R0G=300e+6
SATA1R5G=150e+6

PlotXTimeMax=10
PlotXTimeMin=10e-6


for f in $*
do
	ext=${f##*.}
	if [[ "${ext}" != "txt" ]]
	then
		continue
	fi

	body=${f%.*}
	if ( echo "${body}" |  grep -q -e '[-]sw$' -e '[-]ra$' -e '[-]sr$' -e '[-]rr$' -e '[-]rw$' -e '[-]hd$' )
	then
		continue
	fi

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
	FileSize=`grep 'FileSize(-f):' ${header} | cut -d ':' -f 2`
	BlockSize=`grep 'BlockSize(-b):' ${header} | cut -d ':' -f 2`
	SequentialRWBlocks=`grep 'SequentialRWBlocks(-u):' ${header} | cut -d ':' -f 2`
	BlocksMin=`grep 'BlocksMin(-i):' ${header} | cut -d ':' -f 2`
	BlocksMax=`grep 'BlocksMax(-a):' ${header} | cut -d ':' -f 2`
	DoDirect=`grep 'DoDirect(-d):' ${header} | cut -d ':' -f 2`

	LBASectors=`sed -n '/LBAsects/ s/.*LBAsects=\([0-9][0-9]*\)/\1/p' ${header}`

	FileSizeGi=`gawk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`

	RWBytes=$(( ${BlockSize} * ${SequentialRWBlocks} ))
	RWBytesKi=`gawk "BEGIN { print  ${RWBytes} / 1024 }"`
	RWBytesMi=`gawk "BEGIN { print  ${RWBytesKi} / 1024 }"`

	RandomRWMinBytes=$(( ${BlockSize} * ${BlocksMin} ))
	RandomRWMaxBytes=$(( ${BlockSize} * ${BlocksMax} ))

	RandomRWMinBytesKi=`gawk "BEGIN { print  ${RandomRWMinBytes} / 1024 }"`
	RandomRWMaxBytesKi=`gawk "BEGIN { print  ${RandomRWMaxBytes} / 1024 }"`

	CapacityGB=`gawk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `

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

	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, sequential write\\n${RWBytesMi}Mi bytes per one write() call, up to ${FileSizeGi} Gi bytes, ${DoDirectSequential}\\ntransfer speed - progress"
EOF
	sw_file=${f%.*}-sw.txt
	sw_png=${f%.*}-sw.png
	sed -n '/Twrite/,/elp/ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sw_file}
	gnuplot -e "log_file=\"${sw_file}\"; load \"${GnuplotVarFile}\";load \"${my_dir}/sequential_write.gnuplot\"; quit" > ${sw_png}

	ra_file=${TempPath}/${uuid}-`basename ${f%.*}-ra.txt`
	sed -n '/^i,[[:space:]]/,/Tread/ {p}' ${f} | grep '^[[:space:]]*[0-9]' > ${ra_file}

	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, random read\\n${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read() call, ${DoDirectRandom}\\ntransfer speed - access time"
EOF
	ra_r_file=${f%.*}-rr.txt
	ra_r_png=${f%.*}-rr.png
	grep 'r' "${ra_file}" |  sed -n 's/,//gp' > ${ra_r_file}
	gnuplot -e "log_file=\"${ra_r_file}\"; load \"${GnuplotVarFile}\"; load \"${my_dir}/random_read.gnuplot\"; quit" > ${ra_r_png}

	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, random read\\n${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one read() call, ${DoDirectRandom}\\ntransfer length - access time"
EOF
	ra_r_at_tl_png=${f%.*}-rr-at_tl.png
	gnuplot -e "log_file=\"${ra_r_file}\"; load \"${GnuplotVarFile}\"; load \"${my_dir}/random_read_at-tl.gnuplot\"; quit" > ${ra_r_at_tl_png}


	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, random write\\n${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write() call, ${DoDirectRandom}\\ntransfer speed - access time"
EOF
	ra_w_file=${f%.*}-rw.txt
	ra_w_png=${f%.*}-rw.png
	grep 'w' "${ra_file}" | sed -n 's/,//gp'  > ${ra_w_file}
	gnuplot -e "log_file=\"${ra_w_file}\"; load \"${GnuplotVarFile}\"; load \"${my_dir}/random_write.gnuplot\"; quit" > ${ra_w_png}

	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, random write\\n${RandomRWMinBytesKi}Ki to ${RandomRWMaxBytesKi}Ki bytes per one write() call, ${DoDirectRandom}\\ntransfer length - access time"
EOF
	ra_w_file=${f%.*}-rw.txt
	ra_w_at_tl_png=${f%.*}-rw-at_tl.png
	gnuplot -e "log_file=\"${ra_w_file}\"; load \"${GnuplotVarFile}\"; load \"${my_dir}/random_write_at-tl.gnuplot\"; quit" > ${ra_w_at_tl_png}

	rm "${ra_file}"

	cat << EOF > ${GnuplotVarFile}
	set title "${Model} ${CapacityGB}G bytes, sequential read\\n${RWBytesMi}Mi bytes per one read() call, up to ${FileSizeGi} Gi bytes, ${DoDirectSequential}\\ntransfer speed - progress"
EOF
	sr_file=${f%.*}-sr.txt
	sr_png=${f%.*}-sr.png
	sed -n '/Tread/,$ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sr_file}
	gnuplot -e "log_file=\"${sr_file}\"; load \"${GnuplotVarFile}\"; load \"${my_dir}/sequential_read.gnuplot\"; quit" > ${sr_png}

	rm ${GnuplotVarFile}
done
