override CXXFLAGS += -O2 -Wall -fobjc-arc -D"NS_FORMAT_ARGUMENT(A)=" -D"SKYLIGHT_AVAILABLE=$(SKYLIGHT_AVAILABLE)"

.PHONY: all clean install

all: MiddleMouseFocus MiddleMouseFocus.app

clean:
	rm -f MiddleMouseFocus
	rm -rf MiddleMouseFocus.app

install: MiddleMouseFocus.app
	rm -rf /Applications/MiddleMouseFocus.app
	cp -r MiddleMouseFocus.app /Applications/

MiddleMouseFocus: MiddleMouseFocus.mm
	    g++ $(CXXFLAGS) -o $@ $^ -framework AppKit

MiddleMouseFocus.app: MiddleMouseFocus Info.plist MiddleMouseFocus.icns
	./create-app-bundle.sh
