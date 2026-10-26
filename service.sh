#!/system/bin/sh
MODDIR=${0%/*}

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

DEVICE="$(getprop ro.product.device)"
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.product.odm.device)"
HARDWARE_SKU="$(getprop ro.boot.product.hardware.sku)"
MODEL="$(getprop ro.product.model)"
MARKETNAME="$(getprop ro.product.marketname)"
[ -z "$MARKETNAME" ] && MARKETNAME="$(getprop ro.product.odm.marketname)"

if [ "$DEVICE" != "zorn" ] && [ "$HARDWARE_SKU" != "zorn" ]; then
  exit 0
fi

case "$(echo "$MARKETNAME $MODEL" | tr '[:upper:]' '[:lower:]')" in
  *"poco f7 pro"*|*24117rk2cg*) ;;
  *) exit 0 ;;
esac

nohup sh "$MODDIR/thermal_guard.sh" </dev/null >/dev/null 2>&1 &
