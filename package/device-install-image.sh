#!/bin/sh
# Install (or update) OpenWrt's own root image, e5linux/openwrt.ext4 on
# userdata, which boot/init starts when it is chosen (e5-os openwrt) or is the
# only system there.  Runs on the device as root, in whatever Linux it runs:
# Debian, OpenWrt in the Debian image's /openwrt, or the standalone OpenWrt
# itself; openwrt/install-standalone.sh sends it.
#
#   device-install-image.sh IMAGE.ext4.gz|URL [--try|--switch]
#
# On an SD card system (flash.py's default install, /etc/e5/sd-root) the update
# goes onto the card instead, and userdata is not touched: the new image is
# written into another root partition of the card (made in the card's free space
# the first time, /usr/libexec/e5-gpt), the configuration and the device's files
# copied in as below, and it is marked with the next generation and a trial --
# boot/init boots the highest generation, and a trial that does not come up
# leaves the next boot to the one before it.  E5_IMAGE_SIZE (bytes, unpacked) is
# needed with a URL.  --try and --switch do not apply there.
#
# The image is unpacked next to the installed one (openwrt.ext4.part) and
# renamed at the end.  The running standalone OpenWrt cannot be replaced under
# itself: its update goes to openwrt.ext4.new, which the initramfs swaps in at
# the next boot (the old one stays as openwrt.ext4.old until the next update).
#
# The new image keeps the configuration of an installed OpenWrt -- the running
# one, else the installed image, else the Debian image's /openwrt -- as
# openwrt/device-install.sh does (/etc/config, passwords, SSH keys, /etc/e5,
# the traffic records), and the packages added with apk with it, between
# images of the same OpenWrt build (carry_packages).  With no
# OpenWrt before it, it takes Debian's APN and hotspot for the first boot.
# Linux as the default boot and the misc blocks come along either way.
#
# --try boots OpenWrt once, --switch makes it the default; both reboot.
set -eu
SRC=${1:?image}
MODE=${2:-}
case "$MODE" in ''|--try|--switch) ;; *) echo "unknown option $MODE" >&2; exit 2 ;; esac

# Shared by both standalone installers. Never unlink a flock file: a waiter
# could then lock a different inode. FD 9 is held through cleanup and commit.
# BEGIN e5-upgrade-lock
lockdir=/run/e5-upgrade
[ "$(id -u)" = 0 ] || { echo 'upgrade requires root' >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo 'flock is required for a safe upgrade' >&2; exit 1; }
(umask 077; mkdir "$lockdir") 2>/dev/null || true
[ ! -L "$lockdir" ] && [ -d "$lockdir" ] &&
    [ "$(stat -c '%u:%a' "$lockdir")" = 0:700 ] || {
    echo 'unsafe upgrade lock directory' >&2; exit 1;
}
lockfile=$lockdir/lock
[ ! -L "$lockfile" ] && { [ ! -e "$lockfile" ] || {
    [ -f "$lockfile" ] && [ "$(stat -c '%u:%h' "$lockfile")" = 0:1 ];
}; } || { echo 'unsafe upgrade lock file' >&2; exit 1; }
update_umask=$(umask)
umask 077
exec 9>>"$lockfile"
umask "$update_umask"
flock -n 9 || { echo 'another system upgrade is running' >&2; exit 1; }
# END e5-upgrade-lock

# The configuration of the OpenWrt at $1 into the new root $2 (/etc/config,
# passwords, SSH keys, /etc/e5, the traffic records, the info screen's apps),
# the new image's own version files kept.
app_version() { sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1; }

# is version $1 newer than $2 (dotted numbers; no $2: yes)
version_newer() {
    awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
        for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
        exit 1 }'
}

