CFLAGS=-O3 -Wall -Wunused -Wuninitialized
CLIBS=-lrt

TARGET=ssdstress

$(TARGET): $(TARGET).o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $^

mtTest: mtTest.o mt19937ar.o
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $^

$(TARGET).o: $(TARGET).c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

mt19937ar.o: mt19937ar.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

mtTest.o: mtTest.c mt19937ar.h
	$(CC) -c $(CFLAGS) -o $@ $(CLIBS) $<

clean:
	rm $(TARGET) $(TARGET).o mt19937ar.o mtTest
