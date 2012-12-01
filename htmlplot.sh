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

function Help() {
	#     0         1         2         3         4         5         6         7
	#     01234567890123456789012345678901234567890123456789012345678901234567890123456789
	echo "$0 [directory]"
	echo "directory: directory to create html page. This directory has test"
	echo "           logs and graph plots created by plotlohseq.sh and plotlogmix.sh."
	exit 1
}

my_base=`basename "$0"`
my_dir=`dirname "$0"`
my_dir=`readlink -f "${my_dir}"`

TempPath=/dev/shm
uuid=`cat /proc/sys/kernel/random/uuid`

# Parse Argument

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
			RoundCount="${parsed_arg[${i}]}"
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

function ExtractSmartctl() {
	(	echo "<HTML>"
		echo "<HEAD>"
		echo "<TITLE>$3</TITLE>"
		echo "</HEAD>"
		echo "<BODY>"
		echo "<PRE>"
	) > $2
	sed -n '/smartctl:/,/df:/ p' $1 | grep -v -e '^smartctl:$' -e '^df:$' >> $2
	(	echo "</PRE>"
		echo "</BODY>"
		echo "</HTML>"
	) >> $2
}

Year4=`date +%Y`
Year01Part=${Year4:0:2}
Year23Part=${Year4:2:2}
DateOffset=`date +%Z`

LogDirectoryLast=`pwd`
LogDirectoryLast=`basename "${LogDirectoryLast}"`

DirectoryDate=`echo "${LogDirectoryLast}" | cut -d - -f 3`
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

LogFiles=(`ls *.txt`)

f=${LogFiles[0]}

source ${my_dir}/readcondition.sh "${f}"

if [[ -n ${RoundCount} ]]
then
	RoundCountShow=${RoundCount}
else
	RoundCountShow="Unknown"
fi

echo "<HTML>"
echo "<HEAD>"
echo "<TITLE>Model: ${Model} ${CapacityGBTitle}, TestDate: ${DirectoryDateFormed}, Round: ${RoundCountShow}</TITLE>"
echo "</HEAD>"
echo "<BODY>"
echo "<H1 id=\"TestRecord\">Model: ${Model} ${CapacityGBTitle}, TestDate: ${DirectoryDateFormed}, Round: ${RoundCountShow}</H1>"

TotalReadBytes=0
TotalWrittenBytes=0
for f in *-bytes.tmp
do
	if [[ ${f} == *-mw-bytes.tmp ]]
	then
		TotalWrittenBytes=$(( ${TotalWrittenBytes} + `cat ${f}` ))
		# echo "<!-- ${f} RandomWrites=`cat ${f}` TotalWrittenBytes=${TotalWrittenBytes} -->"
	fi
	if [[ ${f} == *-mr-bytes.tmp ]]
	then
		TotalReadBytes=$(( ${TotalReadBytes} + `cat ${f}` ))
		# echo "<!-- ${f} RandomReads=`cat ${f}` TotalReadBytes=${TotalReadBytes} -->"
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
			SequenceNumber=$(( ${SequenceNumber} + 1 ))
			PlotRandomAccess="n"
			case ${ODirect} in
				(N)
					echo "<HR>"
					H2Title="TestFlow: Try #${SequenceNumber} of Sequential write - Random read/write without O_DIRECT - Sequential read"
					echo "<H2 id=\"TestFlowWithoutODIRECT_${ODirect}_${SequenceNumber}\">${H2Title}</H2>"
				;;
				(Y)
					echo "<HR>"
					H2Title="TestFlow: Try #${SequenceNumber} of Sequential write - Random read/write with O_DIRECT - Sequential read"
					echo "<H2 id=\"TestFlowWithODIRECT_${ODirect}_${SequenceNumber}\">${H2Title}</H2>"
				;;
			esac
			ParagraphIdSw="SequentialWritePlot_${ODirect}_${SequenceNumber}"
			echo "<H3 id=\"SequentialWrite_${ODirect}_${SequenceNumber}\">Sequential write</H3>"
			# echo "<!-- ${p%-sw.png}.txt SequentialWrites=${FileSize} TotalWrittenBytes=${TotalWrittenBytes} -->"

			TextLogFile=${p%-sw.png}.txt
			SmartFile=${p%-sw.png}-smart.html
			ExtractSmartctl ${TextLogFile} ${SmartFile} \
				"S.M.A.R.T before sequential write - ${H2Title}"
			echo "<P id=\"${ParagraphIdSw}\">Plot: Sequential write, transfer speed - progress(percent of test file size).<BR>"
			echo "<A href=\"${SmartFile}\">S.M.A.R.T before sequential write</A><BR>"
			echo -n "<A href=\"${p}\">"
			echo -n "<IMG src=\"${p}\" ${IMAGE_RESIZE}>"
			echo -n "</A><BR>"
			echo "</P><!-- id=\"${ParagraphIdSw}\" -->"
		;;
		(sr) # Sequential read.
			TotalReadBytes=$(( ${TotalReadBytes} + ${FileSize} ))
			ParagraphIdSr="SequentialReadPlot_${ODirect}_${SequenceNumber}"
			echo "<H3 id=\"SequentialRead_${ODirect}_${SequenceNumber}\">Sequential read</H3>"
			# echo "<!-- ${p%-sr.png}.txt SequentialReads=${FileSize} TotalReadBytes=${TotalReadBytes} -->"

			TextLogFile=${p%-sr.png}.txt
			SmartFile=${p%-sr.png}-smart.html
			ExtractSmartctl ${TextLogFile} ${SmartFile} \
				"S.M.A.R.T before sequential write - ${H2Title}"

			echo "<P id=\"${ParagraphIdSr}\">Plot: Sequential read, transfer speed - progress(percent of test file size).<BR>"
			echo "<A href=\"${SmartFile}\">S.M.A.R.T before sequential read</A><BR>"
			echo -n "<A href=\"${p}\">"
			echo -n "<IMG src=\"${p}\" ${IMAGE_RESIZE}>"
			echo -n "</A><BR>"
			echo "</P><!-- id=\"${ParagraphIdSr}\" -->"
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
			echo "<H3 id=\"RandomReadWrite_${ODirect}_${SequenceNumber}\">Random read/write</H3>"
			echo "<TABLE id=\"PlotTable_${ODirect}_${SequenceNumber}\" border=1>"
			echo "<TR>"
			echo "<TD>"
			ParagraphIdMrTsAt="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_tsat"
			echo "<P id=\"${ParagraphIdMrTsAt}\">"
			echo "Random access, read transfer speed - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_at.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMrTsAt}\" -->"
			echo "</TD>"
			echo "<TD>"
			ParagraphIdMwTsAt="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_tsat"
			echo "<P id=\"${ParagraphIdMwTsAt}\">"
			echo "Random access, write transfer speed - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMwTsAt}\" -->"
			echo "</TD>"
			echo "</TR>"
			echo "<TR>"
			echo "<TD>"
			ParagraphIdMrTsTl="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_tstl"
			echo "<P id=\"${ParagraphIdMrTsTl}\">"
			echo "Random access, read transfer speed - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-ts_tl.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMrTsTl}\" -->"
			echo "</TD>"
			echo "<TD>"
			ParagraphIdMwTsTl="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_tstl"
			echo "<P id=\"${ParagraphIdMwTsTl}\">"
			echo "Random access, write transfer speed - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_tl.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMwTsTl}\" -->"
			echo "</TD>"
			echo "</TR>"
			echo "<TR>"
			echo "<TD>"
			ParagraphIdMrTlAt="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_tlat"
			echo "<P id=\"${ParagraphIdMrTlAt}\">"
			echo "Random access, read transfer length - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-tl_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-tl_at.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMrTlAt}\" -->"
			echo "</TD>"
			echo "<TD>"
			ParagraphIdMwTlAt="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_tlat"
			echo "<P id=\"${ParagraphIdMwTlAt}\">"
			echo "Random access, write transfer length - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-tl_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-tl_at.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMwTlAt}\" -->"
			echo "</TD>"
			echo "</TR>"
			echo "</TABLE>"
			PlotRandomAccess="y"
		fi
	fi
	ODirectPrev="${ODirect}"
