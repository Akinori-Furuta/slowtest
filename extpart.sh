#!/bin/bash
#spilt log file into sequential-write, random-read/write, and sequential-read parts.

my_base=`basename "$0"`
my_dir=`dirname "$0"`

TempPath=/dev/shm

for f in $*
do
	ext=${f##*.}
	if [[ "${ext}" != "txt" ]]
	then
		continue
	fi

	body=${f%.*}
	if ( echo "${body}" |  grep -q -e '[-]sw$' -e '[-]ra$' -e '[-]sr$' -e '[-]rr$' -e '[-]rw$' )
	then
		continue
	fi

	sw_file=${f%.*}-sw.txt
	sw_png=${f%.*}-sw.png
	sed -n '/Twrite/,/elp/ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sw_file}
	gnuplot -e "log_file=\"${sw_file}\"; load \"${my_dir}/sequential_write.gnuplot\"; quit" > ${sw_png}

	ra_file=${TempPath}/`basename ${f%.*}-ra.txt`
	sed -n '/^i,[[:space:]]/,/Tread/ {p}' ${f} | grep '^[[:space:]]*[0-9]' > ${ra_file}

	ra_r_file=${f%.*}-rr.txt
	ra_r_png=${f%.*}-rr.png
	grep 'r' "${ra_file}" |  sed -n 's/,//gp' > ${ra_r_file}
	gnuplot -e "log_file=\"${ra_r_file}\"; load \"${my_dir}/random_read.gnuplot\"; quit" > ${ra_r_png}

	ra_w_file=${f%.*}-rw.txt
	ra_w_png=${f%.*}-rw.png
	grep 'w' "${ra_file}" | sed -n 's/,//gp'  > ${ra_w_file}
	gnuplot -e "log_file=\"${ra_w_file}\"; load \"${my_dir}/random_write.gnuplot\"; quit" > ${ra_w_png}

	rm "${ra_file}"

	sr_file=${f%.*}-sr.txt
	sr_png=${f%.*}-sr.png
	sed -n '/Tread/,$ {p}' ${f} | grep '^[0-9][.]' | sed -n 's/,//gp' | sed -n 's/%//gp' > ${sr_file}
	gnuplot -e "log_file=\"${sr_file}\"; load \"${my_dir}/sequential_read.gnuplot\"; quit" > ${sr_png}
done
