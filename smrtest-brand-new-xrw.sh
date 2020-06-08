#!/bin/bash
# Test SMR HDD performance script.
#  "Sequential Write", "Random Read and Write", and "Sequential Read" on RAW device.
#
#  Copyright 2012, 2017, 2020 Akinori Furuta<afuruta@m7.dion.ne.jp>.
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

Result=0

# This test context.
uuid=`cat /proc/sys/kernel/random/uuid`

function Help() {
	echo "Test SSD performance."
	echo "$0 [-L OptionalLabel] [-h] test_file_or_directory"
	echo "-L OptionalLabel : Jam string into log directory path."
	echo "-h : Show this help."
	echo "test_file_or_directory: "
	echo "  Test file name to read and write, or test directory to create"
	echo "  temporal test file to read and write."
	echo "This script create logs to ./log-\${ModelName}\${ModelNameLabel}-\${TestDateTime}-\${TestFileSize}
"
	exit 1
}

MyBase="`dirname $0`"

my_dir=`dirname "$0"`
my_dir=`readlink -f "${my_dir}"`

source "${my_dir}/ssdtestcommon.sh"

if [[ -z ${TestBin} ]]
then
	TestBin=ssdstress
fi

if [[ -z ${MAX_SECTORS_KB_UNIT} ]]
then
	# kernel parameter max IO KiBytes per one request to block device driver.
	MAX_SECTORS_KB_UNIT=2048
fi

if [[ -z ${SEQUENTIAL_READ_AHEAD_KB} ]]
then
	SEQUENTIAL_READ_AHEAD_KB=128
fi

if [[ -z ${RANDOM_READ_AHEAD_KB} ]]
then
	RANDOM_READ_AHEAD_KB=0
fi


if [[ -z ${TEST_USAGE_RATIO} ]]
then
	# Test file size ratio at free space in volume.
	TEST_USAGE_RATIO=0.9
fi

if [[ -z ${LOOP_MAX} ]]
then
	# Test loops per "at with direct" and "at without direct".
	LOOP_MAX=1
fi

if [[ -z ${SEQUENTIAL_DIRECT} ]]
then
	SEQUENTIAL_DIRECT=n
fi

if [[ -z ${O_DIRECT_ORDER} ]]
then
	O_DIRECT_ORDER="Y N"
fi

if [[ -z ${SEED} ]]
then
	# random seed.
	SEED=1000
fi

if [[ -z ${SEED_SPAN_DIRECT} ]]
then
	# random seed span O_DIRECT loop.
	SEED_SPAN_DIRECT=0
fi

if [[ -z ${BLOCK_SIZE} ]]
then
	BLOCK_SIZE=4096
fi

if [[ -z ${RANDOM_BLOCKS_MIN} ]]
then
	# 1 blocks, 4Kibyte.
	RANDOM_BLOCKS_MIN=$(( 1 ))
fi

if [[ -z ${RANDOM_BLOCKS_MAX} ]]
then
	# 128Ki blocks, 512 Mibyte.
	RANDOM_BLOCKS_MAX=$(( 128 * 1024 ))
fi

if [[ -z ${RANDOM_REPEATS} ]]
then
	RANDOM_REPEATS=$(( 1024 * 24 ))
fi

if [[ -z ${SEQUENTIAL_BLOCKS} ]]
then
	SEQUENTIAL_BLOCKS=$(( ${RANDOM_BLOCKS_MAX} / 2 ))
fi

if ( awk "BEGIN { if ( ( 1.0 * ${SEQUENTIAL_BLOCKS} * ${BLOCK_SIZE} ) >= ( 65536.0 * 65536.0 ) ) {exit 0;} else {exit 1;}}" )
then
	echo "$0: Notice: It may caught General Protection Fault when SEQUENTIAL_BLOCKS * BLOCK_SIZE is bigger than 4Gi. SEQUENTIAL_BLOCKS=${SEQUENTIAL_BLOCKS}, BLOCK_SIZE=${BLOCK_SIZE}"
	SEQUENTIAL_BLOCKS=`awk "BEGIN { print ( 256.0 * 1024 * 1024 ) / ${BLOCK_SIZE} }"`
	echo "$0: Notice: Truncate SEQUENTIAL_BLOCKS * BLOCK_SIZE under 256Mi. SEQUENTIAL_BLOCKS=${SEQUENTIAL_BLOCKS}, BLOCK_SIZE=${BLOCK_SIZE}"
