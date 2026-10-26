#!/system/bin/sh
# customize.sh - Verificación de dispositivo e instalación de TermalGuard 2.0
SKIPUNZIP=0

type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
type abort >/dev/null 2>&1 || abort() {
    ui_print "$1"
    [ -n "$MODPATH" ] && rm -rf "$MODPATH" 2>/dev/null
    exit 1
}

DEVICE="$(getprop ro.product.device)"
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.product.odm.device)"
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.product.board)"

HARDWARE_SKU="$(getprop ro.boot.product.hardware.sku)"

MODEL="$(getprop ro.product.model)"
[ -z "$MODEL" ] && MODEL="$(getprop ro.product.odm.model)"

MARKETNAME="$(getprop ro.product.marketname)"
[ -z "$MARKETNAME" ] && MARKETNAME="$(getprop ro.product.odm.marketname)"
[ -z "$MARKETNAME" ] && MARKETNAME="$(getprop ro.product.bootimage.marketname)"

IS_POCO_F7_PRO=0

if [ "$DEVICE" = "zorn" ] || [ "$HARDWARE_SKU" = "zorn" ]; then
    case "$(echo "$MARKETNAME" | tr '[:upper:]' '[:lower:]')" in
        *"poco f7 pro"*)
            IS_POCO_F7_PRO=1
            ;;
    esac
    case "$MODEL" in
        24117RK2CG|*"POCO F7 Pro"*|*"poco f7 pro"*)
            IS_POCO_F7_PRO=1
            ;;
    esac
fi

if [ "$IS_POCO_F7_PRO" -ne 1 ]; then
    ui_print "**************************************************"
    ui_print "! ERROR: Dispositivo no compatible"
    ui_print "! Detectado : ${MARKETNAME:-$MODEL} (${DEVICE:-desconocido})"
    ui_print "! Requerido : POCO F7 Pro (zorn / 24117RK2CG)"
    ui_print "! La instalación de TermalGuard 2.0 fue cancelada."
    ui_print "**************************************************"
    abort "! Instalación abortada: Este módulo es exclusivo para el POCO F7 Pro."
fi

ui_print "**************************************************"
ui_print "- TermalGuard 2.0"
ui_print "- Dispositivo verificado: POCO F7 Pro ($DEVICE / $MODEL)"
ui_print "**************************************************"

chmod 0755 "$MODPATH/service.sh" "$MODPATH/thermal_guard.sh" "$MODPATH/uninstall.sh" 2>/dev/null

if [ ! -d "$MODPATH/webui" ] && [ ! -L "$MODPATH/webui" ]; then
    ln -sf webroot "$MODPATH/webui"
fi

ui_print "- Módulo instalado correctamente."
