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

# ---- website (docs/) and release kit
SITE_ROM := docs/rom/lantern-moth.nes
RELEASE_FILES := lantern-moth.nes docs/press/lantern-moth-release-kit.zip docs/press/manual.pdf \
	docs/press/pamphlet.pdf docs/press/box-front.png docs/press/box-back.png docs/press/cartridge.png \
	docs/press/label.png docs/media/video/trailer.mp4

$(SITE_ROM): lantern.nes
	@mkdir -p docs/rom
	cp lantern.nes $@

site: $(SITE_ROM)

serve: site
	python3 -m http.server --directory docs 8000

art:
	python3 tools/make_art.py docs/media/art

press:
	tools/render_press.sh
	cd docs && rm -f press/lantern-moth-release-kit.zip && \
	  zip -q -r press/lantern-moth-release-kit.zip press/*.png press/*.pdf media/logo.png media/art media/shots

release: lantern.nes
	@mkdir -p dist
	cp lantern.nes dist/lantern-moth.nes
	cp $(filter-out lantern-moth.nes,$(RELEASE_FILES)) dist/
	@ls -l dist

run: lantern.nes
	$(RETROARCH) -L $(NES_CORE) $<

clean:
	rm -rf lantern.o lantern.nes lantern.map lantern.lbl lantern.dbg gen dist $(SITE_ROM)

.PHONY: test stress run clean site serve art press release
