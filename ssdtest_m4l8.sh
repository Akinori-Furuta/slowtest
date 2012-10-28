#!/bin/bash

MyBase="`dirname $0`"

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
	LOOP_MAX=2
fi

if [[ -z ${SEQUENTIAL_DIRECT} ]]
then
	SEQUENTIAL_DIRECT=n
fi

if [[ -z ${SEED} ]]
then
	# random seed.
	SEED=1000
fi

if [[ -z ${BLOCK_SIZE} ]]
then
	BLOCK_SIZE=512
fi

if [[ -z ${RANDOM_MAX_BLOCKS_BASE} ]]
then
	RANDOM_MAX_BLOCKS_BASE=256
fi

if [[ -z ${RANDOM_MAX_BLOCKS_MAG} ]]
then
	RANDOM_MAX_BLOCKS_MAG=4
fi

if [[ -z ${RANDOM_MAX_BLOCKS_LEVEL} ]]
then
	RANDOM_MAX_BLOCKS_LEVEL=8
fi

if [[ -z ${RANDOM_REPEATS} ]]
then
	RANDOM_REPEATS=2048
fi

RandomMaxBlocks=${RANDOM_MAX_BLOCKS_BASE}
i=1
while (( ${i} < ${RANDOM_MAX_BLOCKS_LEVEL} ))
do
	RandomMaxBlocks=$(( ${RandomMaxBlocks} * ${RANDOM_MAX_BLOCKS_MAG} ))
	i=$(( ${i} + 1 ))
done
RandomMaxBlocksL0=${RandomMaxBlocks}

if [[ -z ${SEQUENTIAL_BLOCKS} ]]
then
	SEQUENTIAL_BLOCKS=$(( ${RandomMaxBlocksL0} * 2 ))
fi



# Get uid.
# Strongly recommended root.

Uid=`id | sed 's/uid=\([0-9][0-9]*\).*/\1/'`

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
	exit 2
}

# Trap signals.
trap signaled HUP INT

# Parse Argument

function Help() {
	echo "$0 [-L OptionalLabel] [-h] test_file_or_directory"
	exit 1
}

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

TestFile="${parsed_arg[${i}]}"


# This test context.
uuid=`cat /proc/sys/kernel/random/uuid`

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

for mount_point in `gawk '{print $2}' /proc/mounts | sort -r`
do
	if ( echo ${TestFileCanon} | grep -q "^${mount_point}" )
	then
		Volume=`grep "${mount_point}" /proc/mounts | gawk '{print $1}'`
		break
	fi
done

if [[ -z ${Volume} ]]
then
	echo "${TestFile}: Notice: Can not resolv volume."
else
	echo "${TestFile}: Info: Resolved volume device. Volume=${Volume}"
fi

if [[ -z ${SSD_DEVICE_NAME} ]]
then
	if ( echo ${Volume} | grep -q "^/dev/" )
	then
		SSD_DEVICE_NAME=`echo ${Volume##*/} | sed 's/[0-9]*$//'`
		SSD_DEVICE=/dev/${SSD_DEVICE_NAME}
	else
		echo "${FileName}: Error: Can not handle this volume type. Volume=${Volume}"
		exit 2
	fi
else
	SSD_DEVICE=/dev/${SSD_DEVICE_NAME}
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

MaxHwSectorsKb=/sys/block/${SSD_DEVICE_NAME}/queue/max_hw_sectors_kb
MaxSectorsKb=/sys/block/${SSD_DEVICE_NAME}/queue/max_sectors_kb
ReadAheadKb=/sys/block/${SSD_DEVICE_NAME}/queue/read_ahead_kb

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
if [[ -n ${Volume} ]]
then
	VolumeFreeSpace=`df -k | grep  "^${Volume}" | gawk '{print $4}'`
fi

if [[ -z ${FILE_SIZE} ]]
then
	# Not Specified test file size.
	if (( ${VolumeFreeSpace} <0 ))
	then
		echo "${TestFile}: Can not resolv volume free space."
		exit 2
	fi

	VolumeFreeSpaceMiB=`gawk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 ) ) }"`
	if (( ${VolumeFreeSpaceMiB} <= 20480 ))
	then
		FILE_SIZE=`gawk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 ) ) }"`
		FILE_SIZE_UNIT=m
	else
		FILE_SIZE=`gawk "BEGIN { print int ( ( ${VolumeFreeSpace} * ${TEST_USAGE_RATIO} ) / ( 1024.0 * 1024.0 ) ) }"`
		FILE_SIZE_UNIT=g
	fi
	if (( ${FILE_SIZE} < 1 ))
	then
		echo "${TestFile}: Error: Not enough space to test. VolumeFreeSpace=${VolumeFreeSpace}Kibytes"
		remove_test_file
		recover_queue_config
		recover_hung_task_to
		exit 2
	fi
	FILE_SIZE="${FILE_SIZE}${FILE_SIZE_UNIT}"
	echo "${TestFile}: Test File size. FILE_SIZE=${FILE_SIZE}"