keep_config() {
    local from=$1 N=$2 f p phone bundled
    echo "== keeping the configuration of $from"
    # Keep installed apps and their data, but retain this image's bundled phone
    # code. Otherwise an update silently restores the previous voice fixes/UI.
    phone=$(mktemp -d /tmp/e5-img.phone.XXXXXX)
    if [ -f "$N/etc/e5-infoscreen/plugins/phone/manifest.json" ]; then
        cp -a "$N/etc/e5-infoscreen/plugins/phone/." "$phone/"
    fi
    # (e5-sleep9: and the other apps this image brings, to put back where the old system has an
    # older version of them -- the installed copy would otherwise replace the image's newer one)
    bundled=$(mktemp -d /tmp/e5-img.apps.XXXXXX)
    for p in "$N"/etc/e5-infoscreen/plugins/*/manifest.json; do
        [ -f "$p" ] || continue
        p=${p%/manifest.json}; p=${p##*/}
        [ "$p" = phone ] && continue
        cp -a "$N/etc/e5-infoscreen/plugins/$p" "$bundled/$p"
    done
    for f in image-version image-form build-time; do
        cp "$N/etc/e5/$f" "/tmp/e5-img.$f" 2>/dev/null || rm -f "/tmp/e5-img.$f"
    done
    # (e5-sleep8: etc/unisoc-modem too -- the traffic records, traffic/state.json, and the SMS
    # forwarding settings, forward/; an update wiped both)
    for p in etc/config etc/shadow etc/passwd etc/group etc/dropbear etc/e5 etc/e5linux \
             etc/uhttpd.crt etc/uhttpd.key etc/vnstat etc/e5-infoscreen etc/e5-sms etc/unisoc-modem; do
        [ -e "$from/$p" ] || continue
        if [ -d "$from/$p" ] && [ -d "$N/$p" ]; then
            cp -a "$from/$p/." "$N/$p/"
        else
            rm -rf "$N/$p"
            cp -a "$from/$p" "$N/$p"
        fi
    done
    # (e5-sleep8: and what OpenWrt's own sysupgrade keeps -- each package's /lib/upgrade/keep.d list
    # and /etc/sysupgrade.conf(.d) of the old system: the Bluetooth pairings, crontabs, dnsmasq.d,
    # nftables.d, rc.local, sysctl.conf, hosts, the CPU and sound settings, LuCI's uploads ...)
    for f in "$from"/lib/upgrade/keep.d/* "$from/etc/sysupgrade.conf" "$from"/etc/sysupgrade.conf.d/*; do
        [ -f "$f" ] && sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$f"
    done | sort -u | while read -r p; do
        case "$p" in /*) ;; *) continue ;; esac
        case "$p" in *..*|/proc*|/sys*|/dev*|/tmp*|/mnt*) continue ;; esac
        p=${p%/}
        [ -e "$from$p" ] || [ -L "$from$p" ] || continue
        mkdir -p "$N${p%/*}"
        if [ -d "$from$p" ] && [ ! -L "$from$p" ]; then
            mkdir -p "$N$p" && cp -a "$from$p/." "$N$p/"
        else
            rm -rf "$N$p" && cp -a "$from$p" "$N$p"
        fi
    done
    for f in image-version image-form build-time; do
        rm -f "$N/etc/e5/$f"
        [ -f "/tmp/e5-img.$f" ] && mv "/tmp/e5-img.$f" "$N/etc/e5/$f"
    done
    # (e5-sleep8: only where the old system still has the phone: one without it had it removed --
    # every image since the first brings it -- and it stays removed)
    if [ -d "$from/etc/e5-infoscreen/plugins" ] && [ ! -f "$from/etc/e5-infoscreen/plugins/phone/manifest.json" ]; then
        rm -f "$phone/manifest.json"
        mkdir -p "$N/etc/e5-infoscreen"
        grep -qx phone "$N/etc/e5-infoscreen/removed-apps" 2>/dev/null ||
            echo phone >> "$N/etc/e5-infoscreen/removed-apps"
    fi
    if [ -f "$phone/manifest.json" ]; then
        mkdir -p "$N/etc/e5-infoscreen/plugins/phone"
        cp -a "$phone/." "$N/etc/e5-infoscreen/plugins/phone/"
    fi
    rm -rf "$phone"
    for p in "$bundled"/*/manifest.json; do
        [ -f "$p" ] || continue
        p=${p%/manifest.json}; p=${p##*/}
        f=$(app_version "$N/etc/e5-infoscreen/plugins/$p/manifest.json")
        version_newer "$(app_version "$bundled/$p/manifest.json")" "$f" || continue
        rm -rf "$N/etc/e5-infoscreen/plugins/$p"
        cp -a "$bundled/$p" "$N/etc/e5-infoscreen/plugins/$p"
        echo "   $p: $(app_version "$bundled/$p/manifest.json") from this image in place of the installed $f"
    done
    rm -rf "$bundled"
    # (e5-sleep8: the apps removed on purpose -- the plugin tool's /etc/e5-infoscreen/removed-apps,
    # kept with /etc/e5-infoscreen -- out of the new image, its own copies of them too)
    if [ -f "$N/etc/e5-infoscreen/removed-apps" ]; then
        while read -r p; do
            case "$p" in ''|*/*|.*) continue ;; esac
            grep -qx "$p" "$N/usr/share/e5-infoscreen/builtin-apps" 2>/dev/null && continue
            rm -rf "$N/etc/e5-infoscreen/plugins/$p"
            [ -L "$N/usr/share/e5-infoscreen/www/plugins/$p" ] || rm -rf "$N/usr/share/e5-infoscreen/www/plugins/$p"
            echo "   $p: removed on this system, left out"
        done < "$N/etc/e5-infoscreen/removed-apps"
    fi
    # (e5-sleep6: the apps this image has built in -- volkeys, sidekey, powermon, navbar -- not as
    # installed copies too, or the screen would put the old copy in place of the built-in one; their
    # settings, in /etc/config, stay)
    if [ -f "$N/usr/share/e5-infoscreen/builtin-apps" ]; then
        while read -r p; do
            case "$p" in ''|*/*|.*) continue ;; esac
            [ -d "$N/etc/e5-infoscreen/plugins/$p" ] || continue
            rm -rf "$N/etc/e5-infoscreen/plugins/$p"
            echo "   $p: built into this image, the installed copy left out"
        done < "$N/usr/share/e5-infoscreen/builtin-apps"
    fi
    # (never what stops an update: in an || list, set -e does not apply inside)
    carry_packages "$from" "$N" || echo "   the packages added with apk were not carried over" >&2
}