fi

# Get uid.
# Strongly recommended root.

Uid=`id | sed 's/uid=\([0-9][0-9]*\).*/\1/'`

# Clean work file
#
#
MountList=${TempPath}/${uuid}_mount.txt
TestBinResult=${TempPath}/${uuid}_exit.txt

function remove_work_file() {
	if [[ -n "${MountList}" ]]
	then
		[ -f "${MountList}" ] && rm "${MountList}"
	fi
	if [[ -n "${TestBinResult}" ]]
	then
		[ -f "${TestBinResult}" ] && rm "${TestBinResult}"
	fi
}

# Clean test file.
# no arguments.
# global TestFile
function remove_test_file() {
	if [[ -f ${TestFile} ]]
	then
		echo "${TestFile}: Info: `date '+%y-%m-%d %H:%M:%S %s'`: Remove test file."
		[ -f ${TestFile} ] && rm ${TestFile}
	fi
}

# Recover max_sectors_kb, read_ahead_kb kernel parameter.
# No arguments.
# global SavedMaxSectorsKb, MaxSectorsKb, ReadAheadKb, SavedReadAheadKb, Uid
function recover_queue_config() {
	if (( ${Uid} == 0 ))
	then
		if [[ -n ${SavedMaxSectorsKb} ]]
		then
			echo "${MaxSectorsKb}: Info: Restore max_sectors_kb. SavedMaxSectorsKb=${SavedMaxSectorsKb}"
			echo ${SavedMaxSectorsKb} > ${MaxSectorsKb}
		fi
		if [[ -n ${SavedReadAheadKb} ]]
		then
			echo "${ReadAheadKb}: Info: Restore read_ahead_kb. ReadAheadKb=${SavedReadAheadKb}"
			echo ${SavedReadAheadKb} > ${ReadAheadKb}
		fi
	else
		echo "${MaxSectorsKb}: Notice: Skip restore max_sectors_kb, not root. SavedMaxSectorsKb=${SavedMaxSectorsKb}"
		echo "${ReadAheadKb}: Notice: Skip restore read_ahead_kb, not root. ReadAheadKb=${SavedReadAheadKb}"
	fi
}

# Set read_ahead_kb.
# @param $1 read ahead kibytes.
function set_read_ahead_kb() {
	if (( ${Uid} == 0 ))
	then
		if [[ -n $1 ]]
		then
			echo "${ReadAheadKb}: Info: Set read_ahead_kb. argv[1]=$1"
			echo $1 > ${ReadAheadKb}
		fi
	else
		echo "${ReadAheadKb}: Notice: Skip set read_ahead_kb, not root. argv[1]=$1"
	fi
}


HungTo=/proc/sys/kernel/hung_task_timeout_secs

# Recover hung_task_timeout_secs
# No arguments.
# global SavedMaxSectorsKb, MaxSectorsKb, Uid
function recover_hung_task_to() {
	if [[ -n ${SavedHungTaskTo} ]]
	then
		if (( ${Uid} == 0 ))
		then
			echo "${HungTo}: Info: Restore hung_task_timeout_secs. SavedHungTaskTo=${SavedHungTaskTo}"
			echo ${SavedHungTaskTo} > ${HungTo}
		else
			echo "${HungTo}: Notice: Skip hung_task_timeout_secs, not root. SavedHungTaskTo=${SavedHungTaskTo}"
		fi
	fi
}

# Signal handler.
function signaled() {
	echo "$0: Interrupted."
	remove_test_file
	recover_queue_config
	recover_hung_task_to
	remove_work_file
	exit 2
}

# Trap signals.
trap signaled HUP INT

# Parse Argument

parsed_arg=( `getopt L:h $*` )
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
		(-L)
			i=$(( ${i} + 1 ))
			OptionalLabel="${parsed_arg[${i}]}"
		;;
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

