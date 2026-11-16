#!/bin/bash
# Reruns every test left with a `failed` marker. A marker under a test's
# `.targets/` directory belongs to a run of that test under one target, so
# the test itself is what is rerun.
for f in `find integration-tests -name failed`; do
    DIR=`dirname $f`

    case "$DIR" in
        */.targets/*) DIR=${DIR%%/.targets/*} ;;
    esac

    if [ ! -f "$DIR/disabled" ] ; then
        echo $DIR
    fi
done | sort -u | xargs dotnet ghul-test
