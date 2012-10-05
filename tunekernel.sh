#!/bin/bash

SSD_DEVICE_NAME=sdb
#SSD_SCSI_HOST="/sys/class/scsi_host/host5/"
#SSD_SCSI_DEVICE="/sys/class/scsi_device/5:0:0:0/device"

# set console log level.
#echo 7 4 1 7 > /proc/sys/kernel/printk

# set scsi log level.
#echo -1 > /sys/module/scsi_mod/parameters/scsi_logging_level

#echo "Scan SCSI device."
#echo "- - -" > ${SSD_SCSI_HOST}/scan
#sleep 4

echo $(( 32768 - 2048 )) > /sys/block/${SSD_DEVICE_NAME}/queue/max_sectors_kb

echo 600 > "${SSD_SCSI_DEVICE}/timeout"

#/sbin/fsck.ext4 /dev/${SSD_DEVICE_NAME}1
echo 0 > /proc/sys/kernel/hung_task_timeout_secs
/sbin/swapoff -a
/bin/mount -o discard /dev/${SSD_DEVICE_NAME}1 /mnt/bench1

