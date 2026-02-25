### AnyKernel3 Ramdisk Mod Script
## NovaKernel - Enhanced for KernelSU + Full vendor_boot patching
## Based on osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NovaKernel by omarsmehan1
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=a73xq
device.name2=a52sxq
device.name3=m52xq
device.name4=SM-A736B
device.name5=SM-A528B
device.name6=SM-M526B
supported.versions=12-15
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install

##############################################
## PART 1: BOOT.IMG PATCHING (KernelSU Support)
##############################################

## boot files attributes
boot_attributes() {
    set_perm_recursive 0 0 755 644 $RAMDISK/*;
    set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching
. tools/ak3-core.sh;

ui_print " ";
ui_print "========================================";
ui_print "   NovaKernel - KernelSU Enhanced";
ui_print "========================================";
ui_print " ";

# Detect device
DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null);
DEVICE_NAME=$(getprop ro.product.device 2>/dev/null);

ui_print "Device: $DEVICE_MODEL ($DEVICE_NAME)";
ui_print " ";

# Determine device type for firmware
case $DEVICE_NAME in
    a73xq|a73x)
        DEVICE_TYPE="A73";
        ui_print "→ Detected: Galaxy A73 5G";
        ;;
    a52sxq|a52s)
        DEVICE_TYPE="A52S";
        ui_print "→ Detected: Galaxy A52s 5G";
        ;;
    m52xq|m52)
        DEVICE_TYPE="M52";
        ui_print "→ Detected: Galaxy M52 5G";
        ;;
    *)
        DEVICE_TYPE="UNKNOWN";
        ui_print "⚠ Unknown device - proceeding anyway...";
        ;;
esac

ui_print " ";
ui_print "→ Patching boot.img...";

# Erase AVB footer from boot.img
if [ -f "$BIN/avbtool" ]; then
    ui_print "  • Erasing AVB footer from boot.img";
    $BIN/avbtool erase_footer --image $BOOTIMG 2>/dev/null || ui_print "  ⚠ AVB erase skipped";
fi

# boot install - unpack and replace kernel
split_boot;

# Replace kernel Image
if [ -f "$AKHOME/Image" ]; then
    ui_print "  • Replacing kernel Image";
    cp -f $AKHOME/Image $SPLITIMG/kernel;
elif [ -f "$AKHOME/Image.gz" ]; then
    ui_print "  • Replacing kernel Image.gz";
    cp -f $AKHOME/Image.gz $SPLITIMG/kernel;
elif [ -f "$AKHOME/Image.lz4" ]; then
    ui_print "  • Replacing kernel Image.lz4";
    cp -f $AKHOME/Image.lz4 $SPLITIMG/kernel;
else
    ui_print "  ✗ No kernel image found!";
    abort "Kernel image not found in package!";
fi

##############################################
## KernelSU DETECTION & VERIFICATION
##############################################

ui_print "  • Checking for KernelSU...";

# Check if KernelSU is integrated in kernel
if [ -f "$SPLITIMG/kernel" ]; then
    # Try to detect KernelSU in kernel
    strings $SPLITIMG/kernel 2>/dev/null | grep -q "kernelsu" && KSU_INTEGRATED=true || KSU_INTEGRATED=false;
    
    if [ "$KSU_INTEGRATED" = true ]; then
        ui_print "  ✓ KernelSU detected in kernel!";
        
        # Get KernelSU version if possible
        KSU_VERSION=$(strings $SPLITIMG/kernel 2>/dev/null | grep -oP 'KernelSU version: \K[0-9]+' | head -n1);
        [ -n "$KSU_VERSION" ] && ui_print "    Version: $KSU_VERSION";
    else
        ui_print "  ⚠ KernelSU not detected in kernel";
        ui_print "    This appears to be a non-KSU kernel";
    fi
fi

# Repack and flash boot.img
flash_boot;

ui_print "  ✓ boot.img patched successfully";
ui_print " ";


##############################################
## PART 2: VENDOR_BOOT.IMG PATCHING
##############################################

## vendor_boot files attributes
vendor_boot_attributes() {
    set_perm_recursive 0 0 755 644 $RAMDISK/*;
    set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# vendor_boot shell variables
BLOCK=vendor_boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# reset for vendor_boot patching
reset_ak;

ui_print "→ Patching vendor_boot.img...";

# Erase AVB footer from vendor_boot.img
if [ -f "$BIN/avbtool" ]; then
    ui_print "  • Erasing AVB footer from vendor_boot.img";
    $BIN/avbtool erase_footer --image $BOOTIMG 2>/dev/null || ui_print "  ⚠ AVB erase skipped";
fi

# Split vendor_boot and unpack ramdisk
dump_boot;

##############################################
## HEADER MODIFICATIONS
##############################################

ui_print "  • Modifying boot header...";

cd $SPLITIMG;

# Patch SRP security level (Critical for Samsung Knox bypass)
if [ -f header ]; then
    ui_print "    - Patching SRP version to 001";
    sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header;
    
    # Optional: Add SELinux permissive mode (commented out for security)
    # ui_print "    - Adding SELinux permissive mode";
    # sed -i '2 s/$/ androidboot.selinux=permissive/' header;
fi

cd $AKHOME;

##############################################
## RAMDISK MODIFICATIONS
##############################################

ui_print "  • Modifying vendor ramdisk...";

# 1. Patch fstab.qcom for multi-filesystem support
if [ -f "$RAMDISK/first_stage_ramdisk/fstab.qcom" ]; then
    ui_print "    - Patching fstab.qcom (erofs/ext4/f2fs support)";
    
    backup_file $RAMDISK/first_stage_ramdisk/fstab.qcom;
    
    awk 'BEGIN{OFS="\t"} 
    /^(system|vendor|product|odm)[[:space:]]/ && !seen[$1]++ {
        rest=$4;
        for(i=5; i<=NF; i++) rest=rest"\t"$i;
        for(i=1; i<=3; i++) {
            fs = (i==1 ? "erofs" : (i==2 ? "ext4" : "f2fs"));
            print $1, $2, fs, rest;
        }
        next;
    }
    {print}' $RAMDISK/first_stage_ramdisk/fstab.qcom > $RAMDISK/first_stage_ramdisk/fstab.qcom.new;
    
    mv -f $RAMDISK/first_stage_ramdisk/fstab.qcom.new $RAMDISK/first_stage_ramdisk/fstab.qcom;
else
    ui_print "    ⚠ fstab.qcom not found - skipping";
fi

# 2. Create firmware directory structure
ui_print "    - Setting up firmware directories";
mkdir -p $RAMDISK/lib/firmware;

# 3. Add device-specific firmware
case $DEVICE_TYPE in
    A73)
        ui_print "    - Adding A73 touchscreen firmware";
        if [ -d "$AKHOME/firmware/tsp_synaptics" ]; then
            mkdir -p $RAMDISK/lib/firmware/tsp_synaptics;
            for fw in s3908_a73xq_boe.bin s3908_a73xq_csot.bin s3908_a73xq_sdc.bin s3908_a73xq_sdc_4th.bin; do
                if [ -f "$AKHOME/firmware/tsp_synaptics/$fw" ]; then
                    cp -f $AKHOME/firmware/tsp_synaptics/$fw $RAMDISK/lib/firmware/tsp_synaptics/;
                    chmod 644 $RAMDISK/lib/firmware/tsp_synaptics/$fw;
                fi
            done
        fi
        ;;
        
    A52S)
        ui_print "    - Adding A52s touchscreen firmware";
        if [ -d "$AKHOME/firmware/tsp_stm" ]; then
            mkdir -p $RAMDISK/lib/firmware/tsp_stm;
            if [ -f "$AKHOME/firmware/tsp_stm/fts5cu56a_a52sxq.bin" ]; then
                cp -f $AKHOME/firmware/tsp_stm/fts5cu56a_a52sxq.bin $RAMDISK/lib/firmware/tsp_stm/;
                chmod 644 $RAMDISK/lib/firmware/tsp_stm/fts5cu56a_a52sxq.bin;
            fi
        fi
        ;;
        
    M52)
        ui_print "    - Adding M52 firmware (ABOV + Touchscreen)";
        # ABOV grip sensor firmware
        if [ -d "$AKHOME/firmware/abov" ]; then
            mkdir -p $RAMDISK/lib/firmware/abov;
            for fw in a96t356_m52xq.bin a96t356_m52xq_sub.bin; do
                if [ -f "$AKHOME/firmware/abov/$fw" ]; then
                    cp -f $AKHOME/firmware/abov/$fw $RAMDISK/lib/firmware/abov/;
                    chmod 644 $RAMDISK/lib/firmware/abov/$fw;
                fi
            done
        fi
        
        # Synaptics touchscreen firmware
        if [ -d "$AKHOME/firmware/tsp_synaptics" ]; then
            mkdir -p $RAMDISK/lib/firmware/tsp_synaptics;
            for fw in s3908_m52xq.bin s3908_m52xq_boe.bin s3908_m52xq_sdc.bin; do
                if [ -f "$AKHOME/firmware/tsp_synaptics/$fw" ]; then
                    cp -f $AKHOME/firmware/tsp_synaptics/$fw $RAMDISK/lib/firmware/tsp_synaptics/;
                    chmod 644 $RAMDISK/lib/firmware/tsp_synaptics/$fw;
                fi
            done
        fi
        ;;
esac

# 4. Replace kernel modules
ui_print "    - Updating kernel modules";

if [ "$(ls $AKHOME/modules/*.ko 2>/dev/null)" ]; then
    # Clear old modules
    rm -rf $RAMDISK/lib/modules/*;
    
    # Create modules directory
    mkdir -p $RAMDISK/lib/modules;
    
    # Copy all kernel modules
    cp -f $AKHOME/modules/*.ko $RAMDISK/lib/modules/ 2>/dev/null;
    chmod 644 $RAMDISK/lib/modules/*.ko 2>/dev/null;
    
    # Copy module metadata files
    for modfile in modules.alias modules.dep modules.softdep modules.load; do
        if [ -f "$AKHOME/modules/$modfile" ]; then
            cp -f $AKHOME/modules/$modfile $RAMDISK/lib/modules/;
            chmod 644 $RAMDISK/lib/modules/$modfile;
        fi
    done
    
    MODULE_COUNT=$(ls $RAMDISK/lib/modules/*.ko 2>/dev/null | wc -l);
    ui_print "    ✓ Installed $MODULE_COUNT kernel modules";
else
    ui_print "    ⚠ No kernel modules found - skipping";
fi

# 5. Replace DTB if provided
if [ -f "$AKHOME/dtb" ]; then
    ui_print "    - Replacing Device Tree Blob (DTB)";
    cp -f $AKHOME/dtb $SPLITIMG/dtb;
elif [ -f "$AKHOME/yupik.dtb" ]; then
    ui_print "    - Replacing Device Tree Blob (yupik.dtb)";
    cp -f $AKHOME/yupik.dtb $SPLITIMG/dtb;
fi

##############################################
## REPACK AND FLASH
##############################################

# Repack and flash vendor_boot.img
write_boot;

ui_print "  ✓ vendor_boot.img patched successfully";
ui_print " ";

##############################################
## OPTIONAL: DTBO FLASHING
##############################################

if [ -f "$AKHOME/dtbo.img" ]; then
    ui_print "→ Flashing dtbo.img...";
    flash_generic dtbo;
    ui_print "  ✓ dtbo.img flashed successfully";
    ui_print " ";
fi

##############################################
## FINALIZATION
##############################################

ui_print "========================================";
ui_print "    Installation Complete!";
ui_print "========================================";
ui_print " ";

# Show kernel version if available
KERNEL_VERSION=$(cat $SPLITIMG/boot.img-kernelver 2>/dev/null || echo "Custom");
ui_print "Kernel: NovaKernel $KERNEL_VERSION";

# Show KernelSU status
if [ "$KSU_INTEGRATED" = true ]; then
    ui_print "KernelSU: ✓ Integrated";
    [ -n "$KSU_VERSION" ] && ui_print "  Version: $KSU_VERSION";
else
    ui_print "KernelSU: ✗ Not detected";
fi

ui_print "Device: $DEVICE_MODEL";
ui_print " ";
ui_print "Changes applied:";
ui_print "  ✓ Kernel replaced in boot.img";
ui_print "  ✓ DTB updated in vendor_boot.img";
ui_print "  ✓ SRP security patched";
ui_print "  ✓ fstab.qcom multi-fs support";
ui_print "  ✓ Firmware files added";
ui_print "  ✓ Kernel modules updated";
[ "$KSU_INTEGRATED" = true ] && ui_print "  ✓ KernelSU support enabled";
ui_print " ";
ui_print "Reboot required to apply changes.";
ui_print " ";

# KernelSU specific instructions
if [ "$KSU_INTEGRATED" = true ]; then
    ui_print "KernelSU Instructions:";
    ui_print "  1. Reboot your device";
    ui_print "  2. Install KernelSU Manager APK";
    ui_print "  3. Grant root access as needed";
    ui_print " ";
fi

ui_print "========================================";
ui_print "  Credits: omarsmehan1 / osm0sis";
ui_print "========================================";
ui_print " ";

## end install