# The packages added with apk on the OpenWrt at $1, carried into the new root
# $2 (e5-sleep): those in its apk database that the new image does not have --
# what was installed by hand, with what came in with it, kmods included so the
# dependencies stay whole.  Only between images of the same OpenWrt build
# (DISTRIB_REVISION): their files are copied as they are, with the directories
# under /etc that only they use (OpenClash's /etc/openclash: subscriptions,
# its core) and their enabled services (/etc/rc.d), and their database entries,
# scripts and world lines are merged in.  A package of the image that the old
# system did not have and that shares files with a carried one was replaced
# there (dnsmasq by dnsmasq-full): it goes from the new root.  Another build:
# nothing is copied, the list is left in /etc/e5/apk-carry.list for apk add.
carry_packages() {
    local from=$1 N=$2 db=lib/apk/db/installed T f n rel_old rel_new dir
    [ -f "$from/$db" ] && [ -f "$N/$db" ] || return 0
    T=$(mktemp -d /tmp/e5-img.apk.XXXXXX) || return 0
    awk '/^P:/ { print substr($0, 3) }' "$from/$db" | sort -u > "$T/old"
    awk '/^P:/ { print substr($0, 3) }' "$N/$db" | sort -u > "$T/new"
    grep -vxF -f "$T/new" "$T/old" > "$T/add" || true
    # what the image leaves out on purpose (e5-sleep5: PPPoE, GRUB) does not come back
    if [ -s "$N/etc/e5/apk-removed.list" ]; then
        grep -vxF -f "$N/etc/e5/apk-removed.list" "$T/add" > "$T/add.k" || true
        mv "$T/add.k" "$T/add"
    fi
    if [ ! -s "$T/add" ]; then rm -rf "$T"; return 0; fi
    rel_old=$(grep '^DISTRIB_REVISION=' "$from/etc/openwrt_release" 2>/dev/null)
    rel_new=$(grep '^DISTRIB_REVISION=' "$N/etc/openwrt_release" 2>/dev/null)
    if [ -z "$rel_old" ] || [ "$rel_old" != "$rel_new" ]; then
        mkdir -p "$N/etc/e5"
        cp "$T/add" "$N/etc/e5/apk-carry.list"
        echo "== packages added with apk not carried (another OpenWrt build): $(echo $(cat "$T/add"))"
        echo "   reinstall them with: apk add \$(cat /etc/e5/apk-carry.list)"
        rm -rf "$T"
        return 0
    fi
    # what the carried packages own (D dir, F file), and who owns what in the new root
    awk -v list="$T/add" '
        BEGIN { while ((getline l < list) > 0) want[l] = 1 }
        /^P:/ { keep = (substr($0, 3) in want) }
        /^F:/ { d = substr($0, 3); if (keep) print "D " d }
        /^R:/ { if (keep) print "F " d "/" substr($0, 3) }' "$from/$db" > "$T/files"
    awk '/^P:/ { p = substr($0, 3) } /^F:/ { d = substr($0, 3) }
         /^R:/ { print d "/" substr($0, 3) " " p }' "$N/$db" > "$T/owned"
    # the image's packages the old system did not have, sharing a file with a carried one: replaced
    grep -vxF -f "$T/old" "$T/new" > "$T/newonly" || true
    awk -v files="$T/files" -v only="$T/newonly" '
        BEGIN { while ((getline l < only) > 0) o[l] = 1
                while ((getline l < files) > 0) if (substr(l, 1, 2) == "F ") c[substr(l, 3)] = 1 }
        ($1 in c) && ($2 in o) { print $2 }' "$T/owned" | sort -u > "$T/drop"
    # files of the kept image packages are not overwritten
    awk -v drop="$T/drop" 'BEGIN { while ((getline l < drop) > 0) x[l] = 1 }
        !($2 in x) { print $1 }' "$T/owned" | sort -u > "$T/kept"
    # the dropped packages: their files not wanted by a carried one go
    awk -v drop="$T/drop" -v files="$T/files" '
        BEGIN { while ((getline l < drop) > 0) x[l] = 1
                while ((getline l < files) > 0) if (substr(l, 1, 2) == "F ") c[substr(l, 3)] = 1 }
        ($2 in x) && !($1 in c) { print $1 }' "$T/owned" | while read -r f; do
        rm -f "$N/$f" || true
    done
    while read -r n; do rm -f "$N/lib/apk/packages/$n.list" "$N/lib/apk/packages/$n.conffiles"; done < "$T/drop"
    # the files, as they are on the old system (a uci-defaults that has run is gone there)
    grep '^D ' "$T/files" | cut -c3- | while read -r dir; do mkdir -p "$N/$dir" || true; done
    grep '^F ' "$T/files" | cut -c3- | grep -vxF -f "$T/kept" | while read -r f; do
        { [ -e "$from/$f" ] || [ -L "$from/$f" ]; } || continue
        rm -f "$N/$f" 2>/dev/null || true
        cp -a "$from/$f" "$N/$f" || echo "   could not copy /$f" >&2
    done
    # their own directories under /etc, whole (runtime data), and their enabled services
    grep '^F etc/' "$T/files" | cut -d/ -f2 | sort -u | while read -r dir; do
        case "$dir" in config|init.d|rc.d|uci-defaults|hotplug.d|apk|modules.d|modules-boot.d|e5|e5linux|e5-*|*.*) continue ;; esac
        [ -d "$from/etc/$dir" ] || continue
        grep -q "^etc/$dir/" "$T/kept" && continue
        mkdir -p "$N/etc/$dir" && cp -a "$from/etc/$dir/." "$N/etc/$dir/" || echo "   could not copy /etc/$dir" >&2
    done
    grep '^F etc/init.d/' "$T/files" | cut -d/ -f3 | while read -r n; do
        for f in "$from"/etc/rc.d/[SK][0-9][0-9]"$n"; do
            [ -L "$f" ] || continue
            cp -a "$f" "$N/etc/rc.d/" || true
        done
    done
    # the database: the dropped packages out, the carried ones in
    awk -v drop="$T/drop" 'BEGIN { while ((getline l < drop) > 0) x[l] = 1; RS = ""; ORS = "\n\n" }
        { split($0, a, "\n"); for (i in a) if (a[i] ~ /^P:/) p = substr(a[i], 3) }
        !(p in x)' "$N/$db" > "$T/db"
    awk -v list="$T/add" 'BEGIN { while ((getline l < list) > 0) w[l] = 1; RS = ""; ORS = "\n\n" }
        { split($0, a, "\n"); for (i in a) if (a[i] ~ /^P:/) p = substr(a[i], 3) }
        p in w' "$from/$db" >> "$T/db"
    cat "$T/db" > "$N/$db"
    # their scripts (<name>-<version>.<checksum>.<action>)
    if [ -f "$from/lib/apk/db/scripts.tar.gz" ] && [ -f "$N/lib/apk/db/scripts.tar.gz" ]; then
        awk -v list="$T/add" 'BEGIN { while ((getline l < list) > 0) w[l] = 1 }
            /^P:/ { p = substr($0, 3) } /^V:/ { if (p in w) print p "-" substr($0, 3) "." }' "$from/$db" > "$T/prefix"
        mkdir -p "$T/s"
        tar -xzf "$N/lib/apk/db/scripts.tar.gz" -C "$T/s"
        tar -tzf "$from/lib/apk/db/scripts.tar.gz" | while read -r f; do
            while read -r n; do case "$f" in "$n"*) echo "$f" ;; esac; done < "$T/prefix"
        done > "$T/scripts"
        [ ! -s "$T/scripts" ] || tar -xzf "$from/lib/apk/db/scripts.tar.gz" -C "$T/s" -T "$T/scripts" || true
        (cd "$T/s" && tar -czf "$T/scripts.tar.gz" *) && cat "$T/scripts.tar.gz" > "$N/lib/apk/db/scripts.tar.gz"
    fi
    # world: the dropped out, the carried ones the old system asked for in
    if [ -f "$N/etc/apk/world" ]; then
        awk -v drop="$T/drop" 'BEGIN { while ((getline l < drop) > 0) x[l] = 1 }
            { n = $0; sub(/[<>=~].*/, "", n) } !(n in x)' "$N/etc/apk/world" > "$T/world"
        [ -f "$from/etc/apk/world" ] && awk -v list="$T/add" 'BEGIN { while ((getline l < list) > 0) w[l] = 1 }
            { n = $0; sub(/[<>=~].*/, "", n) } n in w' "$from/etc/apk/world" >> "$T/world"
        cat "$T/world" > "$N/etc/apk/world"
    fi
    echo "== packages added with apk carried over: $(echo $(cat "$T/add"))"
    [ -s "$T/drop" ] && echo "   replaced there, so gone from the image: $(echo $(cat "$T/drop"))"
    rm -rf "$T"
    return 0
}

