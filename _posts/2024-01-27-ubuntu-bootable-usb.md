---
title: Ubuntu USB Stick with Encrypted Partition
date: 2024-01-27 04:20:00
categories: [Code Snippets]
tags: [ubuntu, linux, usb]     # TAG names should always be lowercase
---

## Introduction

Here's a step-by-step guide on how to create a bootable Ubuntu 20.04 USB stick with an encrypted persistent partition. 

Please replace `/dev/sdc` with your actual USB device if it's different.

## Preparing The USB Stick

Download the Ubuntu 20.04 `.iso` file:

```bash
wget https://releases.ubuntu.com/focal/ubuntu-20.04.6-desktop-amd64.iso
```

Write the ISO file to the USB drive and make sure to replace `/dev/sdc` with your USB device:

```bash
sudo dd if=ubuntu-20.04.6-desktop-amd64.iso of=/dev/sdc bs=4M status=progress 
```

Now, let's create an encrypted persistent partition on the remaining space of the USB drive.

First, find out the end of the Ubuntu partition on the USB drive:

```bash
sudo fdisk -l /dev/sdc
```

Note down the "End" sector of the partition.

Now, create a new partition for persistence:

```bash
sudo fdisk /dev/sdc
```

In the `fdisk` prompt, follow these steps:

- Press `d` to delete a partition.
- When asked which partition to delete, enter `2`.
- Press `n` to create a new partition.
- Press `p` for a primary partition.
- Press `2` for the partition number.
- Press `Enter` to accept the default `First sector`. This should be the next available sector after the end of `/dev/sdc1`.
- Press `Enter` again to accept the default `Last sector`, which will use the rest of the space on the USB stick.
- Press `w` to write the changes.

Setup LUKS on the new partition:

```bash
sudo cryptsetup luksFormat /dev/sdc2
```

You will be asked to confirm and set a passphrase.

Open the encrypted partition:

```bash
sudo cryptsetup luksOpen /dev/sdc2 persistence
```

Create an ext4 filesystem on the partition:

```bash
sudo mkfs.ext4 /dev/mapper/persistence
```

Mount the partition and create a configuration file for persistence:

```bash
sudo mkdir -p /mnt/my_usb
sudo mount /dev/mapper/persistence /mnt/my_usb
echo "/ union" | sudo tee /mnt/my_usb/persistence.conf
```

Unmount and close everything:

```bash
sudo umount /dev/mapper/persistence
sudo cryptsetup luksClose /dev/mapper/persistence
```


You should now have a bootable USB stick with Ubuntu 20.04 and an encrypted persistent partition. 
You will be asked for the passphrase each time you boot from the USB stick.

Please note that running an operating system from a USB stick will be slower than running it from an internal drive, especially if you're using a USB 2.0 drive.
For better performance, use a USB 3.0 or 3.1 drive if possible.

---

## Unlocking LUKS

Use the commands below to unlock the encrypted partition and then mount it.

Note: after running the first command, you will be prompted to enter the password of the encrypted partition.

```bash
sudo cryptsetup luksOpen /dev/sda2 persistence &&
sudo mkdir /mnt/persistence &&
sudo mount /dev/mapper/persistence /mnt/persistence
```
