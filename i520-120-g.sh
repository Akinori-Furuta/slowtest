#!/bin/bash
# this test script is paired with i520-120-f.sh

FILE_SIZE=100g
DEF_CONFIG="-f ${FILE_SIZE} -dnN -py -ry -xb -my -b 512 -i 1 -a 64k -n 32768"
TEST_FILE_BODY=/mnt/bench1/work/${FILE_SIZE}

SSD_DEVICE_NAME=sdb
SSD_DEVICE=/dev/${SSD_DEVICE_NAME}
LOOP_MAX=8
SEED=400

now_date="`date +%y%m%d%H%M%S`"

LOGDIR="log_${now_date}_${FILE_SIZE}"

function show_config() {
	echo "TestScript: $0"
	echo "RunLevel: `/sbin/runlevel`"
	echo "uname: `uname -a`"
	echo "${SSD_DEVICE}: status"
	/sbin/swapon -s
	echo "${SSD_DEVICE}: mount"
	mount
	echo "${SSD_DEVICE}: hdparm"
	/sbin/hdparm -i ${SSD_DEVICE}
	echo "${SSD_DEVICE}: smartctl"
	smartctl --all ${SSD_DEVICE}
	echo "${SSD_DEVICE}: df"
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
