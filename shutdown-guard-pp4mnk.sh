#!/bin/sh
# Shutdown Guard 1.1 - modded by pp4mnk - MIT license
# Install: sh shutdown-guard-pp4mnk.sh --install
# Remove: sh shutdown-guard-pp4mnk.sh --remove
set -u
APP=/usr/local/lib/shutdown-guard/guard.sh
STATE=/var/lib/shutdown-guard
fail() { printf '%s\n' "$*" >&2; exit 1; }
confirm() {
    command -v yad >/dev/null 2>&1 || return 1
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
    case "${LANG:-en}" in
      es*) title='Confirmar apagado / reinicio'; text='Tienes 15 segundos para pulsar Confirm.\nSin confirmación se cancela la operación.\n¿Has guardado los archivos que tienes en RAM?'; cancel='Cancelar' ;;
      *) title='Confirm shutdown / reboot'; text='You have 15 seconds to press Confirm.\nWithout confirmation the operation is cancelled.\nHave you saved the files you are keeping in RAM?'; cancel='Cancel' ;;
    esac
    # Only the dedicated Confirm button returns 42. Timeout, Escape,
    # window close, missing display and all errors fail closed.
    # Clear YAD_OPTIONS so user defaults cannot change timeout/buttons.
    YAD_OPTIONS= yad --title="$title" --text="$text" --image=dialog-warning \
      --width=500 --center --on-top --timeout=15 --timeout-indicator=top \
      --button="$cancel:1" --button='Confirm:42' --default-button=1
    [ "$?" -eq 42 ]
}
case "${1:---auto}" in
 --auto)
    command -v yad >/dev/null 2>&1 || fail 'Falta YAD. Instala yad desde el gestor de paquetes.'
    if [ -f "$APP" ] && grep -q 'SHUTDOWN-GUARD-PP4MNK' /usr/bin/wmpoweroff 2>/dev/null && grep -q 'SHUTDOWN-GUARD-PP4MNK' /usr/bin/wmreboot 2>/dev/null; then
        YAD_OPTIONS= yad --title='Shutdown Guard' --text='La protección ya está instalada.\nAhora se abrirá una prueba que NO apaga el equipo.' --button='OK:0' --center
        sh "$0" --test
        exit $?
    fi
    report=$(mktemp) || fail 'No se puede crear el archivo temporal.'
    if sh "$0" --install > "$report" 2>&1; then
        rm -f "$report"
        YAD_OPTIONS= yad --title='Shutdown Guard instalado' --text='Instalación terminada. No necesitas reiniciar.\nApagar y Reiniciar requieren Confirm antes de 15 segundos.\nAhora se abrirá una prueba que NO apaga el equipo.' --button='OK:0' --center
        sh "$0" --test
    else
        YAD_OPTIONS= yad --title='No se pudo instalar' --text-info --filename="$report" --width=600 --height=280 --button='Cerrar:0' --center
        cat "$report" >&2
        rm -f "$report"
        exit 1
    fi
    exit 0
    ;;
 --confirm) confirm; exit $? ;;
 --test)
    if confirm; then message='PRUEBA: has confirmado. En uso real continuaría el apagado o reinicio.'
    else message='PRUEBA: operación cancelada. El equipo seguiría encendido.'; fi
    printf '%s\n' "$message"
    command -v yad >/dev/null 2>&1 && YAD_OPTIONS= yad --title='Prueba finalizada' --text="$message\nEsta prueba nunca apaga ni reinicia el equipo." --button='OK:0' --center
    exit 0 ;;

 --install)
    [ "$(id -u)" = 0 ] || fail 'Run as root.'
    command -v yad >/dev/null 2>&1 || fail 'YAD is required. Install yad with your package manager first. Nothing changed.'
    [ ! -e "$STATE" ] || fail 'Already installed, or a backup exists. Remove first.'
    # Validate BOTH commands before changing anything. Only conventional shell scripts.
    for name in wmpoweroff wmreboot; do
        path=/usr/bin/$name
        [ -f "$path" ] && [ ! -L "$path" ] || fail "Unsupported layout: $path must be a regular shell script. Nothing changed."
        head -n 1 "$path" | LC_ALL=C grep -Eq '^#![[:space:]]*/bin/(a|ba|da)?sh([[:space:]]|$)' || fail "Unsupported interpreter in $path. Nothing changed."
        grep -q 'SHUTDOWN-GUARD-PP4MNK' "$path" && fail "Existing guard in $path."
    done
    mkdir -p "$STATE" "${APP%/*}" || fail 'Cannot create directories.'
    chmod 700 "$STATE"
    cp -p /usr/bin/wmpoweroff "$STATE/wmpoweroff" && cp -p /usr/bin/wmreboot "$STATE/wmreboot" || fail 'Backup failed; no shutdown scripts changed.'
    cp "$0" "$APP" && chmod 755 "$APP" || fail 'Cannot install guard.'
    rollback() {
        cp -p "$STATE/wmpoweroff" /usr/bin/wmpoweroff
        cp -p "$STATE/wmreboot" /usr/bin/wmreboot
        echo 'Installation interrupted: original scripts restored; backups retained.' >&2
        exit 1
    }
    trap rollback HUP INT TERM
    for name in wmpoweroff wmreboot; do
        path=/usr/bin/$name
        tmp=$(mktemp /usr/bin/.shutdown-guard.XXXXXX) || rollback
        { head -n 1 "$STATE/$name"; printf '%s\n' '# SHUTDOWN-GUARD-PP4MNK' '"/usr/local/lib/shutdown-guard/guard.sh" --confirm || exit 0'; tail -n +2 "$STATE/$name"; } > "$tmp" || rollback
        chmod 755 "$tmp" && mv -f "$tmp" "$path" || rollback
    done
    trap - HUP INT TERM
    echo 'Installed. Shutdown and reboot now require Confirm within 15 seconds. No restart needed.'
    echo 'Safe preview: sh /usr/local/lib/shutdown-guard/guard.sh --test'
    echo 'Uninstall: sh /usr/local/lib/shutdown-guard/guard.sh --remove'
    ;;
 --remove)
    [ "$(id -u)" = 0 ] || fail 'Run as root.'
    for name in wmpoweroff wmreboot; do
        [ -f "$STATE/$name" ] || fail "Missing backup: $name. Nothing changed."
        # Do not overwrite unrelated updates made since installation.
        expected=$(mktemp) || fail 'Cannot make temporary file.'
        { head -n 1 "$STATE/$name"; printf '%s\n' '# SHUTDOWN-GUARD-PP4MNK' '"/usr/local/lib/shutdown-guard/guard.sh" --confirm || exit 0'; tail -n +2 "$STATE/$name"; } > "$expected"
        cmp -s "$expected" "/usr/bin/$name"; result=$?
        rm -f "$expected"
        [ "$result" = 0 ] || fail "Changed since installation: /usr/bin/$name. Backups retained in $STATE; automatic removal stopped."
    done
    for name in wmpoweroff wmreboot; do cp -p "$STATE/$name" "/usr/bin/$name" || fail 'Restore failed; backups retained.'; done
    rm -f "$STATE/wmpoweroff" "$STATE/wmreboot"
    rmdir "$STATE"
    rm -f "$APP"
    rmdir "${APP%/*}"
    echo 'Removed; original shutdown scripts restored.'
    ;;
 *) printf '%s\n' 'Shutdown Guard 1.1 - pp4mnk' 'Use --install, --test (never shuts down), or --remove.' ;;
esac