# The device's own files (firmware, the Android vendor subset) as a tar on
# stdout, read through a plain (non-recursive) bind of the root that has them --
# the Debian image for the directory form, / otherwise: the vendor chroot has
# /proc, /sys and /dev mounted inside it while the baseband runs, and a tar of
# the live tree walked into those.  Nothing (and false) when this system has none.
VIEW=/tmp/e5-img.view
device_files_tar() {
    local src=/ list rc=1
    [ -f /mnt/e5-disk/usr/lib/firmware/wcnmodem.bin ] && src=/mnt/e5-disk
    mkdir -p "$VIEW" && mount --bind "$src" "$VIEW"
    if [ -f "$VIEW/lib/firmware/wcnmodem.bin" ] && [ -x "$VIEW/opt/e5/android/vendor/bin/modem_control" ]; then
        list=$(cd "$VIEW" && for f in lib/firmware/wcnmodem.bin lib/firmware/gnssmodem.bin \
                   lib/firmware/wifi_board_config*.ini lib/firmware/tsx_data lib/firmware/l_agdsp_a.img \
                   lib/firmware/audio_structure lib/firmware/dsp_vbc lib/firmware/cvs \
                   lib/firmware/aw87xxx_acf.bin lib/firmware/sprd opt/e5/android; do
                   [ -e "$f" ] && echo "$f"; done)
        (cd "$VIEW" && tar -cf - $list) && rc=0
    fi
    umount "$VIEW"
    return $rc
}