fi

# Get device model name.
# To append log directory path.

if [[ -n ${SSD_DEVICE} ]]
then
	ModelName=`/sbin/hdparm -i ${SSD_DEVICE} \
		| grep 'Model=' \
		| sed -n 's/.*Model=\(.*\),*/\1/p' \
		| cut -f 1 -d ',' \
		| tr -d '\012' \
		| tr '[[:space:]]' '_' \
		`
	if [[ -n ${ModelName} ]]
	then
		echo "${TestFile}: Resolved model name. ModelName=${ModelName}"
	fi
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
	(export LANG=C; /sbin/fdisk -u -l /dev/${SSD_DEVICE_NAME} )
	echo "hdparm:"
	/sbin/hdparm -i /dev/${SSD_DEVICE_NAME}
	echo "smartctl:"
	 /usr/sbin/smartctl --all /dev/${SSD_DEVICE_NAME}
	echo "df:"
	( export LANG=C; df )
	echo "queue:"
	(	cd /sys/block/${SSD_DEVICE_NAME}/queue
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
	mkdir -p "${LOG_DIR}"
fi

file_index=0

for direct in N Y
do

	i=0
	while (( ${i} < ${LOOP_MAX} ))
	do
		remove_test_file

		LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-00" ${i}`.txt
		echo "TEST: index=${i}, SequentialWrite, SEQUENTIAL_DIRECT=${SEQUENTIAL_DIRECT}" >> ${LogFile}

		CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
		-py -xb -rn -my \
		-b ${BLOCK_SIZE} -i 1 -a ${RandomMaxBlocks} -n 0 \
		-u ${SEQUENTIAL_BLOCKS} \
		-d${SEQUENTIAL_DIRECT} -d${direct} -s $(( ${i} * 3 + 0 + ${SEED} )) ${TestFile} \
		)

		echo "COMMAND: ${CommandBody[*]}" >> ${LogFile}

		set_read_ahead_kb ${SEQUENTIAL_READ_AHEAD_KB}
		( show_config ) >> ${LogFile}
		( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 ) | tee -a ${LogFile}

		file_index=$(( ${file_index} + 1 ))

		RandomMaxBlocks=${RandomMaxBlocksL0}
		level=0
		while (( ${level} < ${RANDOM_MAX_BLOCKS_LEVEL} ))
		do
			level=$(( ${level} + 1 ))

			LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-%02d" ${i} ${level}`.txt
			echo "TEST: index=${i}, RandomMaxBlocks=${RandomMaxBlocks}, DoDirectRW=${direct}" >> ${LogFile}

			CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-pn -xb -rn -my \
			-b ${BLOCK_SIZE} -i 1 -a ${RandomMaxBlocks} -n ${RANDOM_REPEATS} \
			-u ${SEQUENTIAL_BLOCKS} \
			-d${SEQUENTIAL_DIRECT} -d${direct} -s $(( ${i} * 3 + 0 + ${SEED} )) ${TestFile} \
			)

			echo "COMMAND: ${CommandBody[*]}" >> ${LogFile}

			set_read_ahead_kb ${RANDOM_READ_AHEAD_KB}
			( show_config ) >> ${LogFile}
			( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 ) | tee -a ${LogFile}

			file_index=$(( ${file_index} + 1 ))

			RandomMaxBlocks=$(( ${RandomMaxBlocks} / ${RANDOM_MAX_BLOCKS_MAG} ))
		done
		level=$(( ${level} + 1 ))

		LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d-%02d" ${i} ${level}`.txt
		echo "TEST: index=${i}, SequentialRead, SEQUENTIAL_DIRECT=${SEQUENTIAL_DIRECT}," >> ${LogFile}

		CommandBody=( ${MyBase}/${TestBin} -f ${FILE_SIZE} \
		-pn -xb -ry -my \
		-b ${BLOCK_SIZE} -i 1 -a ${RandomMaxBlocks} -n 0 \
		-u ${SEQUENTIAL_BLOCKS} \
		-d${SEQUENTIAL_DIRECT} -d${direct} -s $(( ${i} * 3 + 0 + ${SEED} )) ${TestFile} \
		)

		echo "COMMAND: ${CommandBody[*]}" >> ${LogFile}

		set_read_ahead_kb ${SEQUENTIAL_READ_AHEAD_KB}
		( show_config ) >> ${LogFile}
		( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody[*]} 2>&1 ) | tee -a ${LogFile}

		file_index=$(( ${file_index} + 1 ))

		i=$(( ${i} + 1 ))

		remove_test_file
	done
done

recover_queue_config
recover_hung_task_to
exit 0
