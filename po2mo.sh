#!/bin/bash

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

POPATH=$SCRIPTPATH/share/shutter/resources/po
MOPATH=$SCRIPTPATH/share/locale

if [ ! -d $MOPATH ]
then
	CREATEFOLDERS=1
fi

for POFOLDER in $POPATH/*
do
	for POFILE in ${POFOLDER}/*.po
	do
		LOCALE=$(echo $(basename $POFILE) | cut -d"." -f1)
		if [ $CREATEFOLDERS -eq 1 ]
		then
			mkdir -p $MOPATH/$LOCALE/LC_MESSAGES
		fi
		MOFILE=$(basename $POFOLDER)".mo"
		msgfmt -o $MOPATH/$LOCALE/LC_MESSAGES/$MOFILE $POFILE
	done
done