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

my_base=`basename "$0"`
my_dir=`dirname "$0"`

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`

# Parse Argument

function Help() {
	echo "$0 test_log_directory"
	exit 1
}

parsed_arg=( `getopt C:h $*` )
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
		(-C) # Loop Count.
			i=$(( ${i} + 1 ))
			LoopCount="${parsed_arg[${i}]}"
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

if [[ -n ${parsed_arg[${i}]} ]]
then
	LogDirectory="${parsed_arg[${i}]}"
else
	LogDirectory="."
fi

if [[ -z "${IMAGE_RESIZE}" ]]
then
	IMAGE_RESIZE="width=640 height=480"
fi

cd "${LogDirectory}"

# @note It slightly buggy, I don't care at acrossing 2099 to 2100.
YearX100Part=`date +%Y | cut -c1-2`

DirectoryDate=`pwd | cut -d - -f 3`
DateOffset=`date +%Z`

DirectoryDateFormed=`echo ${YearX100Part}${DirectoryDate} ${DateOffset} \
	| awk '{printf("%s/%s/%s %s:%s:%s %s", \
	substr($1,1,4),  substr($1,5,2),  substr($1,7,2), \
	substr($1,9,2), substr($1,11,2), substr($1,13,2), \
	$2 \
	);}'`

LogFiles=(`ls *.txt`)
f=${LogFiles[0]}
header=${TempPath}/${uuid}-`basename ${f%.*}-hd.txt`
sed -n '1,/Seed(-s):/ {p}' ${f} > ${header}

Model=`grep 'Model=' ${header} | cut -d ',' -f 1 | cut -d '=' -f 2`
FileSize=`grep 'FileSize(-f):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
BlockSize=`grep 'BlockSize(-b):' ${header} | cut -d ':' -f 2`
SequentialRWBlocks=`grep 'SequentialRWBlocks(-u):' ${header} | cut -d ':' -f 2`
BlocksMin=`grep 'BlocksMin(-i):' ${header} | cut -d ':' -f 2`
BlocksMax=`grep 'BlocksMax(-a):' ${header} | cut -d ':' -f 2`
DoDirect=`grep 'DoDirect(-d):' ${header} | cut -d ':' -f 2 | tr -d [[:space:]]`
LBASectors=`sed -n '/LBAsects/ s/.*LBAsects=\([0-9][0-9]*\)/\1/p' ${header}`

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
	CapacityGBTitle="${CapacityGB}G bytes(test file size ${FileSizeShow})"
else
	CapacityGB=0
	CapacityGBTitle="Unknown capacity (test file size ${FileSizeShow})"
fi

if [[ -n ${LoopCount} ]]
then
	LoopCountShow=${LoopCount}
else
	LoopCountShow="Unknown"
fi

echo "<HTML>"
echo "<HEAD>"
echo "<TITLE>Model: ${Model} ${CapacityGBTitle}, TestDate: ${DirectoryDateFormed}, LoopCount: ${LoopCountShow}</TITLE>"
echo "</HEAD>"
echo "<BODY>"
echo "<H1>Model: ${Model} ${CapacityGBTitle}, TestDate: ${DirectoryDateFormed}, LoopCount: ${LoopCountShow}</H1>"

TotalWrittenBytes=0
for f in ${LogFiles[*]}
do
	if [[ ${f} == *-mw-bytes.txt ]]
	then
		TotalWrittenBytes=$(( ${TotalWrittenBytes} + `cat ${f}` ))
		echo "<!-- ${f} RandomWrites=`cat ${f}` TotalWrittenBytes=${TotalWrittenBytes} -->"
	fi
done


ODirectPrev='X'
SequenceNumber=0
PlotRandomAccess="n"