# ------------------------------------------------------------ the SD card
card_update() {
    local rootdev disk curn cur gpt size need t n start end name g best bestgen lo next tries
    rootdev=$(awk '$2 == "/" && $1 ~ /^\/dev\/mmcblk[0-9]+p[0-9]+$/ { d = $1 } END { print d }' /proc/mounts)
    [ -n "$rootdev" ] || { echo "the card's root partition is not mounted as /" >&2; exit 1; }
    disk=${rootdev%p*} curn=${rootdev##*p}
    gpt=$(dirname "$0")/e5-gpt
    [ -f "$gpt" ] || gpt=/usr/libexec/e5-gpt
    [ -f "$gpt" ] || { echo "no e5-gpt (the card's partition table)" >&2; exit 1; }
    cur=$(cat /etc/e5/sd-gen 2>/dev/null || :); case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
    # On a registered card this updater owns OpenWrt's slots only. Verify the
    # running partition's registration before changing any table or root.
    local meta=/mnt/e5-boot current_uuid registry_slot= registry_target=
    if [ -f "$meta/format" ]; then
        . /opt/e5/e5-sd-registry
        sd_registry_valid "$meta" || { echo "invalid SD system registry" >&2; exit 1; }
        [ "$(cat /etc/e5/sd-system 2>/dev/null || echo openwrt)" = openwrt ] || {
            echo "the OpenWrt updater cannot update a foreign system" >&2; exit 1;
        }
        current_uuid=$(ucode "$gpt" uuid "$disk" "$curn") || exit 1
        for registry_slot in a b; do
            [ "$(cat "$meta/systems/openwrt/$registry_slot" 2>/dev/null)" = "$current_uuid" ] || continue
            [ "$registry_slot" = a ] && registry_target=b || registry_target=a
            break
        done
        [ -n "$registry_target" ] || { echo "the current OpenWrt root is not registered" >&2; exit 1; }
    fi
    size=${E5_IMAGE_SIZE:-}
    if [ -z "$size" ]; then
        case "$SRC" in
            http://*|https://*) echo "E5_IMAGE_SIZE (the unpacked size) is needed with a URL" >&2; exit 2 ;;
        esac
        # (gzip's last four bytes: the unpacked size, modulo 4 GiB)
        size=$(tail -c 4 "$SRC" | od -An -tu4 | tr -d ' ')
    fi
    need=$(( (size + 511) / 512 ))
    echo "== the card: $disk, running from partition $curn (generation $cur), the image $((size >> 20)) MiB"

    # The partition to write: another root of the card (e5root*) that holds the
    # image -- the oldest generation, a failed trial or an unmarked one first;
    # never the running one, never a partition of another name.
    lo=$(losetup -f)
    best= bestgen=
    gen_at() {
        losetup -r -o $(($1 * 512)) "$lo" "$disk" 2>/dev/null || { echo -1; return; }
        mkdir -p "$OLD_ROOT"
        if mount -t ext4 -o ro,noload "$lo" "$OLD_ROOT" 2>/dev/null; then
            if [ -f "$OLD_ROOT/etc/e5/sd-system" ] &&
               [ "$(cat "$OLD_ROOT/etc/e5/sd-system")" != openwrt ]; then
                echo foreign
            elif [ ! -f "$OLD_ROOT/etc/openwrt_release" ]; then
                echo foreign
            elif [ ! -f "$OLD_ROOT/etc/e5/sd-root" ] || [ "$(cat "$OLD_ROOT/etc/e5/sd-trial" 2>/dev/null)" = 0 ]; then
                echo -1
            else
                g=$(cat "$OLD_ROOT/etc/e5/sd-gen" 2>/dev/null || :); case "$g" in ''|*[!0-9]*) g=0 ;; esac
                echo "$g"
            fi
            umount "$OLD_ROOT"
        else
            echo -1
        fi
        losetup -d "$lo"
    }
    t=$(ucode "$gpt" list "$disk") || exit 1
    while read -r n start end name; do
        [ "$n" = "$curn" ] && continue
        case "$name" in e5root*) ;; *) continue ;; esac
        [ $((end - start + 1)) -ge "$need" ] || continue
        g=$(gen_at "$start")
        [ "$g" != foreign ] || { echo "   partition $n ($name): foreign system, skipped"; continue; }
        echo "   partition $n ($name, $(( (end - start + 1) >> 11 )) MiB): generation $g"
        if [ -z "$best" ] || [ "$g" -lt "$bestgen" ]; then best="$n $start $end" bestgen=$g; fi
    done <<EOT
