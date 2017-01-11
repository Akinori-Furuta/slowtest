#!/bin/bash
# Bind plot graphs to html page.
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

source "${my_dir}/ssdtestcommon.sh"

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
	LogLabel=`basename "${LogDirectory}" | cut -f 2 -d '-'`
else
	LogDirectory="."
	cur_dir="`pwd`"
	LogLabel=`basename "${cur_dir}" | cut -f 2 -d '-'`
fi

if [[ -z "${IMAGE_RESIZE}" ]]
then
	IMAGE_RESIZE="width=640 height=480"
fi

if [[ -z "${ACCESS_TIME_SCALE_OVER}" ]]
then
	ACCESS_TIME_SCALE_OVER="1.0e+2"
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

LogDirectoryLast=`pwd`
LogDirectoryLast=`basename "${LogDirectoryLast}"`

DirectoryDateFormed=`FormatDirectoryDate "${LogDirectoryLast}"`

LogFiles=(`ls *.txt`)

f=${LogFiles[0]}

ReadCondition "${f}"

if [[ -z "${Model}" ]]
then
	Model="${LogLabel}"
fi

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
	if [[ ( ${f} == *-mw-bytes.tmp ) || ( ${f} == *-sw-bytes.tmp ) ]]
	then
		w_bytes=`cat ${f}`
		if [[ -n ${w_bytes} ]]
		then
			TotalWrittenBytes=$(( ${TotalWrittenBytes} + ${w_bytes} ))
			# echo "<!-- ${f}=${w_bytes} TotalWrittenBytes=${TotalWrittenBytes} -->"
		fi
	fi
	if [[ ( ${f} == *-mr-bytes.tmp ) || ( ${f} == *-sr-bytes.tmp ) ]]
	then
		r_bytes=`cat ${f}`
		if [[ -n ${r_bytes} ]]
		then
			TotalReadBytes=$(( ${TotalReadBytes} + ${r_bytes} ))
			# echo "<!-- ${f}=${r_bytes} TotalReadBytes=${TotalReadBytes} -->"
		fi
	fi
done


ODirectPrev='X'
SequenceNumber=0
PlotRandomAccess="n"

png_list=()

function ClearRandomAccessPngPrev() {
	png_prev_mw_at_tl=""
	png_prev_mw_ts_at=""
	png_prev_mw_ts_tl=""
	png_prev_mr_at_tl=""
	png_prev_mr_ts_at=""
	png_prev_mr_ts_tl=""
}


function AddListRandomAccessPng() {
	if [[ -n ${png_prev_mw_at_tl} ]]
	then
		png_list[${i}]="${png_prev_mw_at_tl}"
		i=$(( ${i} + 1 ))
	fi
	if [[ -n ${png_prev_mw_ts_at} ]]
	then
		png_list[${i}]="${png_prev_mw_ts_at}"
		i=$(( ${i} + 1 ))
	fi
	if [[ -n ${png_prev_mw_ts_tl} ]]
	then
		png_list[${i}]="${png_prev_mw_ts_tl}"
		i=$(( ${i} + 1 ))
	fi
	if [[ -n ${png_prev_mr_at_tl} ]]
	then
		png_list[${i}]="${png_prev_mr_at_tl}"
		i=$(( ${i} + 1 ))
	fi
	if [[ -n ${png_prev_mr_ts_at} ]]
	then
		png_list[${i}]="${png_prev_mr_ts_at}"
		i=$(( ${i} + 1 ))
	fi
	if [[ -n ${png_prev_mr_ts_tl} ]]
	then
		png_list[${i}]="${png_prev_mr_ts_tl}"
		i=$(( ${i} + 1 ))
	fi
}

ClearRandomAccessPngPrev
i=0
for p in *.png
do
	Split=(`echo ${p%.png} | tr '-' ' '`)
	FileNo="${Split[0]}"
	ODirect="${Split[1]}"
	SeqMain="${Split[2]}"
	SeqSub="${Split[3]}"
	Access="${Split[4]}"
	PlotType="${Split[5]}"
	case "${Access}" in
		(sw) # Sequential write.
			AddListRandomAccessPng
			ClearRandomAccessPngPrev
			png_list[${i}]="${p}"
			i=$(( ${i} + 1 ))

		;;
		(sr) # Sequential read.
			AddListRandomAccessPng
			ClearRandomAccessPngPrev
			png_list[${i}]="${p}"
			i=$(( ${i} + 1 ))
		;;
		(mw) # Random access write part.
			case "${PlotType}" in
				(at_tl) # Transfer length - access time
					png_prev_mw_at_tl="${p}"
				;;
				(ts_at) # Transfer speed - access time
					png_prev_mw_ts_at="${p}"
				;;
				(ts_tl) # Transfer speed - transfer length
					png_prev_mw_ts_tl="${p}"
				;;
			esac
		;;
		(mr) # Random access read part.
			case "${PlotType}" in
				(at_tl) # Transfer length - access time
					png_prev_mr_at_tl="${p}"
				;;
				(ts_at) # Transfer speed - access time
					png_prev_mr_ts_at="${p}"
				;;
				(ts_tl) # Transfer speed - transfer length
					png_prev_mr_ts_tl="${p}"
				;;
			esac
		;;
	esac
done
AddListRandomAccessPng

