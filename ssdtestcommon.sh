#!/bin/bash
# Common defines for test SSD performance scripts.
#
#  Copyright 2012, 2015 Akinori Furuta<afuruta@m7.dion.ne.jp>.
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

TempPath=/dev/shm
if [[ ! -d ${TempPath} ]]
then
	TempPath=/tmp
fi

CharDollar='$'

function CommonHelp() {
	echo "Common defines for test SSD performance scripts."
	exit 1
}

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
	{a=$1;lk=0;d=0;\
	 if(a>0){lk=log(a)/log(1024)};\
	 m=int(lk);\
	 a=a/(exp(log(1024)*m));\
	 if (a>0) {d=int(log(a)/log(10))};\
	 f=3-d;printf("%5.*f%s\n",f,a,u[m]);\
	}'
}


function ReadCondition() {
	s_uuid=`cat /proc/sys/kernel/random/uuid`

	s_logfile="$1"
	s_header=${TempPath}/${s_uuid}-`basename ${s_logfile%.*}-hd.txt`
	sed -n '1,/Seed(-s):/ {p}' "${s_logfile}" > ${s_header}

	Model=`grep 'Model=' ${s_header} | cut -d ',' -f 1 | cut -d '=' -f 2`
	ModelSmart="`grep 'Device[[:space:]]*Model' ${s_header} \
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

	if [[ -n ${FileSize} ]]
	then
		FileSizeMi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 ) ) }"`
		FileSizeGi=`awk "BEGIN { print int ( ${FileSize} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`
	else
		FileSize=0
		FileSizeMi=0
		FileSizeGi=0
	fi

	if (( ${FileSizeMi} < 20480 ))
	then
		FileSizeShow="${FileSizeMi}Mi"
	else
		FileSizeShow="${FileSizeGi}Gi"
	fi

	if [[ -z ${LBASectors} ]]
	then
		LBASectors=`grep '^Disk.*sectors' "${s_header}" | tail -n 1 | sed -n 's/^[dD]isk.*[[:space:],:]\+\([0-9]\+\)[[:space:]]*[Ss]ectors.*/\1/p'`
	fi

	if [[ -z ${LBASectors} ]]
	then
		s_fdisk_sectors=`grep '^[0-9][0-9]*[[:space:]]*heads,[[:space:]]*[0-9][0-9]*[[:space:]]*sectors' ${s_header} \
			| sed -n 's/^.*total[[:space:]]*// p' \
			| cut -f 1 -d ' '`
		s_fdisk_sector_size=`grep '^[sS]ector[[:space:]]*[sS]ize[[:space:]].*logical' ${s_header} \
			| sed -n 's/^.*[:][[:space:]]*// p' \
			| cut -f 1 -d ' '`
		if [[ -n ${s_fdisk_sectors} && -n ${s_fdisk_sector_size} ]]
		then
			LBASectors=$(( ${s_fdisk_sectors} * ( ${s_fdisk_sector_size} / 512 ) ))
		fi
	fi

	if [[ -n ${LBASectors} ]]
	then
		CapacityGB=`awk "BEGIN { print int ( ( ${LBASectors} * 512.0 ) / ( 1000.0 * 1000.0 * 1000.0 ) ) }" `
		CapacityGBTitle="${CapacityGB}G bytes(test file size ${FileSizeShow} bytes)"
	else
		LBASectors=0
		CapacityGB=0
		CapacityGBTitle="Unknown capacity (test file size ${FileSizeShow} bytes)"
	fi

	rm ${s_header}
}

Year4=`date +%Y`
Year01Part=${Year4:0:2}
Year23Part=${Year4:2:2}
DateOffset=`date +%Z`

function Year2To4() {
	if (( $1 > ${Year23Part} ))
	then
		echo $(( ${Year01Part} - 1 ))$1
	else
		echo $(( ${Year01Part} ))$1
	fi
}

function Year2To100s() {
	if (( $1 > ${Year23Part} ))
	then
		echo $(( ${Year01Part} - 1 ))
	else
		echo $(( ${Year01Part} ))
	fi
}

function FormatDirectoryDate() {
	DirectoryDate=`echo "$1" | cut -d - -f 3`
	DirectoryDateY2=${DirectoryDate:0:2}

	echo `Year2To100s ${DirectoryDateY2}`${DirectoryDate} ${DateOffset} \
		| awk '{printf("%s/%s/%s %s:%s:%s %s", \
		substr($1,1,4),  substr($1,5,2),  substr($1,7,2), \
		substr($1,9,2), substr($1,11,2), substr($1,13,2), \
		$2 \
		);}'
}