$t
EOT
    if [ -z "$best" ]; then
        # (room for a larger image later: 256 MiB past this one)
        n=2; while echo "$t" | grep -q " e5root$n\$"; do n=$((n + 1)); done
        best=$(ucode "$gpt" add "$disk" "e5root$n" $((need + 524288))) || exit 1
        echo "== a new root partition on the card: e5root$n ($best)"
    fi
    set -- $best
    n=$1 start=$2 end=$3
    [ $((start % 2048)) = 0 ] || { echo "partition $n does not start on a MiB" >&2; exit 1; }

    # the partition is not bootable while it is written: its superblock goes first
    echo "== writing the image into partition $n"
    dd if=/dev/zero of="$disk" bs=1048576 seek=$((start / 2048)) count=4 conv=fsync 2>/dev/null
    rm -f /tmp/e5-img.fail
    case "$SRC" in
        http://*|https://*) { wget -q -O - "$SRC" || touch /tmp/e5-img.fail; } | gunzip -c ;;
        *) gunzip -c "$SRC" ;;
    esac | dd of="$disk" bs=1048576 seek=$((start / 2048)) conv=fsync 2>/tmp/e5-img.dd ||
        { cat /tmp/e5-img.dd >&2; echo "writing the card failed" >&2; exit 1; }
    [ ! -e /tmp/e5-img.fail ] || { rm -f /tmp/e5-img.fail; echo "download failed" >&2; exit 1; }

    losetup -o $((start * 512)) "$lo" "$disk"
    mkdir -p "$NEW_ROOT"
    mount -t ext4 "$lo" "$NEW_ROOT" ||
        { losetup -d "$lo"; echo "the written partition does not mount" >&2; exit 1; }
    N=$NEW_ROOT
    trap 'umount "$NEW_ROOT" 2>/dev/null; losetup -d "$lo" 2>/dev/null' EXIT
    [ -x "$N/sbin/init" ] && [ -f "$N/etc/openwrt_release" ] || { echo "not an OpenWrt image" >&2; exit 1; }
    keep_config / "$N"
    if [ -n "$registry_target" ]; then
        # The new image may predate SD selection; keep the shared selector
        # until all released images carry registry format 1 support.
        cp /opt/e5/e5-os /opt/e5/e5-sd-registry "$N/opt/e5/"
        cp "$gpt" "$N/usr/libexec/e5-gpt"
    fi
    # (marked last, below: until then the partition is no candidate)
    rm -f "$N/etc/e5/sd-root" "$N/etc/e5/sd-trial"
    if [ ! -f "$N/lib/firmware/wcnmodem.bin" ]; then
        if device_files_tar > /tmp/e5-img.dft; then
            tar -xf /tmp/e5-img.dft -C "$N"
            sha256sum /tmp/e5-img.dft | cut -d' ' -f1 > "$N/etc/e5/device-files.stamp"
            echo "== the device's files copied in"
        else
            rm -f /tmp/e5-img.dft
            echo "the image has no firmware or vendor subset, and this system has none to give" >&2
            exit 1
        fi
        rm -f /tmp/e5-img.dft
    fi
    mkdir -p "$N/etc/e5linux"
    cp /run/e5linux/misc-bc-slot-a.bin /run/e5linux/misc-bc-slot-b-trial.bin "$N/etc/e5linux/" 2>/dev/null || true
    next=$((cur + 1))
    echo "$next" > "$N/etc/e5/sd-gen"
    echo 1 > "$N/etc/e5/sd-trial"
    cp /etc/e5/sd-root "$N/etc/e5/sd-root"
    echo openwrt > "$N/etc/e5/sd-system"
    ver=$(cat "$N/etc/e5/image-version" 2>/dev/null || echo "?")
    sync
    umount "$NEW_ROOT" && losetup -d "$lo"
    trap - EXIT
    if [ -n "$registry_target" ]; then
        uuid=$(ucode "$gpt" uuid "$disk" "$n") || exit 1
        printf '%s\n' "$uuid" > "$meta/systems/openwrt/.$registry_target.tmp"
        sync
        mv "$meta/systems/openwrt/.$registry_target.tmp" "$meta/systems/openwrt/$registry_target"
    fi
    sync
    echo "installed: card partition $n ($ver, generation $next), started at the next boot"
    echo "   (its first boot is a trial: one that does not come up returns to partition $curn)"
    grep -qs sd-gen /run/e5linux/init-features ||
        echo "   the boot image in use predates card updates: flash this package's boot image too"
    exit 0
}

