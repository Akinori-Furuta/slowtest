# Make tar.gz package, ssdstress binary, clean, and test.
#
#  Copyright 2012, 2017 Akinori Furuta<afuruta@m7.dion.ne.jp>.
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

# Make tar.gz package:
# $ make dist
#
# Make ssdstress binary:
# $ make
#
# Clean:
# $ make clean
#
# Test MT19937 (Mersenne Twister) lib:
# $ make mtTest
#

CFLAGS=-O3 -Wall -Wunused -Wuninitialized

UseNative=$(shell uname -m | grep -q -e x86_64 -e 'i[3456]86' -e athlon | echo $$? )
ifeq ($(UseNative), 0)
	CFLAGS+= -march=native -mtune=native
endif

CLIBS=-lrt -lm

DIST_FILES=\
	ssdtest.sh ssdtest_light.sh \
	ssdtest_usbmems.sh ssdtestloop.sh \
	ssdtestcommon.sh \
	htmlplot.sh \
	plotlogmix.sh plotlogmix_usbmems.sh plotlogmix_uhs1.sh \
	plotlogseq.sh plotlogseq_usbmems.sh plotlogseq_uhs1.sh \
	sequential-ts_pr.gnuplot \
	random-ts_at.gnuplot random-at_tl.gnuplot random-ts_tl.gnuplot \
	pageupdater.sh pageupdaterloop.sh \
	mt19937ar.c mt19937ar.h mtTest.c mt19937ar.out readme-mt.txt \
	ssdstress.c Makefile \
	readme.html README_JP

DIST_DIR=ssdtest_2.00

TARGET=ssdstress

MTTEST_TEMP=mtTestOutUnderTest.txt

Test2SComp=$(shell echo -n '        ' | tr ' ' '\377' | od -t d4 | grep -e '[-]1' | awk '{print $$2}' )

ifeq ($(Test2SComp), -1)
	CFLAGS_CONFIG_2SCOMP?=-DCONFIG_2SCOMP
endif

CFLAGS+=$(CFLAGS_CONFIG_2SCOMP)

$(TARGET): $(TARGET).o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $^ $(CLIBS)

mtTest: mtTest.o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $^ $(CLIBS)
	./mtTest > $(MTTEST_TEMP)
	diff $(MTTEST_TEMP) mt19937ar.out

$(TARGET).o: $(TARGET).c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $< $(CLIBS)

mt19937ar.o: mt19937ar.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $< $(CLIBS)

mtTest.o: mtTest.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $< $(CLIBS)

dist: $(TARGET) $(DIST_FILES)
	mkdir -p $(DIST_DIR)
	cp -p $(DIST_FILES) $(DIST_DIR)
	tar zcvf $(DIST_DIR).tar.gz $(DIST_DIR)

clean:
	rm -rf $(TARGET) $(TARGET).o mt19937ar.o mtTest $(MTTEST_TEMP)
	rm -rf $(DIST_DIR)
