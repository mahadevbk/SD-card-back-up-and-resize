#!/usr/bin/env bash

# setting up filename of backup file
day=$(date +%F)
hostname=$(hostname -s)
bkfile_name="$hostname-$day.img"

# destination of backup file
dest="/mnt/4tb"
# Source Drive to be backed up
source_drive="/dev/mmcblk0"

echo "Backing up Source drive : $source_drive to Destination : $dest/$bkfile_name"

sudo dd if=$source_drive of=$dest/$bkfile_name  bs=1M status=progress

echo "Completed Back up of Source drive : $source_drive to Destination : $dest/$bkfile_name"

echo "Starting to minimal resize $dest/$bkfile_name ..."

orig_img_size=$(stat --printf="%s" $dest/$bkfile_name)

part_info=$(parted -m $dest/$bkfile_name unit B print)
echo -e "\n[+] partition info"
echo "----------------------------------------------"
echo -e "$part_info\n"

part_num=$(echo "$part_info" | grep ext4 | cut -d':' -f1)
part_start=$(echo "$part_info" | grep ext4 | cut -d':' -f2 | sed 's/B//g')
part_size=$(echo "$part_info" | grep ext4 | cut -d':' -f4 | sed 's/B//g')

echo -e "[+] setting up loopback\n"
loopback=$(losetup -f --show -o "$part_start" $dest/$bkfile_name)

echo "[+] checking loopback file system"
echo "----------------------------------------------"
e2fsck -f "$loopback"

echo -e "\n[+] determining minimum partition size"
min_size=$(resize2fs -P "$loopback" | cut -d':' -f2)

# next line is optional: comment out to remove $dest/$bkfile_name overhead to fs size
min_size=$(($min_size + $min_size / 100))

if [[ $part_size -lt $(($min_size * 4096 + 1048576)) ]]; then
  echo -e "\n[!] halt: image already as small as possible.\n"
  losetup -d "$loopback"
  exit
fi

echo -e "\n[+] resizing loopback fs (may take a while)"
echo "----------------------------------------------"
resize2fs -p "$loopback" "$min_size"
sleep 1

echo -e "[+] detaching loopback\n"
losetup -d "$loopback"

part_new_size=$(($min_size * 4096))
part_new_end=$(($part_start + $part_new_size))

echo -e "[+] adjusting partitions\n"
parted $dest/$bkfile_name rm "$part_num"
parted $dest/$bkfile_name unit B mkpart primary $part_start $part_new_end

free_space_start=$(parted -m $dest/$bkfile_name unit B print free | tail -1 | cut -d':' -f2 | sed 's/B//g')

echo -e "[+] truncating image\n"
truncate -s $free_space_start $dest/$bkfile_name

new_img_size=$(stat --printf="%s" $dest/$bkfile_name)
bytes_saved=$(($orig_img_size - $new_img_size))
echo -e "DONE: reduced $dest/$bkfile_name by $(($bytes_saved/1024))KiB ($((bytes_saved/1024/1024))MB)\n"

