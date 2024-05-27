SKYLIGHT_AVAILABLE := $(shell test -d /System/Library/PrivateFrameworks/SkyLight.framework && echo 1 || echo 0)
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
        ifeq ($(SKYLIGHT_AVAILABLE), 1)
	    g++ $(CXXFLAGS) -o $@ $^ -framework AppKit -F /System/Library/PrivateFrameworks -framework SkyLight
        else
	    g++ $(CXXFLAGS) -o $@ $^ -framework AppKit
        endif

MiddleMouseFocus.app: MiddleMouseFocus Info.plist MiddleMouseFocus.icns
	./create-app-bundle.sh
