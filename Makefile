# Static library is always built; set DYNAMIC_LIB=1 to also build the shared one
DYNAMIC_LIB ?= 0

DESTDIR =
PREFIX = /usr/local

MAJOR = 1
MINOR = 10
REVISION = 8
LIB = libcli.so
LIB_STATIC = libcli.a

CC = gcc
AR = ar
ARFLAGS = rcs
DEBUG = -g
OPTIM = -O3
override CFLAGS += $(DEBUG) $(OPTIM) -Wall -std=c99 -pedantic -Wformat-security -Wno-format-zero-length -Werror -Wwrite-strings -Wformat -fdiagnostics-show-option -Wextra -Wsign-compare -Wcast-align -Wno-unused-parameter
override LDFLAGS += -shared -Wl,-soname,$(LIB).$(MAJOR).$(MINOR)
LIBS = -lcrypt

TARGET_LIBS = $(LIB_STATIC)
ifeq (1,$(DYNAMIC_LIB))
TARGET_LIBS += $(LIB)
endif

all: $(TARGET_LIBS) clitest

$(LIB_STATIC): libcli.o
	$(AR) $(ARFLAGS) $@ $^

$(LIB): libcli.o
	$(CC) -o $(LIB).$(MAJOR).$(MINOR).$(REVISION) $^ $(LDFLAGS) $(LIBS)
	-rm -f $(LIB) $(LIB).$(MAJOR).$(MINOR)
	ln -s $(LIB).$(MAJOR).$(MINOR).$(REVISION) $(LIB).$(MAJOR).$(MINOR)
	ln -s $(LIB).$(MAJOR).$(MINOR) $(LIB)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -fPIC -o $@ -c $<

libcli.o: libcli.h

clitest: clitest.o $(LIB_STATIC)
	$(CC) $(CFLAGS) -o $@ $^ $(LIBS)

# Test driver for the Perl suite in t/.  libcli.c is compiled in directly so
# the sanitizers instrument the library too.
TEST_CFLAGS = -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
	-Wall -std=c99 -pedantic -Werror -Wextra -Wno-unused-parameter

t/cli_driver: t/cli_driver.c libcli.c libcli.h
	$(CC) $(CPPFLAGS) $(TEST_CFLAGS) -I. -o $@ t/cli_driver.c libcli.c $(LIBS)

test: t/cli_driver
	prove -r t/

lint:
	clang-tidy -quiet -warnings-as-errors *.c *.h

clean:
	rm -f *.o $(LIB)* $(LIB_STATIC) clitest t/cli_driver

install: $(TARGET_LIBS)
	install -d $(DESTDIR)$(PREFIX)/include $(DESTDIR)$(PREFIX)/lib
	install -m 0644 libcli.h $(DESTDIR)$(PREFIX)/include
	install -m 0644 $(LIB_STATIC) $(DESTDIR)$(PREFIX)/lib
ifeq (1,$(DYNAMIC_LIB))
	install -m 0755 $(LIB).$(MAJOR).$(MINOR).$(REVISION) $(DESTDIR)$(PREFIX)/lib
	cd $(DESTDIR)$(PREFIX)/lib && \
	    ln -fs $(LIB).$(MAJOR).$(MINOR).$(REVISION) $(LIB).$(MAJOR).$(MINOR) && \
	    ln -fs $(LIB).$(MAJOR).$(MINOR) $(LIB)
endif

.PHONY: all test lint clean install
