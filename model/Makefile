CXX ?= g++
CXXFLAGS ?= -O2 -Wall -Wextra -std=c++11

OBJS = cache_model.o main.o

cachesim: $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS)

cache_model.o: cache_model.cpp cache_model.h
	$(CXX) $(CXXFLAGS) -c cache_model.cpp

main.o: main.cpp cache_model.h
	$(CXX) $(CXXFLAGS) -c main.cpp

run: cachesim
	./cachesim -o .

clean:
	rm -f cachesim $(OBJS) trace.hex expected.hex

.PHONY: run clean
