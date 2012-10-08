CFLAGS=-O3 -Wall -Wunused -Wuninitialized
CLIBS=-lrt

TARGET=ssdstress

$(TARGET): $(TARGET).c
	$(CC) $(CFLAGS) -o $@ $(CLIBS) $<

clean:
	rm $(TARGET)