done
echo "<HR>"
echo "<H2 id=\"Summary\">Summary</H2>"
echo "<P id=\"SummaryStatistics\">"

Size16Gi=17179869184
Size16Ti=17592186044416

function BytesToShowBytes() {
	if (( $1 < ${Size16Gi} ))
	then
		# Under 16GiBytes, show in Mi bytes.
		TotalWrittenBytesMi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 ) ) }"`
		echo "${TotalWrittenBytesMi}Mi"
	else
		# Equal to or more than 16GiBytes, show in Mi bytes.
		if (( $1 < ${Size16Ti} ))
		then
			# Under 16TiBytes, show in Gi bytes.
			TotalWrittenBytesGi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 * 1024.0 ) ) }"`
			echo "${TotalWrittenBytesGi}Gi"
		else
			# Equal to or more than 16TiBytes, show in Gi bytes.
			TotalWrittenBytesTi=`awk "BEGIN { print int ( ${TotalWrittenBytes} / ( 1024.0 * 1024.0 * 1024.0 * 1024.0 ) ) }"`
			echo "${TotalWrittenBytesTi}Ti"
		fi
	fi
}

TotalWrittenBytesShow=`BytesToShowBytes ${TotalWrittenBytes}`
echo "Total Written Bytes: ${TotalWrittenBytes} (${TotalWrittenBytesShow}) bytes<BR>"
echo ${TotalWrittenBytes} > total_written_bytes.tmp

TotalReadBytesShow=`BytesToShowBytes ${TotalReadBytes}`
echo "Total Read Bytes: ${TotalReadBytes} (${TotalReadBytesShow}) bytes<BR>"
echo ${TotalReadBytes} > total_read_bytes.tmp

echo "</P><!-- id=\"SummaryStatistics\" -->"

echo "<HR>"

pass_count_all=0
fail_count_all=0

echo "<H2 id=\"RawDataLink\">Raw data link</H2>"
echo "<P id=\"RawDataLinkTxt\">"
echo "<TABLE id=\"RawDataLinkTxtTable\">"
echo "<TR><TH>File<TH>PASS<TH>FAIL</TR>"
for f in *.txt
do
	pass_count=`grep '[.]bin' ${f} | grep 'PASS' | wc -l`
	fail_count=`grep '[.]bin' ${f} | grep 'FAIL' | wc -l`
	echo "<TR><TD align="left"><A href=\"${f}\">${f}</A><TD align="center">${pass_count}<TD align="center">${fail_count}</TR>"
	pass_count_all=$(( ${pass_count_all} + ${pass_count} ))
	fail_count_all=$(( ${fail_count_all} + ${fail_count} ))
done
echo "</TABLE><!-- id=\"RawDataLinkTxtTable\" -->"
echo ${pass_count_all} > pass_count_all.tmp
echo ${fail_count_all} > fail_count_all.tmp
echo "</P><!-- id=\"RawDataLinkTxt\" -->"
echo "</BODY>"
echo "</HTML>"