if [[ -z ${parsed_arg[${i}]} ]]
then
	Help
	exit 1
fi

if [[ ! -x ${MyBase}/${TestBin} ]]
then
	echo "${MyBase}/${TestBin}: Can not find or execute. To build this file, invoke make command."
	exit 2
fi

TIME_PROFILE=/usr/bin/time

if [[ ! -x ${TIME_PROFILE} ]]
then
	# Not found time command.
	TIME_PROFILE=/bin/time
fi

if [[ ! -x ${TIME_PROFILE} ]]
then
	# Not found time command.
	# Try shell build in.
	TIME_PROFILE=time
fi

TestFile="${parsed_arg[${i}]}"

# File or directory.


if [[ -d ${TestFile} ]]
then
	echo "${TestFile}: Notice: It may directory."
	TestFile=${TestFile}/${uuid}.bin
	if ( ! touch ${TestFile} )
	then
		echo "${TestFile}: Error: Can not access."
		exit 1
	fi
fi

if ( ! touch ${TestFile} )
then
	echo "${TestFile}: Error: Can not access."
	exit 1
fi

# Get canonical path name.
TestFileCanon=`readlink -f ${TestFile}`

# Check canonical path name.
if [[ -z ${TestFileCanon} ]]
then
	echo "${TestFile}: Error: Can not resolv canonical path name."
	exit 1
fi

echo "${TestFile}: Info: Canonical path. TestFileCanon=${TestFileCanon}"


# resolv volume name (mounted block device or partiton).
# Note: This program can resolv volume not using volume group.


cat /proc/mounts | grep '^/' | sort -r -k 2 > ${MountList}

if [ -b "${TestFileCanon}" ]
then
	# Raw block device
	Volume="${TestFileCanon}"
	FileSystem="raw"
else
	# File on file system.
	i=1
	for mount_point in `awk '{print $2}' ${MountList}`
	do
		if ( echo ${TestFileCanon} | grep -q "^${mount_point}" )
		then
			VolumeFs=(`awk "NR==${i} {printf(\"%s %s\", ${CharDollar}1, ${CharDollar}3);}" "${MountList}"`)
			break
		fi
		i=$(( ${i} + 1 ))
	done

	Volume=${VolumeFs[0]}
	FileSystem=${VolumeFs[1]}

	if ( ! ( echo ${Volume} | grep -q "^/dev/" ) )
	then
		mount | sort -r -k 3 > ${MountList}
		i=1
		for mount_point in `awk '{print $3}' ${MountList}`
		do
			if ( echo ${TestFileCanon} | grep -q "^${mount_point}" )
			then
				VolumeFs=(`awk "NR==${i} {printf(\"%s %s\", ${CharDollar}1, ${CharDollar}5);}" "${MountList}"`)
				break
			fi
			i=$(( ${i} + 1 ))
		done
		Volume=${VolumeFs[0]}
		FileSystem=${VolumeFs[1]}
	fi
fi

# Limit max file size to 16TiB (ext4 max file size)
FileSizeFSMaxKb=$(( 65536 * 65536 * 4 - 1 ))

case ${FileSystem} in
	(vfat|fat)
		FileSizeFSMaxKb=$(( 4096 * 1024 - 1 ))
	;;
esac


if [[ -n "${MountList}" ]]
then
	rm "${MountList}"
fi

if [[ -z ${Volume} ]]
then
	echo "${TestFile}: Notice: Can not resolv volume."
else
	echo "${TestFile}: Info: Resolved volume device. Volume=${Volume}"
fi


if [[ -z ${STORAGE_DEVICE_NAME} ]]
then
	if ( echo ${Volume} | grep -q "^/dev/" )
	then
		STORAGE_DEVICE_NAME=`echo ${Volume##*/} | sed 's/[0-9]*$//'`
		STORAGE_DEVICE=/dev/${STORAGE_DEVICE_NAME}
		if [[ -z ${FILE_SIZE} ]]
		then
			SysFsBlocks=`cat /sys/block/${STORAGE_DEVICE_NAME}/size`
			FILE_SIZE=$(( ${SysFsBlocks} * 512 ))
		fi
	else
		echo "${FileName}: Error: Can not handle this volume type. Volume=${Volume}"
		exit 2
	fi
