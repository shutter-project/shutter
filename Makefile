prefix = /usr/local

all:
	./po2mo.sh

clean:
	if [ -d $(srcdir)share/locale ]; then \
		rm -r $(srcdir)share/locale; \
	fi
install: all
	install -Dm644 $(srcdir)COPYING $(prefix)/share/doc/shutter/COPYING
	install -Dm644 $(srcdir)README $(prefix)/share/doc/shutter/README
	install -Dm755 $(srcdir)bin/shutter $(prefix)/bin/shutter
	cp -r $(srcdir)share/ $(prefix)/

uninstall:
	rm $(prefix)/bin/shutter
	rm $(prefix)/share/appdata/shutter.appdata.xml
	rm $(prefix)/share/applications/shutter.desktop
	rm -r $(prefix)/share/doc/shutter/
	rm $(prefix)/share/man/man1/shutter.1.gz
	rm $(prefix)/share/pixmaps/shutter.png
	rm -r $(prefix)/share/shutter/
	rm $(prefix)/share/icons/HighContrast/scalable/apps/shutter.svg
	rm $(prefix)/share/icons/HighContrast/scalable/apps/shutter-panel.svg
	for size in 128x128  16x16  192x192  22x22  24x24  256x256  32x32  36x36  48x48  64x64  72x72  96x96; do \
		rm $(prefix)/share/icons/hicolor/$$size/apps/shutter.png; \
	done
	for size in 16x16 22x22 24x24; do \
		rm $(prefix)/share/icons/hicolor/$$size/apps/shutter-panel.png; \
	done
	rm $(prefix)/share/icons/hicolor/scalable/apps/shutter-panel.svg
	rm $(prefix)/share/icons/hicolor/scalable/apps/shutter.svg
	for locale in $(prefix)/share/locale/*; do \
		for mofile in shutter.mo shutter-plugins.mo shutter-upload-plugins.mo; do \
			if [ -f $$locale/LC_MESSAGES/$$mofile ]; then \
				rm $$locale/LC_MESSAGES/$$mofile; \
			fi \
		done \
	done