for p in *.png
do
	Split=(`echo ${p%.png} | tr '-' ' '`)
	FileNo="${Split[0]}"
	ODirect="${Split[1]}"
	SeqMain="${Split[2]}"
	SeqSub="${Split[3]}"
	Access="${Split[4]}"
	PlotType="${Split[5]}"
	if [[ "${ODirect}" != "${ODirectPrev}" ]]
	then
		SequenceNumber=0
	fi
	random_plot="n"
	case "${Access}" in
		(sw) # Sequential write.
			TotalWrittenBytes=$(( ${TotalWrittenBytes} + ${FileSize} ))
			echo "<!-- ${p%-sw.png}.txt SequentialWrites=${FileSize} ${TotalWrittenBytes} -->"
			SequenceNumber=$(( ${SequenceNumber} + 1 ))
			PlotRandomAccess="n"
			case ${ODirect} in
				(N)
					echo "<HR>"
					echo "<H2>TestFlow: Try #${SequenceNumber} of Sequential write - Random read/write without O_DIRECT - Sequential read</H2>"
				;;
				(Y)
					echo "<HR>"
					echo "<H2>TestFlow: Try #${SequenceNumber} of Sequential write - Random read/write with O_DIRECT - Sequential</H2>"
				;;
			esac
			echo "<H3>Sequential write</H3>"
			echo "<P>Plot: Sequential write, transfer speed - progress(percent of test file size).<BR>"
			echo -n "<A href=\"${p}\">"
			echo -n "<IMG src=\"${p}\" ${IMAGE_RESIZE}>"
			echo -n "</A><BR>"
			echo "</P>"
		;;
		(sr) # Sequential read.
			echo "<H3>Sequential read</H3>"
			echo "<P>Plot: Sequential read, transfer speed - progress(percent of test file size).<BR>"
			echo -n "<A href=\"${p}\">"
			echo -n "<IMG src=\"${p}\" ${IMAGE_RESIZE}>"
			echo -n "</A><BR>"
			echo "</P>"
		;;
	esac
	case "${PlotType}" in
		(ts_at) # Transfer speed - access time
			random_plot="y"
		;;
		(ts_tl) # Transfer speed - transfer length
			random_plot="y"
		;;
		(tl_at) # Transfer length - access time
			random_plot="y"
		;;
	esac
	if [[ "${PlotRandomAccess}" == "n" ]]
	then
		if [[ "${random_plot}" == "y" ]]
		then
			echo "<H3>Random read/write</H3>"
			echo "<TABLE border=1>"
			echo "<TR>"
			echo "<TD><P>Random access, read transfer speed - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_at.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "<TD><P>Random access, write transfer speed - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "</TR>"
			echo "<TR>"
			echo "<TD><P>Random access, read transfer speed - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_tl.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "<TD><P>Random access, write transfer speed - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_tl.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "</TR>"
			echo "<TR>"
			echo "<TD><P>Random access, read transfer length - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-tl_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-tl_at.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "<TD><P>Random access, write transfer length - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-tl_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-tl_at.png\" ${IMAGE_RESIZE}>"
			echo -n "</A></P></TD>"
			echo "</TR>"
			echo "</TABLE>"
			PlotRandomAccess="y"
		fi
	fi
	ODirectPrev="${ODirect}"
done
echo "<HR>"

TotalWrittenBytesMi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 ) ) }"`
TotalWrittenBytesGi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`
TotalWrittenBytesTi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 * 1024.0 * 1024.0 ) ) }"`


if (( ${TotalWrittenBytes} < 17179869184 ))
then
	TotalWrittenBytesShow="${TotalWrittenBytesMi}Mi"
else
	if (( ${TotalWrittenBytes} < 17592186044416 ))
	then
		TotalWrittenBytesShow="${TotalWrittenBytesGi}Gi"
	else
		TotalWrittenBytesShow="${TotalWrittenBytesTi}Ti"
	fi
fi


echo "<P>Total Written Bytes: ${TotalWrittenBytes} (${TotalWrittenBytesShow}) bytes</P>"
echo "</BODY>"
echo "</HTML>"

