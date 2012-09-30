#!/bin/bash
#spilt log file into sequential-write, random-read/write, and sequential-read parts.

for f in $*
do
	ext=${f##*.}
	if [[ "${ext}" != "txt" ]]
	then
		continue
	fi

	body=${f%%.*}
	if ( echo "${body}" |  grep -q -e '[-]sw$' -e '[-]ra$' -e '[-]sr$' )
	then
		continue
	fi

	sw_file=${f%%.*}-sw.txt
	sed -n '/Twrite/,/elp/ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sw_file}

	ra_file=${f%%.*}-ra.txt
	sed -n '/^i,[[:space:]]/,/Tread/ {p}' ${f} | grep '^[[:space:]]*[0-9]' > ${ra_file}

	sr_file=${f%%.*}-sr.txt
	sed -n '/Tread/,$ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sr_file}
done
