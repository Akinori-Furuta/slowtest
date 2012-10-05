#!/bin/bash
# this test script is paired with i520-120-l.sh

if [[ -z ${FILE_SIZE} ]]
then
	FILE_SIZE=100g
fi

if [[ -z ${DEF_CONFIG} ]]
then
	DEF_CONFIG="-f ${FILE_SIZE} -dnN -py -ry -xb -my -b 512 -i 1 -a 512k -n 65536"
fi

if [[ -z ${TEST_FILE_BODY} ]]
then
	TEST_FILE_BODY=/mnt/bench1/work/${FILE_SIZE}
fi

TEST_FILE_BODY_CANON=`readlink -f ${TEST_FILE_BODY}`

if [[ -z ${SSD_DEVICE_NAME} ]]
then
	for mp in `gawk '{print $2}' /proc/mounts | sort -r`
	do
		if ( echo ${TEST_FILE_BODY_CANON} | grep -q "^${mp}" )
		then
			Volume=`grep "${mp}" /proc/mounts | gawk '{print $1}'`
			if ( echo ${Volume} | grep -q "^/dev/" )
			then
				SSD_DEVICE_NAME=`echo ${Volume##*/} | sed 's/[0-9]*$//'`
				SSD_DEVICE=/dev/${SSD_DEVICE_NAME}
				echo "${TEST_FILE_BODY}: Resolved volume device. SSD_DEVICE_NAME=${SSD_DEVICE_NAME}"
				break
			fi
		fi
	done
fi

if [[ -z ${SSD_DEVICE_NAME} ]]
then
	SSD_DEVICE_NAME=sdb
fi

if [[ -z ${SSD_DEVICE} ]]
then
	SSD_DEVICE=/dev/${SSD_DEVICE_NAME}
fi

LOOP_MAX=4
SEED=500

now_date="`date +%y%m%d%H%M%S`"

LOGDIR="log_${now_date}_${FILE_SIZE}"

function show_config() {
	echo "TestScript: $0"
	echo "RunLevel: `/sbin/runlevel`"
	echo "uname: `uname -a`"
	/sbin/swapon -s
	mount
	/sbin/hdparm -i /dev/${SSD_DEVICE_NAME}
	( export LANG=C; df )
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

TestFile=${TEST_FILE_BODY}-00000-0000.bin

function remove_test_file() {
	if [[ -f ${TestFile} ]]
	then
		echo "${TestFile}: `date '+%y-%m-%d %H:%M:%S %s'`: Remove test file."
		rm ${TestFile}
	fi
}

if [[ ! -d "${LOGDIR}" ]]
then
	mkdir -p "${LOGDIR}"
fi

# Clean test file.

i=0
while (( ${i} < ${LOOP_MAX} ))
do
	TestFile=${TEST_FILE_BODY}-`printf "%05d-%04d" $$ ${i}`.bin
	remove_test_file
	i=$(( ${i} + 1 ))
done

i=0
while (( ${i} < ${LOOP_MAX} ))
do
	TestFile=${TEST_FILE_BODY}-`printf "%05d-%04d" $$ ${i}`.bin
	remove_test_file

	LogFile=${LOGDIR}/`printf "%04d" ${i}`.txt

	echo "TEST: index=${i}" >> ${LogFile}
	CommandBody="./slowtest ${DEF_CONFIG} -s $(( ${i} + ${SEED} )) ${TestFile}"
	echo "COMMAND: ${CommandBody}" >> ${LogFile}
	( show_config ) >> ${LogFile}
	( /usr/bin/time  -f 'U:%U, S:%S, E:%e' ${CommandBody} 2>&1 ) | tee -a ${LogFile}
	remove_test_file

	i=$(( ${i} + 1 ))
done
