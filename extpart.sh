#!/bin/bash
#spilt log file into sequential-write, random-read/write, and sequential-read parts.

my_base=`basename "$0"`
my_dir=`dirname "$0"`

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
	sw_png=${f%%.*}-sw.png
	sed -n '/Twrite/,/elp/ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sw_file}
	gnuplot -e "log_file=\"${sw_file}\"; load \"${my_dir}/sequential_write.gnuplot\"; quit" > ${sw_png}

	ra_file=${f%%.*}-ra.txt
	sed -n '/^i,[[:space:]]/,/Tread/ {p}' ${f} | grep '^[[:space:]]*[0-9]' > ${ra_file}

	sr_file=${f%%.*}-sr.txt
	sr_png=${f%%.*}-sr.png
	sed -n '/Tread/,$ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sr_file}
	gnuplot -e "log_file=\"${sr_file}\"; load \"${my_dir}/sequential_read.gnuplot\"; quit" > ${sr_png}
done
