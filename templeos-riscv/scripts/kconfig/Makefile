# SPDX-License-Identifier: GPL-2.0
# Standalone build of Linux scripts/kconfig mconf + conf (vendored from Linux v6.11).
# Deps: C compiler + ncurses (pkg-config or Homebrew ncurses on macOS).
# Generated lexer.lex.c / parser.tab.c are vendored — flex/bison not required to build.

HOSTCC         ?= cc
HOSTPKG_CONFIG ?= pkg-config

common-objs := confdata.o expr.o lexer.lex.o menu.o parser.tab.o preprocess.o symbol.o util.o
lxdialog-objs := lxdialog/checklist.o lxdialog/inputbox.o lxdialog/menubox.o \
	lxdialog/textbox.o lxdialog/util.o lxdialog/yesno.o

HOSTCFLAGS_BASE := -D_GNU_SOURCE -I. -Iinclude -Wall -Wno-unused-parameter \
	-Wno-missing-field-initializers

.PHONY: all clean mconf conf

all: mconf conf

mconf: mconf.o mnconf-common.o $(lxdialog-objs) $(common-objs) mconf-libs
	$(HOSTCC) -o $@ mconf.o mnconf-common.o $(lxdialog-objs) $(common-objs) \
		$(shell cat mconf-libs)

conf: conf.o $(common-objs)
	$(HOSTCC) -o $@ conf.o $(common-objs)

mconf-cflags mconf-libs: mconf-cfg.sh
	@HOSTCC='$(HOSTCC)' HOSTPKG_CONFIG='$(HOSTPKG_CONFIG)' \
		$(SHELL) ./mconf-cfg.sh mconf-cflags mconf-libs

# Core objects — no ncurses
%.o: %.c
	$(HOSTCC) $(HOSTCFLAGS_BASE) -c $< -o $@

# mconf + lxdialog need ncurses cflags
mconf.o: mconf.c mconf-cflags
	$(HOSTCC) $(HOSTCFLAGS_BASE) $(shell cat mconf-cflags) -c mconf.c -o mconf.o

lxdialog/%.o: lxdialog/%.c mconf-cflags
	@mkdir -p lxdialog
	$(HOSTCC) $(HOSTCFLAGS_BASE) $(shell cat mconf-cflags) -c $< -o $@

clean:
	rm -f mconf conf *.o lxdialog/*.o mconf-cflags mconf-libs
