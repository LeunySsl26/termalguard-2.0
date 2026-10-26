#!/system/bin/sh
MODDIR=${0%/*}

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

nohup sh "$MODDIR/thermal_guard.sh" </dev/null >/dev/null 2>&1 &
