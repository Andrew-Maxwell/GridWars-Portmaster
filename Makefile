BINARY := gridwars
ZIP    := gridwars.zip
STAGE  := .release

.PHONY: all build release clean

all: build

build:
	bmk makeapp -t gui -r -w -platform raspberrypi -arch arm64 $(BINARY).bmx

release: build
	rm -rf "$(STAGE)" "$(ZIP)"
	mkdir -p "$(STAGE)/gridwars/music" "$(STAGE)/gridwars/sounds" "$(STAGE)/gridwars/licenses"
	cp portmaster/GridWars.sh portmaster/port.json portmaster/README.md \
	   portmaster/screenshot.jpg portmaster/gameinfo.xml "$(STAGE)/"
	cp $(BINARY) gridwars.gptk Colours.txt Readme.txt "$(STAGE)/gridwars/"
	cp *.bmx "$(STAGE)/gridwars/"
	cp -r gfx "$(STAGE)/gridwars/"
	cp music/*.ogg "$(STAGE)/gridwars/music/"
	cp sounds/*.wav "$(STAGE)/gridwars/sounds/"
	cp licenses/* "$(STAGE)/gridwars/licenses/"
	cd "$(STAGE)" && zip -r "../$(ZIP)" GridWars.sh port.json README.md screenshot.jpg gameinfo.xml gridwars/
	rm -rf "$(STAGE)"

clean:
	rm -f "$(BINARY)"
	rm -rf .bmx "$(STAGE)" "$(ZIP)"
