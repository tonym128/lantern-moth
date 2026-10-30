CA65 ?= ca65
LD65 ?= ld65
RETROARCH ?= retroarch
NES_CORE ?= /usr/lib/libretro/mesen_libretro.so

SRC := $(wildcard src/*.s src/*.inc)
GEN := gen/lantern.chr gen/tables.inc gen/levels.inc gen/sound.inc gen/tiles.inc gen/stages.json

lantern.nes: lantern.o nrom.cfg
	$(LD65) -C nrom.cfg -o $@ lantern.o -m lantern.map -Ln lantern.lbl --dbgfile lantern.dbg
	@python3 usage.py lantern.map || (rm -f $@; exit 1)

lantern.o: $(SRC) $(GEN)
	$(CA65) -g -I src -I . src/lantern.s -o $@

$(GEN) &: make_assets.py boss_art.py $(wildcard levels/*.txt)
	python3 make_assets.py

tests/node_modules: tests/package.json
	cd tests && npm install
	@touch $@

test: lantern.nes tests/node_modules
	cd tests && npm test

stress: lantern.nes tests/node_modules
	cd tests && npm run stress

run: lantern.nes
	$(RETROARCH) -L $(NES_CORE) $<

clean:
	rm -rf lantern.o lantern.nes lantern.map lantern.lbl lantern.dbg gen

.PHONY: test stress run clean
