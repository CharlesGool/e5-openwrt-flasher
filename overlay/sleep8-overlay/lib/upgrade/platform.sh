# E5 (e5-sleep8): OpenWrt's generic armsr platform script, replaced.  It wrote an EFI disk image,
# and knows nothing of the E5's storage (the kernel in boot_b, the root image on userdata or an SD
# card): sysupgrade and LuCI's 刷写新的固件 would break the system.  They refuse here; updates go
# through LuCI 系统 -> E5 系统升级 (an E5 flash package, /usr/libexec/e5-upgrade), or flash.py --update.
# (sysupgrade -b, the configuration backup, does not come here and keeps working.)

platform_check_image() {
	echo "E5: 不能用通用 sysupgrade 刷写，请在 LuCI「系统 → E5 系统升级」上传 E5 刷机包（.zip）"
	echo "E5: generic sysupgrade images are not for this device; use System -> E5 系统升级 with an E5 flash package"
	return 1
}

platform_do_upgrade() {
	echo "E5: refused -- use System -> E5 系统升级"
	return 1
}

platform_copy_config() {
	return 0
}
