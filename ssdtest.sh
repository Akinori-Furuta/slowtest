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

if [[ -z ${SEED} ]]
then
	# random seed.
	SEED=1000
fi

if [[ -z ${BLOCK_SIZE} ]]
then
	BLOCK_SIZE=512
fi

if [[ -z ${MAX_SECTORS_RANDOM_LONG} ]]
then
	MAX_SECTORS_RANDOM_LONG=524288
fi

if [[ -z ${MAX_SECTORS_RANDOM_MIDDLE} ]]
then
	MAX_SECTORS_RANDOM_MIDDLE=16384
fi

if [[ -z ${MAX_SECTORS_RANDOM_SHORT} ]]
then
	MAX_SECTORS_RANDOM_SHORT=512
fi

if [[ -z ${RANDOM_REPEATS} ]]
then
	RANDOM_REPEATS=8192
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

# Recover max_sectors_kb kernel parameter.
# No arguments.
# global SavedMaxSectorsKb, MaxSectorsKb, Uid
function recover_max_sectors_kb() {
	if [[ -n ${SavedMaxSectorsKb} ]]
	then
		if (( ${Uid} == 0 ))
		then
			echo "${MaxSectorsKb}: Info: Restore max_sectors_kb. SavedMaxSectorsKb=${SavedMaxSectorsKb}"
			echo ${SavedMaxSectorsKb} > ${MaxSectorsKb}
		else
			echo "${MaxSectorsKb}: Notice: Skip restore max_sectors_kb, not root. SavedMaxSectorsKb=${SavedMaxSectorsKb}"
		fi
	fi
}

# Signal handler.
function signaled() {
	echo "$0: Interrupted."
	remove_test_file
	recover_max_sectors_kb
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
	case in ${opt}
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

# Trim max_sectors_kb

MaxHwSectorsKb=/sys/block/${SSD_DEVICE_NAME}/queue/max_hw_sectors_kb
MaxSectorsKb=/sys/block/${SSD_DEVICE_NAME}/queue/max_sectors_kb

ReadMaxHwSectorsKb=`cat ${MaxHwSectorsKb}`
SavedMaxSectorsKb=`cat ${MaxSectorsKb}`

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
else
	echo "${MaxSectorsKb}: Notice: Skip update max_sectors_kb, not root."
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
		recover_max_sectors_kb
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
	mkdir -p "${LOG_DIR}"
fi

file_index=0

for direct in N Y
do
	i=0
	while (( ${i} < ${LOOP_MAX} ))
	do
		remove_test_file

		LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d" ${i}`-L.txt
		echo "TEST: index=${i}, Random=Long, DoDirectRW=${direct}" >> ${LogFile}

		if [[ -n ${DEF_CONFIG_RA_L} ]]
		then
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			${DEF_CONFIG_RA_L} \
			-d${direct} -s $(( ${i} * 3 + 0 + ${SEED} )) ${TestFile}"
		else
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-py -xb -rn -my -b ${BLOCK_SIZE} -i 1 -a ${MAX_SECTORS_RANDOM_LONG} -n ${RANDOM_REPEATS} \
			-dn -d${direct} -s $(( ${i} * 3 + 0 + ${SEED} )) ${TestFile}"
		fi

		echo "COMMAND: ${CommandBody}" >> ${LogFile}
		( show_config ) >> ${LogFile}
		( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody} 2>&1 ) | tee -a ${LogFile}
		file_index=$(( ${file_index} + 1 ))

		LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d" ${i}`-M.txt
		echo "TEST: index=${i}, Random=Middle, DoDirectRW=${direct}" >> ${LogFile}

		if [[ -n ${DEF_CONFIG_RA_M} ]]
		then
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			${DEF_CONFIG_RA_M} \
			-d${direct} -s $(( ${i} * 3 + 1 + ${SEED} )) ${TestFile}"
		else
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-pn -xb -rn -my -b ${BLOCK_SIZE} -i 1 -a ${MAX_SECTORS_RANDOM_MIDDLE} -n ${RANDOM_REPEATS} \
			-dn -d${direct} -s $(( ${i} * 3 + 1 + ${SEED} )) ${TestFile}"
		fi

		echo "COMMAND: ${CommandBody}" >> ${LogFile}
		( show_config ) >> ${LogFile}
		( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody} 2>&1 ) | tee -a ${LogFile}
		file_index=$(( ${file_index} + 1 ))

		LogFile=${LOG_DIR}/`printf "%04d" ${file_index}`-${direct}-`printf "%04d" ${i}`-S.txt
		echo "TEST: index=${i}, Random=Short, DoDirectRW=${direct}" >> ${LogFile}

		if [[ -n ${DEF_CONFIG_RA_S} ]]
		then
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			${DEF_CONFIG_RA_S} \
			-d${direct} -s $(( ${i} * 3 + 2 + ${SEED} )) ${TestFile}"
		else
			CommandBody="${MyBase}/${TestBin} -f ${FILE_SIZE} \
			-pn -xb -ry -my -b ${BLOCK_SIZE} -i 1 -a ${MAX_SECTORS_RANDOM_SHORT} -n ${RANDOM_REPEATS} \
			-u $(( ${MAX_SECTORS_RANDOM_LONG} * 2 )) \
			-dn -d${direct} -s $(( ${i} * 3 + 2 + ${SEED} )) ${TestFile}"
		fi

		echo "COMMAND: ${CommandBody}" >> ${LogFile}
		( show_config ) >> ${LogFile}
		( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody} 2>&1 ) | tee -a ${LogFile}
		file_index=$(( ${file_index} + 1 ))

		remove_test_file

		i=$(( ${i} + 1 ))
	done
done

recover_max_sectors_kb
exit 0