D=/mnt/e5-data
DIR=$D/e5linux IMG=$D/e5linux/openwrt.ext4
PART=$IMG.part NEW_ROOT=/tmp/e5-img.new OLD_ROOT=/tmp/e5-img.old
[ -f /etc/e5/sd-root ] && [ -f /etc/openwrt_release ] && card_update

# userdata: the initramfs leaves it at /mnt/e5-data; one that predates that
# keeps it to itself, and the partition is mounted a second time (the same
# f2fs, not a copy)
if ! grep -qs " $D " /proc/mounts; then
    dev=
    for u in /sys/class/block/mmcblk*p*/uevent; do
        grep -qx PARTNAME=userdata "$u" 2>/dev/null && dev=/dev/$(basename "$(dirname "$u")")
    done
    [ -n "$dev" ] || { echo "no userdata partition" >&2; exit 1; }
    mkdir -p "$D"
    mount -t f2fs -o noatime "$dev" "$D"
    echo "== mounted userdata ($dev) at $D"
fi
mkdir -p "$DIR"

# the running root: the image itself when OpenWrt runs from it
running_image=
if [ -f /etc/openwrt_release ] && [ "$(cat /etc/e5/image-form 2>/dev/null)" = standalone ]; then
    running_image=1
fi

cleanup() {
    umount "$NEW_ROOT" 2>/dev/null || true
    umount "$OLD_ROOT" 2>/dev/null || true
    rm -f "$PART"
}
trap cleanup EXIT

avail=$(df -Pk "$D" | awk 'NR == 2 { print $4 }')
[ "$avail" -gt 1572864 ] || { echo "less than 1.5 GiB free on userdata" >&2; exit 1; }
rm -f "$DIR/openwrt.ext4.old"

echo "== unpacking into $PART"
rm -f "$PART" "$PART.fail"
case "$SRC" in
    http://*|https://*) { wget -q -O - "$SRC" || touch "$PART.fail"; } | gunzip -c > "$PART" ;;
    *) gunzip -c "$SRC" > "$PART" ;;
esac
[ ! -e "$PART.fail" ] || { rm -f "$PART.fail"; echo "download failed" >&2; exit 1; }

mkdir -p "$NEW_ROOT" "$OLD_ROOT"
mount -t ext4 -o loop "$PART" "$NEW_ROOT"
[ -x "$NEW_ROOT/sbin/init" ] && [ -f "$NEW_ROOT/etc/openwrt_release" ] ||
    { echo "not an OpenWrt image" >&2; exit 1; }

