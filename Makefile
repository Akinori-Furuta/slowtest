CFLAGS=-O2 -Wall -Wunused
CLIBS=-lrt

TARGET=ssdstress

$(TARGET): $(TARGET).c
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $<

clean:
	rm $(TARGET)