else
	STORAGE_DEVICE=/dev/${STORAGE_DEVICE_NAME}
fi

# Fix hung task timeout

if [[ -e ${HungTo} ]]
then
	SavedHungTaskTo=`cat ${HungTo}`
else
	SavedHungTaskTo=""
fi
if (( ${Uid} == 0 ))
then
	if [[ -e ${HungTo} ]]
	then
		echo 0 > ${HungTo}
	fi
fi

# Trim max_sectors_kb, read_ahead_kb

MaxHwSectorsKb=/sys/block/${STORAGE_DEVICE_NAME}/queue/max_hw_sectors_kb
MaxSectorsKb=/sys/block/${STORAGE_DEVICE_NAME}/queue/max_sectors_kb
ReadAheadKb=/sys/block/${STORAGE_DEVICE_NAME}/queue/read_ahead_kb

ReadMaxHwSectorsKb=`cat ${MaxHwSectorsKb}`
SavedMaxSectorsKb=`cat ${MaxSectorsKb}`
SavedReadAheadKb=`cat ${ReadAheadKb}`

if (( ${Uid} == 0 ))
then
	NewMaxSectorsKb=$(( ${ReadMaxHwSectorsKb} - ( ${ReadMaxHwSectorsKb} % ${MAX_SECTORS_KB_UNIT} ) ))
	if (( ${NewMaxSectorsKb} <= 0 ))
	then
		NewMaxSectorsKb=${ReadMaxHwSectorsKb}
	fi
	if (( ${NewMaxSectorsKb} >= ${SavedMaxSectorsKb} ))
	then
		echo "${MaxSectorsKb}: Info: Update max_sectors_kb. NewMaxSectorsKb=${NewMaxSectorsKb}"
		echo ${NewMaxSectorsKb} > ${MaxSectorsKb}
	else
		echo "${MaxSectorsKb}: Info: Sekip update max_sectors_kb, already modified large enough."
	fi
	echo 0 > ${ReadAheadKb}
else
	echo "${MaxSectorsKb}: Notice: Skip update max_sectors_kb, not root."
	echo "${ReadAheadKb}: Notice: Skip update read_ahead_kb, not root."
fi

# Estimate test file size.

VolumeFreeSpace=-1
if [[ ! -b "${TestFileCanon}" ]]
then
	if [[ -n ${Volume} ]]
	then
		VolumeFreeSpace=`df -k | grep  "^${Volume}" | awk '{print $4}'`
	fi
fi

if (( ${VolumeFreeSpace} > ${FileSizeFSMaxKb} ))
then
	VolumeFreeSpace=${FileSizeFSMaxKb}
fi

if [[ -z ${FILE_SIZE} ]]
then
	# Not Specified test file size.
	if (( ${VolumeFreeSpace} <0 ))
	then
		echo "${TestFile}: Can not resolv volume free space."
		exit 2
	fi

	VolumeFreeSpaceMiB=`awk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 ) ) }"`
	if (( ${VolumeFreeSpaceMiB} <= 20480 ))
	then
		FILE_SIZE=`awk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 ) ) }"`
		FILE_SIZE_UNIT=m
	else
		FILE_SIZE=`awk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 * 1024.0 ) ) }"`
		FILE_SIZE_UNIT=g
	fi
	if (( ${FILE_SIZE} < 1 ))
	then
		echo "${TestFile}: Error: Not enough space to test. VolumeFreeSpace=${VolumeFreeSpace}Kibytes"
		remove_test_file
		recover_queue_config
		recover_hung_task_to
		remove_work_file
		exit 2
	fi
	FILE_SIZE="${FILE_SIZE}${FILE_SIZE_UNIT}"
	echo "${TestFile}: Test File size. FILE_SIZE=${FILE_SIZE}"
fi

# Get device model name.
# To append log directory path.

