#!/usr/bin/env bash
# Boot-time support for the existing HDD offload dataset. Never imports/mounts all pools.
set -Eeuo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
export LC_ALL=C
pool_guid=10870576030707066749
dataset=zstore/ssd-migration/bulk

case ${1:-} in
    sata-performance)
        for wwn in 0x5000c500e84abb69 0x5000c500e86adcbe; do
            dev=$(readlink -e "/dev/disk/by-id/wwn-$wwn")
            path=$(readlink -e "/sys/class/block/${dev##*/}/device")
            [[ $path =~ /host([0-9]+)/ ]]
            policy=/sys/class/scsi_host/host${BASH_REMATCH[1]}/link_power_management_policy
            printf '%s\n' max_performance > "$policy"
            [[ $(<"$policy") == max_performance ]]
        done
        ;;
    import)
        if ! zpool list -H zstore >/dev/null 2>&1; then
            zpool import -N -o cachefile=none -d /dev/disk/by-id "$pool_guid"
        fi
        [[ $(zpool get -Hp -o value guid zstore) == "$pool_guid" ]]
        [[ $(zpool get -H -o value readonly zstore) == off ]]
        [[ $(zfs get -H -o value org.quasimorphic:purpose "$dataset") == ssd-folder-offload ]]
        [[ $(zfs get -H -o value mountpoint "$dataset") == /srv/ssd-offload ]]
        [[ $(zfs get -H -o value canmount "$dataset") == noauto ]]
        # /datastore already contains unrelated files on the SSD root filesystem.
        # This legacy HDD dataset must not be automatically mounted over them.
        [[ $(zfs get -H -o value canmount zstore/datastore) == noauto ]]
        ;;
    *) echo "Usage: $0 {sata-performance|import}" >&2; exit 2 ;;
esac
