CFLAGS=-O3 -Wall -Wunused -Wuninitialized
CLIBS=-lrt

DIST_FILES=\
	plotlogmix.sh plotlogmix_usbmems.sh \
	plotlogseq.sh plotlogseq_usbmems.sh \
	ssdtest.sh ssdtest_light.sh \
	ssdtest_usbmems.sh \
	mt19937ar.c mt19937ar.h mtTest.c mtTestOut.txt \
	ssdstress.c Makefile

DIST_DIR=ssdtest_1.0

TARGET=ssdstress

MTTEST_TEMP=mtTestOutUnderTest.txt

$(TARGET): $(TARGET).o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $^

mtTest: mtTest.o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $^
	./mtTest > $(MTTEST_TEMP)
	diff $(MTTEST_TEMP) mtTestOut.txt

$(TARGET).o: $(TARGET).c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

mt19937ar.o: mt19937ar.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

mtTest.o: mtTest.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

dist: $(TARGET) $(DIST_FILES)
	mkdir -p $(DIST_DIR)
	cp $(DIST_FILES) $(TARGET) $(DIST_DIR)
	tar zcvf $(DIST_DIR).tar.gz $(DIST_DIR)

clean:
	rm $(TARGET) $(TARGET).o mt19937ar.o mtTest $(MTTEST_TEMP)
	rm -rf $(DIST_DIR)