if [[ -n ${STORAGE_DEVICE} ]]
then
	ModelName=`/sbin/hdparm -i ${STORAGE_DEVICE} \
		| grep 'Model=' \
		| sed -n 's/.*Model=\(.*\),*/\1/p' \
		| cut -f 1 -d ',' \
		| tr -d '\012' \
		| tr '[[:space:]-]' '_' \
		`
	if [[ -n ${ModelName} ]]
	then
		echo "${TestFile}: Resolved model name. ModelName=${ModelName}"
	fi
fi

if [[ ( -z "${OptionalLabel}" )  &&  ( -z "${ModelName}" ) ]]
then
	case ${FileSystem} in
		(vfat|fat)
			OptionalLabel=`dosfslabel "${Volume}" | tail -1 \
				| sed -n 's/^[[:space:]]*// p' | sed -n 's/[[:space:]]*$// p' \
				| tr ' :' '_.' `
		;;
		(ext*)
			OptionalLabel=`tune2fs -l ${Volume} \
				| grep 'volume name' \
				| cut -d ':' -f 2 \
				| awk '{print $1}' \
				| tr ' :<>' '_.()'`
		;;
	esac
fi

# Show config function.

function show_config() {
	echo "TestScript: $0"
	echo "RunLevel: `/sbin/runlevel`"
	echo "uname: `uname -a`"
	echo "swapon:"
	/sbin/swapon -s
	echo "mount:"
	mount
	echo "fdisk:"
	(export LANG=C; /sbin/fdisk -u -l /dev/${STORAGE_DEVICE_NAME} )
	echo "hdparm:"
	/sbin/hdparm -i /dev/${STORAGE_DEVICE_NAME}
	echo "smartctl:"
	 /usr/sbin/smartctl --all /dev/${STORAGE_DEVICE_NAME}
	echo "df:"
	( export LANG=C; df )
	echo "queue:"
	(	cd /sys/block/${STORAGE_DEVICE_NAME}/queue
		curdir=`pwd`
		echo "${curdir}: BEGIN Queue configs."
		for f in `ls`
		do
			if [[ -f ${f} ]]
			then
				echo "${curdir}/${f}: `cat ${f}`"
			fi
		done
		echo "${curdir}: END Queue configs."
	)
	echo "DATE: `date '+%y-%m-%d %H:%M:%S'`";
}

now_date="`date +%y%m%d%H%M%S`"

LOG_DIR="log-${ModelName}${OptionalLabel}-${now_date}-${FILE_SIZE}"

if [[ ! -d "${LOG_DIR}" ]]
then
	echo "${LOG_DIR}: Create log directory."
	CurDirUG=`stat -c '%u:%g' . `
	mkdir -p "${LOG_DIR}"
	chmod u+rw "${LOG_DIR}"
	if (( ${Uid} == 0 ))
	then
		chown "${CurDirUG}" "${LOG_DIR}"
	fi
fi

# Create Log File

LogFile=""
function CreateLogFile() {
	touch "${LogFile}"
	if (( ${Uid} == 0 ))
	then
		chown "${CurDirUG}" "${LogFile}"
	fi
}

yn_index=0
file_index=0