# the OpenWrt whose configuration the new image keeps
from=
if [ -f /etc/openwrt_release ]; then
    from=/
elif [ -f "$IMG" ] && mount -t ext4 -o loop,ro "$IMG" "$OLD_ROOT" 2>/dev/null; then
    from=$OLD_ROOT
elif [ -d /openwrt/etc/config ]; then
    from=/openwrt
fi

N=$NEW_ROOT
[ -n "$from" ] && keep_config "$from" "$N"
umount "$OLD_ROOT" 2>/dev/null || true

if [ ! -f "$N/etc/e5/install.conf" ] && command -v nmcli >/dev/null 2>&1; then
    echo "== settings from Debian"
    # nmcli -g escapes ":" and "\\" in what it prints
    get() { nmcli "$@" 2>/dev/null | sed 's/\\\(.\)/\1/g' || true; }
    apn=$(get -g gsm.apn connection show Mobile)
    ssid=$(get -g 802-11-wireless.ssid connection show Hotspot)
    key=$(get -s -g 802-11-wireless-security.psk connection show Hotspot)
    chan=$(get -g 802-11-wireless.channel connection show Hotspot)
    q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
    mkdir -p "$N/etc/e5"
    (
        umask 077
        echo "# from the Debian image's NetworkManager profiles at install (openwrt/device-install-image.sh)"
        echo "E5_APN=$(q "$apn")"
        echo "E5_WIFI_SSID=$(q "${ssid:-E5-Linux}")"
        echo "E5_WIFI_KEY=$(q "$key")"
        echo "E5_WIFI_CHANNEL=$(q "${chan:-149}")"
    ) > "$N/etc/e5/install.conf"
    chmod 600 "$N/etc/e5/install.conf"
    echo "   apn=${apn:-(none)} ssid=${ssid:-E5-Linux} channel=${chan:-149} key=$([ -n "$key" ] && echo set || echo none)"
fi

# An image built without the device's files (E5_DEVICE_FILES=0) takes them
# from userdata's device-files.tar, which boot/init unpacks as well; made here
# from this system's own when there is none yet (device_files_tar).
DFT=$DIR/device-files.tar
if [ ! -f "$N/lib/firmware/wcnmodem.bin" ] && [ ! -f "$DFT" ]; then
    if device_files_tar > "$DFT.part"; then
        echo "== the device's files from this system -> $DFT"
        mv "$DFT.part" "$DFT"
    else
        rm -f "$DFT.part"
    fi
fi
if [ ! -f "$N/lib/firmware/wcnmodem.bin" ]; then
    if [ -f "$DFT" ]; then
        tar -xf "$DFT" -C "$N"
        sha256sum "$DFT" | cut -d' ' -f1 > "$N/etc/e5/device-files.stamp"
        echo "== the device's files unpacked into the image"
    else
        # (no modem and no Wi-Fi without them: better the old system than that)
        echo "the image has no firmware or vendor subset, and there is no $DFT: not installed" >&2
        exit 1
    fi
fi

mkdir -p "$N/etc/e5linux"
[ -f /etc/e5linux/default-boot ] && [ ! -f "$N/etc/e5linux/default-boot" ] &&
    cp /etc/e5linux/default-boot "$N/etc/e5linux/default-boot"
cp /run/e5linux/misc-bc-slot-a.bin /run/e5linux/misc-bc-slot-b-trial.bin "$N/etc/e5linux/" 2>/dev/null || true
ver=$(cat "$N/etc/e5/image-version" 2>/dev/null || echo "?")
umount "$NEW_ROOT"

if [ -n "$running_image" ]; then
    mv "$PART" "$IMG.new"
    echo "installed: $IMG.new ($ver), swapped in at the next boot"
else
    mv "$PART" "$IMG"
    echo "installed: $IMG ($ver)"
fi
sync

grep -qs openwrt-image /run/e5linux/init-features || {
    echo "the boot image in use predates OpenWrt images of their own: flash a newer one" >&2
    echo "(boot/flash-from-linux.sh) before booting it" >&2
    exit 0
}
case "$MODE" in
    --try)    echo openwrt > "$DIR/boot-os-next"; sync; reboot ;;
    --switch) rm -f "$DIR/boot-os-next"; echo openwrt > "$DIR/boot-os"; sync; reboot ;;
    '')       [ -n "$running_image" ] && echo "reboot to start it" ||
                  echo "boot it with: e5-os openwrt --once (one boot) or e5-os openwrt, then reboot" ;;
esac