for p in ${png_list[*]}
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
			ParagraphIdSr="SequentialReadPlot_${ODirect}_${SequenceNumber}"
			echo "<H3 id=\"SequentialRead_${ODirect}_${SequenceNumber}\">Sequential read</H3>"

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
		(at_tl) # Access time - Transfer length
			random_plot="y"
		;;
		(ts_at) # Transfer speed - Access time
			random_plot="y"
		;;
		(ts_tl) # Transfer speed - Transfer length
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
			ra_r_over100_counts=""
			ra_r_over100_tmp=${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-over100.tmp
			if [[ -f "${ra_r_over100_tmp}" ]]
			then
				ParagraphIdMrTsAtSo="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_tsat_so"
				echo "<P id=\"${ParagraphIdMrTsAtSo}\">"
				ra_r_over100_counts=`cat "${ra_r_over100_tmp}"`
				echo "The number of \"access time &gt; ${ACCESS_TIME_SCALE_OVER}\" record(s): ${ra_r_over100_counts}"
				echo "</P><!-- id=\"${ParagraphIdMrTsAtSo}\" -->"
			fi
			echo "</TD>"
			echo "<TD>"
			ParagraphIdMwTsAt="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_tsat"
			echo "<P id=\"${ParagraphIdMwTsAt}\">"
			echo "Random access, write transfer speed - access time<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-ts_at.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMwTsAt}\" -->"
			ra_w_over100_counts=""
			ra_w_over100_tmp=${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-over100.tmp
			if [[ -f "${ra_w_over100_tmp}" ]]
			then
				ParagraphIdMwTsAtSo="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_tsat_so"
				echo "<P id=\"${ParagraphIdMwTsAtSo}\">"
				ra_w_over100_counts=`cat "${ra_w_over100_tmp}"`
				echo "The number of \"access time &gt; ${ACCESS_TIME_SCALE_OVER}\" record(s): ${ra_w_over100_counts}"
				echo "</P><!-- id=\"${ParagraphIdMwTsAtSo}\" -->"
			fi
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
			ParagraphIdMrAtTl="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_attl"
			echo "<P id=\"${ParagraphIdMrAtTl}\">"
			echo "Random access, read access time - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-at_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mr-at_tl.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMrAtTl}\" -->"
			if [[ -n "${ra_r_over100_counts}" ]]
			then
				ParagraphIdMrAtTlSo="RandomReadWrite_${ODirect}_${SequenceNumber}_mr_attl_so"
				echo "<P id=\"${ParagraphIdMrAtTlSo}\">"
				echo "The number of \"access time &gt; ${ACCESS_TIME_SCALE_OVER}\" record(s): ${ra_r_over100_counts}"
				echo "</P><!-- id=\"${ParagraphIdMrAtTlSo}\" -->"
			fi
			echo "</TD>"
			echo "<TD>"
			ParagraphIdMwAtTl="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_attl"
			echo "<P id=\"${ParagraphIdMwAtTl}\">"
			echo "Random access, write access time - transfer length<BR>"
			echo -n "<A href=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-at_tl.png\">"
			echo -n "<IMG src=\"${FileNo}-${ODirect}-${SeqMain}-${SeqSub}-mw-at_tl.png\" ${IMAGE_RESIZE}>"
			echo "</A>"
			echo "</P><!-- id=\"${ParagraphIdMwAtTl}\" -->"
			if [[ -n "${ra_w_over100_counts}" ]]
			then
				ParagraphIdMwAtTlSo="RandomReadWrite_${ODirect}_${SequenceNumber}_mw_attl_so"
				echo "<P id=\"${ParagraphIdMwAtTlSo}\">"
				echo "The number of \"access time &gt; ${ACCESS_TIME_SCALE_OVER}\" record(s): ${ra_w_over100_counts}"
				echo "</P><!-- id=\"${ParagraphIdMwAtTlSo}\" -->"
			fi
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

TotalWrittenBytesShow=`BytesToShowBytes ${TotalWrittenBytes}`
echo "Total Written Bytes: ${TotalWrittenBytesShow} (${TotalWrittenBytes}) bytes<BR>"
echo ${TotalWrittenBytes} > total_written_bytes.tmp

TotalReadBytesShow=`BytesToShowBytes ${TotalReadBytes}`
echo "Total Read Bytes: ${TotalReadBytesShow} (${TotalReadBytes}) bytes<BR>"
echo ${TotalReadBytes} > total_read_bytes.tmp

echo "</P><!-- id=\"SummaryStatistics\" -->"

echo "<HR>"

pass_count_all=0
fail_count_all=0

echo "<H2 id=\"RawDataLink\">Raw data link</H2>"
echo "<TABLE border=1 id=\"RawDataLinkTxtTable\">"
echo "<TR><TH>File<TH>PASS<TH>FAIL</TR>"
for f in *.txt
do
	pass_count=`grep '[.]bin' ${f} | grep 'PASS' | wc -l`
	fail_count=`grep '[.]bin' ${f} | grep 'FAIL' | wc -l`
	echo -n "<TR>"
	echo -n "<TD align="left"><A href=\"${f}\">${f}</A>"
	echo -n "<TD align="right">${pass_count}<TD align="right">${fail_count}</TR>"
	pass_count_all=$(( ${pass_count_all} + ${pass_count} ))
	fail_count_all=$(( ${fail_count_all} + ${fail_count} ))
done
echo "</TABLE><!-- id=\"RawDataLinkTxtTable\" -->"
echo ${pass_count_all} > pass_count_all.tmp
echo ${fail_count_all} > fail_count_all.tmp
echo "</BODY>"
echo "</HTML>"