for direct in ${O_DIRECT_ORDER}
do
	i=0
	while (( ( ${i} < ${LOOP_MAX} ) && ( ${Result} == 0 ) ))
	do
		remove_test_file
		context_seed=$(( ${i} + ${yn_index} * ${SEED_SPAN_DIRECT} + ${SEED} ))
		level=0

		# Sequential Write
		LogFile="${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-%02d" ${i} ${level}`.txt"
		CreateLogFile

		echo "TEST: index=${i}, SequentialWrite, SEQUENTIAL_DIRECT=${SEQUENTIAL_DIRECT}" | tee -a "${LogFile}"

		CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-py -xb -rn -my \
			-b ${BLOCK_SIZE} -i ${RANDOM_BLOCKS_MIN} -a ${RANDOM_BLOCKS_MAX} -i exp -n 0 \
			-u ${SEQUENTIAL_BLOCKS} \
			-d${SEQUENTIAL_DIRECT} -d${direct} -s ${context_seed} \
			${SEQUENTIAL_WRITE_EXTRA_OPTIONS} \
			${TestFile} \
		)

		echo "COMMAND: ${CommandBody[*]}" | tee -a "${LogFile}"

		set_read_ahead_kb ${SEQUENTIAL_READ_AHEAD_KB}
		( show_config ) | tee -a "${LogFile}"

		echo 1 > ${TestBinResult}
		(    ${TIME_PROFILE}  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 \
		  && echo 0 > ${TestBinResult} \
		) | tee -a "${LogFile}"
		if (( `cat "${TestBinResult}"` != 0 ))
		then
			Result=1
		fi
		file_index=$(( ${file_index} + 1 ))
		level=$(( ${level} + 1 ))

		# Random Read and Write
		LogFile="${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-%02d" ${i} ${level}`.txt"
		CreateLogFile

		echo "TEST: index=${i}, RandomMaxBlocks=${RANDOM_BLOCKS_MAX}, DoDirectRW=${direct}" | tee -a "${LogFile}"

		CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-pn -xb -rn -my \
			-b ${BLOCK_SIZE} -i ${RANDOM_BLOCKS_MIN} -a ${RANDOM_BLOCKS_MAX} -i exp -n ${RANDOM_REPEATS} \
			-u ${SEQUENTIAL_BLOCKS} \
			-d${SEQUENTIAL_DIRECT} -d${direct} -s ${context_seed} \
			${RANDOM_EXTRA_OPTIONS} \
			${TestFile} \
		)
		echo "COMMAND: ${CommandBody[*]}" | tee -a "${LogFile}"

		set_read_ahead_kb ${RANDOM_READ_AHEAD_KB}
		( show_config ) | tee -a "${LogFile}"

		echo 1 > ${TestBinResult}
		(    ${TIME_PROFILE}  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 \
		  && echo 0 > ${TestBinResult} \
		) | tee -a "${LogFile}"
		if (( `cat "${TestBinResult}"` != 0 ))
		then
			Result=1
		fi
		file_index=$(( ${file_index} + 1 ))
		level=$(( ${level} + 1 ))

		# Sequential read
		LogFile="${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-%02d" ${i} ${level}`.txt"
		CreateLogFile

		echo "TEST: index=${i}, SequentialRead, SEQUENTIAL_DIRECT=${SEQUENTIAL_DIRECT}," | tee -a "${LogFile}"

		CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-pn -xb -ry -my \
			-b ${BLOCK_SIZE} -i ${RANDOM_BLOCKS_MIN} -a ${RANDOM_BLOCKS_MAX} -i exp -n 0 \
			-u ${SEQUENTIAL_BLOCKS} \
			-d${SEQUENTIAL_DIRECT} -d${direct} -s ${context_seed} \
			${SEQUENTIAL_READ_EXTRA_OPTIONS} \
			${TestFile} \
		)

		echo "COMMAND: ${CommandBody[*]}" | tee -a "${LogFile}"

		set_read_ahead_kb ${SEQUENTIAL_READ_AHEAD_KB}
		( show_config ) | tee -a "${LogFile}"

		echo 1 > ${TestBinResult}
		(    ${TIME_PROFILE}  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 \
		  && echo 0 > ${TestBinResult} \
		) | tee -a "${LogFile}"

		if (( `cat "${TestBinResult}"` != 0 ))
		then
			Result=1
		fi
		file_index=$(( ${file_index} + 1 ))
		level=$(( ${level} + 1 ))

		i=$(( ${i} + 1 ))
		remove_test_file
	done
	yn_index=$(( ${yn_index} + 1 ))
done

DoneMark="${LOG_DIR}/.mark_ssdtest_done"
touch "${DoneMark}"
if (( ${Uid} == 0 ))
then
	chown "${CurDirUG}" "${DoneMark}"
fi

recover_queue_config
recover_hung_task_to
remove_work_file
if (( ${Result} == 0 ))
then
	echo "${LOG_DIR}: PASS: Logs are stored."
else
	echo "${LOG_DIR}: FAIL: Logs are stored."
fi
exit ${Result}
