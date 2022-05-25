 
#!/bin/bash
#
# A Linux system migration tool 
#
# Date: October 2021
# Author: Bryan Ritchie
# 
# Migration Strategy:
# This script captures a snapshot of dependencies of interest in an Arch Linux filesystem. The 'dependencies of interest' 
# are listed in the arrays below. The files required for migration are staged into a temporary directory for easy access.
# This snapshot (a compressed file called /tmp/migrate.tar.gz ) is then used to compare, analyze, deploy and install any required 
# missing dependencies on another system when the script is invoked from that target system.
# 
# NOTE: In order to deploy this script onto a targeted machine, the generated snapshot needs to be present on the target filesystem.


VERSION="1.0.0"

MIGRATE=/migrate
MIGRATE_FILE=migrate.tar.gz

METADATA=/metadata
MET_FILES=file_metadata
MET_DIRECTORYS=dir_metadata
MET_COMMANDS=cmd_versions

CONFIG=/config
SERVICES=/services
USR_GRP=/usr_grp # Users and groups

LOG_FILENAME=sysmig.log
TMP_WD=/tmp/

MIGRATE_WD=$TMP_WD/$MIGRATE
METADATA_WD=$TMP_WD/$METADATA
CONFIG_WD=$TMP_WD/$CONFIG
SERVICES_WD=$TMP_WD/$SERVICES
USR_GRP_WD=$TMP_WD/$USR_GRP
LOG_FILE=$TMP_WD/$LOG_FILENAME

########## NOTE ##########
# All of the arrays below are editable. Fill them with 
# directories and files of interest

# It's best to keep everything with absolute filepaths
declare -a Dirs=(\
"/etc/network/" \
"/etc/systemd/" \
"/etc/init.d/" \
"" \
)

declare -a Files=(\
"/usr/share/plymouth/splash.png" \
"/etc/passwd" \
"/etc/group" \
"/etc/shadow" \
"/etc/gshadow" \
"/boot/config.txt" \
"" \
)

declare -a Cmds=(\
"udiskie" \
"daemonize" \
"" \
)

declare -a Devs=(\
"/dev/ttyAMA0" \
"" \
)

declare -a Configs=(\
"/boot/config.txt:display_rotate=3" \
"/boot/config.txt:hdmi_force_hotplug=1" \
"/boot/config.txt:hdmi_group=2" \
"/boot/config.txt:hdmi_mode=1" \
"/boot/config.txt:hdmi_mode=87" \
"/boot/config.txt:hdmi_cvt 800 480 60 6 0 0 0" \
"/boot/config.txt:max_usb_current=1" \
"/boot/config.txt:gpu_mem_1024=512" \
"/boot/config.txt:display_lcd_rotate=1" \
"/boot/config.txt:dtoverlay=rpi-ft5406,touchscreen-swapped-x-y=1,touchscreen-inverted-x=1" \
"/etc/sudoers:root ALL=(ALL) ALL" \
"/etc/sudoers:alarm ALL=(ALL) ALL"
"/etc/ssh/sshd_config:PermitRootLogin yes" \
"/boot/config.txt:disable_splash=1" \
"" \
)

declare -a Services=(\
"udiskie.service" \
"sshd.service" \
"" \
)

declare -a Users=(\
# "root" \
# "bin" \
# "daemon" \
# "mail" \
# "ftp" \
# "http" \
# "uuidd" \
# "dbus" \
# "nobody" \
# "systemd-journal-gateway" \
# "systemd-timesync" \
# "systemd-network" \
# "systemd-bus-proxy" \
# "systemd-resolve" \
# "systemd-coredump" \
# "systemd-journal-upload" \
# "systemd-journal-remote" \
# "alarm" \
# "git" \
# "polkitd" \
"" \
)

declare -a Groups=(\
"alarm" \
"pi" \
# "root" \
# "bin" \
# "daemon" \
# "sys" \
# "adm" \
# "disk" \
# "wheel" \
# "log" \
"" \
)

scan_directories ()
{   # Scan through interested directories recursively
    # If on ARCH machine, stage found files and directories in the /tmp/ directory

    echo -e "\n\n  Scanning directories...\n" | tee -a $LOG_FILE

    # Explicitly set the output working directory
    METADATA_WD=$TMP_WD/$METADATA

    # Make sure directory exists
    mkdir -p $METADATA_WD 

    # Clear out the old metadata file
    echo "Directory Metadata" > $METADATA_WD/dir_metadata

    # Recursively scan these directories
    for dir in ${Dirs[@]}; do
        recursivelist=$(find $dir)
        # echo "[DEBUG]: $dir: $recursivelist"

        for file in ${recursivelist}; do
            # echo "[DEBUG]: file: $file"
            STRTYPE=""
            if [[ -h file ]]; then
                echo "LINK $file"
                STRTYPE=$(echo LINK)
            elif [[ -f $file ]]; then
                STRTYPE=$(echo FILE)
            elif [[ -d $file ]]; then
                # Compile metadata
                STRTYPE=$(echo DIR)
                INODE=$(stat -c %i $dir)
                PERMS=$(stat -c %a $dir)
                OWNER=$(stat -c %U $dir)
                GROUP=$(stat -c %G $dir)
                SRC=$(ls -d $dir)
                metadata="$STRTYPE $INODE $PERMS $OWNER $GROUP $SRC"

                # Skip duplicates
                alreadystored=$(grep "$metadata" $METADATA_WD/dir_metadata)
                if [[ $alreadystored != "" ]]; then
                    continue
                fi
                # Store metadata
                echo "$metadata" >> $METADATA_WD/dir_metadata
                echo "FOUND $dir " | tee -a $LOG_FILE

                # Stage the directory
                if [[ $MACHINE == *"ARCH"* ]]; then
                    DST_DIR=$(echo $TMP_WD/migrate/$dir | sed 's/\/\//\//g')
                    mkdir -p $DST_DIR
                fi

                continue
            elif [[ -S $file || -p $file ]]; then
                continue
            fi

            if [[ $STRTYPE != "" ]]; then
                # Follow links while compiling metadata
                TYPE=$(ls -lL $file | awk '{print substr($1,1,1)}' | tr -d '\n')
                INODE=$(stat -L -c %i $file)
                PERMS=$(stat -L -c %a $file)
                OWNER=$(stat -L -c %U $file)
                GROUP=$(stat -L -c %G $file)

                # Compile link path to filename
                if [[ $STRTYPE = "FILE" ]]; then
                    SRC=$(ls -l $file | awk '{print substr($9,1)}' | tr -d '\n')
                    metadata="$STRTYPE $TYPE $INODE $PERMS $OWNER $GROUP $SRC"
                elif [[ $STRTYPE = "LINK" ]]; then
                    SRC=$(ls -l $file | awk '{print substr($11,1)}' | tr -d '\n')

                    # Tack on the filename that the link points to here
                    metadata="$STRTYPE $TYPE $INODE $PERMS $OWNER $GROUP $SRC $file"
                fi
                
                # Store metadata
                echo "$metadata" >> $METADATA_WD/file_metadata
                echo "FOUND $file " | tee -a $LOG_FILE

                # Stage the file
                if [[ $MACHINE == *"ARCH"* ]]; then
                    DST_FILE=$(echo $TMP_WD/migrate/$file | sed 's/\/\//\//g')
                    # echo "[DEBUG]: DST_FILE $DST_FILE"
                    
                    # Determine the destination basepath
                    dstbasepath=$(dirname $DST_FILE)
                    # echo "[DEBUG]: dstbasepath $dstbasepath"

                    if [[ ! -d $dstbasepath ]]; then 
                        # echo "MKDIR $dstbasepath" | tee -a $LOG_FILE
                        mkdir -p $dstbasepath
                    fi
                    
                    cp $file $DST_FILE
                fi

            else
                echo "MISSING $file" | tee -a $LOG_FILE
            fi
        done
    done
}

install_directories ()
{   # Must supply a source directory
    echo -e "\n\n  Installing directories...\n" | tee -a $LOG_FILE
    SRC_WD=$1
    METADATA_WD=$(echo $SRC_WD/$METADATA | sed 's/\/\//\//g')

    for dir in ${Dirs[@]}; do
        # Read the metadata for this particular directory
        metadata=$(cat $METADATA_WD/dir_metadata | grep $dir 2>/dev/null)
        
        if [[ $metadata != "" ]]; then
            # Is $dir needed?
            if [[ ! -d $dir ]]; then
                # Parse metadata
                TYPE=$(echo $metadata | awk '{print substr($1,1)}' | tr -d '\n')
                INODE=$(echo $metadata | awk '{print substr($2,1)}' | tr -d '\n')
                PERMS=$(echo $metadata | awk '{print substr($3,1)}' | tr -d '\n')
                OWNER=$(echo $metadata | awk '{print substr($4,1)}' | tr -d '\n')
                GROUP=$(echo $metadata | awk '{print substr($5,1)}' | tr -d '\n')
                SRC=$(echo $metadata | awk '{print substr($6,1)}' | tr -d '\n')

                if [[ $TYPE == "DIR" ]]; then
                    mkdir -p $dir
                    # Apply metadata
                    chmod $PERMS $dir
                    chown $OWNER:$GROUP $dir
                else
                    echo "ERROR: ($TYPE) $dir metadata mismatch" | tee -a $LOG_FILE
                    continue
                fi
                
                echo "MAKE $dir" | tee -a $LOG_FILE
            else
                echo "SKIP $dir" | tee -a $LOG_FILE
            fi
        fi
    done
}

scan_files ()
{
    echo -e "\n\n  Scanning files...\n" | tee -a $LOG_FILE

    # Make sure directory exists
    METADATA_WD=$TMP_WD/$METADATA
    mkdir -p $METADATA_WD

    # Scan for each file
    for file in ${Files[@]}; do
        STRTYPE=""
        if [[ -h $file ]]; then
            STRTYPE=$(echo LINK)
        elif [[ -f $file ]]; then
            STRTYPE=$(echo FILE)
        fi

        if [[ $STRTYPE != "" ]]; then

            # Follow links while compiling metadata
            TYPE=$(ls -lL $file | awk '{print substr($1,1,1)}' | tr -d '\n')
            INODE=$(stat -L -c %i $file)
            PERMS=$(stat -L -c %a $file)
            OWNER=$(stat -L -c %U $file)
            GROUP=$(stat -L -c %G $file)

            # Compile link path to filename
            if [[ $STRTYPE = "FILE" ]]; then
                SRC=$(ls -l $file | awk '{print substr($9,1)}' | tr -d '\n')
                metadata="$STRTYPE $TYPE $INODE $PERMS $OWNER $GROUP $SRC"
            elif [[ $STRTYPE = "LINK" ]]; then
                SRC=$(ls -l $file | awk '{print substr($11,1)}' | tr -d '\n')

                # Tack on the filename that the link points to here
                metadata="$STRTYPE $TYPE $INODE $PERMS $OWNER $GROUP $SRC $file"
            fi

            # Store metadata
            echo "$metadata" >> $METADATA_WD/file_metadata

            # Stage the file
            if [[ $MACHINE == *"ARCH"* ]]; then
                DST_FILE=$(echo $TMP_WD/migrate/$file | sed 's/\/\//\//g')
                # echo "[DEBUG]: DST_FILE $DST_FILE"

                # Determine the destination basepath
                dstbasepath=$(dirname $DST_FILE)
                # echo "[DEBUG]: dstbasepath $dstbasepath"

                if [[ ! -d $dstbasepath ]]; then 
                    # echo "MKDIR $dstbasepath" | tee -a $LOG_FILE
                    mkdir -p $dstbasepath
                fi
                
                cp $file $DST_FILE
            fi


            echo "FOUND $file" | tee -a $LOG_FILE
        else
            echo "MISSING $file" | tee -a $LOG_FILE
        fi
    done
}

install_files ()
{   # Must supply a source directory
    echo -e "\n\n  Installing files...\n" | tee -a $LOG_FILE
    SRC_WD=$(echo $1/migrate | sed 's/\/\//\//g')
    METADATA_WD=$(echo $1/$METADATA | sed 's/\/\//\//g') 

    # Error check the source directory
    if [[ ! -d $SRC_WD ]]; then 
        echo "ERROR: $SRC_WD does not exist. Exiting" | tee -a $LOG_FILE
        exit
    fi

    for file in ${Files[@]}; do
        # Read the metadata for this particular directory
        metadata=$(cat $METADATA_WD/file_metadata | grep $file 2>/dev/null)
        
        if [[ $metadata != "" ]]; then
            # Is $file needed?
            # if [[ -f $file ]]; then # (BAR): Uncomment to debug this conditional
            if [[ ! -f $file ]]; then
                
                # Parse metadata                
                STRTYPE=$(echo $metadata | awk '{print substr($1,1)}' | tr -d '\n')
                TYPE=$(echo $metadata | awk '{print substr($2,1)}' | tr -d '\n')
                INODE=$(echo $metadata | awk '{print substr($3,1)}' | tr -d '\n')
                PERMS=$(echo $metadata | awk '{print substr($4,1)}' | tr -d '\n')
                OWNER=$(echo $metadata | awk '{print substr($5,1)}' | tr -d '\n')
                GROUP=$(echo $metadata | awk '{print substr($6,1)}' | tr -d '\n')
                SRC=$(echo $metadata | awk '{print substr($7,1)}' | tr -d '\n')

                # Strip filename from filepath
                filename=$(echo ${SRC##*/})

                # Leave the following files in the SRC_WD
                if [[ $filename == *"passwd" || \
                      $filename == *"shadow" || \
                      $filename == *"group" ]]; then
                      continue
                fi

                # Determine the source basepath
                srcbasepath=$(dirname $SRC)

                # Determine the destination basepath
                dstbasepath=$(dirname $file)

                # Create each filepath if needed
                # if [[ -d $srcbasepath ]]; then # (BAR): Uncomment to debug this conditional
                if [[ ! -d $srcbasepath ]]; then 
                    echo "MKDIR $srcbasepath" | tee -a $LOG_FILE
                    mkdir -p $basepath
                fi

                # if [[ -d $dstbasepath ]]; then # (BAR): Uncomment to debug this conditional
                if [[ ! -d $dstbasepath ]]; then 
                    echo "MKDIR $dstbasepath" | tee -a $LOG_FILE
                    mkdir -p $basepath
                fi

                # echo "[DEBUG]: file/link            :$file"
                # echo "[DEBUG]: source/linksource    :$SRC"
                # echo "[DEBUG]: filename:$filename"
                # echo "[DEBUG]: srcbasepath:$srcbasepath"
                # echo "[DEBUG]: dstbasepath:$dstbasepath"
                
                # Copy file to destination filepath
                # if [[ -f $SRC ]]; then # (BAR): Uncomment to debug this conditional
                if [[ ! -f $SRC ]]; then 

                    # Finally, install the file
                    srcfile=$SRC_WD$SRC
                    srcfile=$(echo $srcfile | sed 's/\/\//\//g')
                    echo "INSTALL -m $PERMS -o $OWNER -g $GROUP $srcfile $SRC" | tee -a $LOG_FILE
                    install -m $PERMS -o $OWNER -g $GROUP $srcfile $SRC
                    # Was this a link?
                    if [[ $STRTYPE == "LINK" ]]; then
                        # TODO Create the link
                        echo "LINK $SRC $file" | tee -a $LOG_FILE
                        ln -s $SRC $file
                    fi
                    
                    # echo "[DEBUG]: srcfile: $srcfile"
                    # echo "[DEBUG]: SRC: $SRC"
                    
                    echo ""
                else
                    echo "SKIP $SRC" | tee -a $LOG_FILE
                fi
            else
                echo "SKIP $file" | tee -a $LOG_FILE
            fi
        else
            echo "ERROR: Missing metadata information for $file" | tee -a $LOG_FILE
        fi


    done
}

scan_commands ()
{
    echo -e "\n\n  Scanning commands...\n" | tee -a $LOG_FILE

    # Make sure directory exists
    METADATA_WD=$TMP_WD/$METADATA
    mkdir -p $METADATA_WD

    # Clear out the old metadata file
    echo "Commands Metadata" 2>/dev/null > $METADATA_WD/$MET_COMMANDS

    # Test each command
    for cmd in ${Cmds[@]}; do
        # Check that it is in the PATH
        WHICH=$(which $cmd | tr -d '\n')
        if [[ $WHICH != *"no $cmd"* ]]; then
            # Store version of command
            if [[ $MACHINE == *"ARCH"* ]]; then
                VERSION=$(pacman -Q $cmd 2>/dev/null | awk '{print $0}')
                if [[ $VERSION == "" ]]; then # Version wasn't returned, try a different method
                    VERSION=$($WHICH --version)
                fi
            else
                VERSION=$(apt show $cmd | grep Version | awk '{print $2}')
                if [[ $VERSION == "" ]]; then
                    VERSION=$(dpkg -s $cmd | grep Version | awk '{print $2}')
                fi
                if [[ $VERSION == "" ]]; then
                    VERSION=$(apt list | grep $cmd)
                fi
            fi

            if [[ $VERSION != "" ]]; then
                echo "$cmd $VERSION" >> $METADATA_WD/$MET_COMMANDS
                echo "INSTALLED $cmd" | tee -a $LOG_FILE
            else
                echo "MISSING $cmd" | tee -a $LOG_FILE
            fi
        else
            echo "MISSING $cmd" | tee -a $LOG_FILE 
        fi
    done
}

install_commands ()
{   # A scan of the system should have been completed prior to this step
    
    echo -e "\n\n  Installing commands...\n" | tee -a $LOG_FILE
    
    RASPBIAN_PACKAGE_MANAGER="apt"

    # Run update if we are not on deprecated machine
    if [[ $MACHINE != *"ARCH"* ]]; then
        $RASPBIAN_PACKAGE_MANAGER update
        $RASPBIAN_PACKAGE_MANAGER upgrade -y
    fi

    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    echo ""
    SRC_WD=$1
    SRC_METADATA_WD=$SRC_WD/$METADATA
    SRC_METADATA_WD=$(echo $SRC_METADATA_WD | sed 's/\/\//\//g')
    LOC_METADATA_WD=$TMP_WD/$METADATA

    if [[ ! -d $LOC_METADATA_WD ]]; then
        echo "ERROR: Cannot install commands, there is no local metadata available" | tee -a $LOG_FILE
        exit 1
    fi
    if [[ ! -d $SRC_METADATA_WD ]]; then
        echo "ERROR: Cannot install commands, there is no source metadata available" | tee -a $LOG_FILE
        exit
    fi

    for cmd in ${Cmds[@]}; do

        SRC_VERSION=$(grep -i -m 1 $cmd $SRC_METADATA_WD/$MET_COMMANDS | awk '{print $3}' )
        # echo "[DEBUG]: SRC $cmd $SRC_VERSION"

        LOC_VERSION=$(grep -i -m 1 $cmd $LOC_METADATA_WD/$MET_COMMANDS | awk '{print $3}' )
        # echo "[DEBUG]: LOC $cmd $LOC_VERSION"

        # if [[ $SRC_VERSION != $LOC_VERSION ]]; then # (BAR): Uncomment to debug this conditional
        if [[ $SRC_VERSION == $LOC_VERSION ]]; then
            echo "SKIP $cmd $SRC_VERSION" | tee -a $LOG_FILE
            continue
        else # Package is needed, let's install it
            echo "[DEBUG]: $RASPBIAN_PACKAGE_MANAGER install $cmd=$SRC_VERSION" | tee -a $LOG_FILE
            $RASPBIAN_PACKAGE_MANAGER install $cmd=$SRC_VERSION -y

            if [[ $? -eq 0 ]]; then
                echo "ERROR: Failed to install $cmd=$SRC_VERSION" | tee -a $LOG_FILE
                echo "Attempting to install available package instead" | tee -a $LOG_FILE
                $RASPBIAN_PACKAGE_MANAGER install $cmd -y

                if [[ $? -eq 0 ]]; then
                    echo "INSTALL $cmd $SRC_VERSION successful" | tee -a $LOG_FILE
                else
                    echo "FATAL: Unable to install $cmd" | tee -a $LOG_FILE
                fi
            fi
        fi
    done
}

scan_devices ()
{
    echo -e "\n\n  Scanning devices...\n" | tee -a $LOG_FILE

    # Make sure directory exists
    METADATA_WD=$TMP_WD/$METADATA
    mkdir -p $METADATA_WD

    # Clear out the old metadata file
    echo "Devices Metadata" > $METADATA_WD/device_metadata

    # Scan each device
    for dev in ${Devs[@]}; do
        if [[ -c $dev ]]; then
            # Store metadata
            ls -li $dev >> $METADATA_WD/device_metadata
            echo "FOUND $dev" | tee -a $LOG_FILE
        else
            echo "MISSING $dev" | tee -a $LOG_FILE
        fi
    done
}

scan_configs()
{
    echo -e "\n\n  Scanning configuration settings...\n" | tee -a $LOG_FILE

    PREV_IFS=$IFS
    # Input Field Separator
    IFS=":"

    # Make sure directory exists
    CONFIG_WD=$TMP_WD/$CONFIG
    mkdir -p $CONFIG_WD

    # Clear out the old metadata file
    echo "Configuration data" > $CONFIG_WD/config_data

    key=0 # Used to determine whether scanning a key or a value
    for config in ${Configs[@]}; do
        if [[ key -eq 0 ]]; then
            file=$config
            key=1 # toggle key, next time around, ensure we scan the value
            continue
        else
            config_kvp=$config # kvp = key value pair
            key=0 # toggle key, ensure to scan the key next time
        fi

        if [[ -f $file ]]; then
            
            FOUND=$(grep $config_kvp $file) 
            if [[ $FOUND != "" ]]; then
                echo "$file:$config_kvp" >> $CONFIG_WD/config_data
                echo "FOUND $file:$config_kvp" | tee -a $LOG_FILE
            else
                echo "MISSING $file:$config_kvp" | tee -a $LOG_FILE
            fi
        fi 
    done

    IFS=$PREV_IFS
}

install_configs ()
{
    echo -e "\n\n  Configuring...\n" | tee -a $LOG_FILE

    PREV_IFS=$IFS
    # Input Field Separator
    IFS=":"

    key=0 # Used to determine whether scanning a key or a value
    for config in ${Configs[@]}; do
        if [[ key -eq 0 ]]; then
            file=$config
            key=1 # toggle key, next time around, ensure we scan the value
            continue
        else
            config_kvp=$config # kvp = key value pair
            key=0 # toggle key, ensure to scan the key next time
        fi

        FOUND=$(grep $config_kvp $file 2>/dev/null) 
        # if [[ $FOUND == "" ]]; then # (BAR): Uncomment to debug this conditional
        if [[ $FOUND != "" ]]; then
            echo "SKIP $file:$config_kvp" | tee -a $LOG_FILE
        else

            if [[ $file == *"/etc/sudoers"* ]]; then
                echo -e "$config_kvp\n" | (EDITOR='tee -a' visudo)
            else
                echo "$config_kvp" >> $file
            fi
            
            if [[ $? -eq 0 ]]; then
                echo "ECHO '$config_kvp' >> $file"
            else
                echo "ERROR: Not able to configure $file:$config_kvp"
            fi
        fi
        # echo "[DEBUG]: file $file"
        # echo "[DEBUG]: config_kvp $config_kvp"
        # echo "[DEBUG]: echo '$config_kvp' >> $file"
    done

    IFS=$PREV_IFS
}

scan_services ()
{
    echo -e "\n\n  Scanning services...\n" | tee -a $LOG_FILE
    
    # Output the list of services to a file
    SERVICES_WD=$TMP_WD/$SERVICES
    mkdir -p $SERVICES_WD && systemctl > $SERVICES_WD/running_services

    # Scan for each service
    for service in ${Services[@]}; do
        grep $service $SERVICES_WD/running_services 1>/dev/null

        # Was the grep successful?
        if [[ $? -eq 0 ]]; then
            # find service
            searchservice=$(find / -name $service)
            
            mkdir -p $TMP_WD/$METADATA

            # for results in service
            for result in ${searchservice}; do
                if [[ $result != "" ]]; then
                    # Compile metadata
                    if [[ -h $result || -f $result ]]; then #LINK
                        if [[ -h $result ]]; then
                            STRTYPE="LINK"
                            SRC=$(ls -l $result | awk '{print substr($11,1)}' | tr -d '\n')
                        else
                            STRTYPE="FILE"
                            SRC=$(ls -l $result | awk '{print substr($9,1)}' | tr -d '\n')
                        fi
                            
                        TYPE=$(ls -lL $result | awk '{print substr($1,1,1)}' | tr -d '\n')
                        INODE=$(stat -L -c %i $result)
                        PERMS=$(stat -L -c %a $result)
                        OWNER=$(stat -L -c %U $result)
                        GROUP=$(stat -L -c %G $result)
                        metadata="$STRTYPE $TYPE $INODE $PERMS $OWNER $GROUP $SRC $result"

                        # Store metadata
                        # echo "[DEBUG]: echo "$metadata" >> $TMP_WD$METADATA/$MET_FILES"
                        echo "$metadata" >> $TMP_WD$METADATA/$MET_FILES

                        # Stage source file
                        DST_FILE=$(echo $TMP_WD$MIGRATE/$SRC | sed 's/\/\//\//g')

                        # Separate filename and basepath
                        dstbasepath=$(dirname $DST_FILE)

                        # Create necessary directories ahead of file
                        # if [[ -d $dstbasepath ]]; then # TODO (BAR): Uncomment to debug conditional
                        if [[ ! -d $dstbasepath ]]; then
                            # echo "[DEBUG]: mkdir -p $dstbasepath"
                            mkdir -p $dstbasepath
                        fi

                        # Copy source file to stage directory
                        # echo "[DEBUG]: cp $SRC $DST_FILE"
                        cp $SRC $DST_FILE

                    elif [[ -d $result ]]; then #DIR
                        STRTYPE="DIR"
                        INODE=$(stat -c %i $result)
                        PERMS=$(stat -c %a $result)
                        OWNER=$(stat -c %U $result)
                        GROUP=$(stat -c %G $result)
                        SRC=$(ls -d $result)
                        metadata="$STRTYPE $INODE $PERMS $OWNER $GROUP $SRC"

                        # Store metadata
                        # echo "[DEBUG]: echo "$metadata" >> $TMP_WD$METADATA/$MET_DIRECTORYS"
                        echo "$metadata" >> $TMP_WD$METADATA/$MET_DIRECTORYS

                        DST_FILE=$(echo $TMP_WD$MIGRATE/$SRC | sed 's/\/\//\//g')

                        # Create directory
                        if [[ ! -d $DST_FILE ]]; then
                            # echo "[DEBUG]: mkdir -p $DST_FILE"
                            mkdir -p $DST_FILE
                        fi
                    fi    
                else
                    echo "MISSING $service" | tee -a $LOG_FILE
                fi
            done

            echo "FOUND $service" | tee -a $LOG_FILE
        else
            echo "MISSING $service" | tee -a $LOG_FILE
        fi
    done        
}

scan_users ()
{
    echo -e "\n\n  Scanning users...\n" | tee -a $LOG_FILE

    # Output the list of users to a file
    USR_GRP_WD=$TMP_WD/$USR_GRP
    mkdir -p $USR_GRP_WD && cat /etc/passwd > $USR_GRP_WD/users

    # Scan for each user
    for user in ${Users[@]}; do
        RESULT=$(grep $user $USR_GRP_WD/users 1>/dev/null)

        # Was the grep successful?
        if [[ $? -eq 0 ]]; then
            echo "FOUND $user" | tee -a $LOG_FILE
        else
            echo "MISSING $user" | tee -a $LOG_FILE
        fi
    done        
}

create_users ()
{
    echo -e "\n\n  Creating required users...\n" | tee -a $LOG_FILE

    SRC_WD=$1
    USR_GRP_WD=$SRC_WD/$USR_GRP
    SRC_USERS=$(echo $USR_GRP_WD/users | sed 's/\/\//\//g')
    SRC_GROUPS=$(echo $USR_GRP_WD/groups | sed 's/\/\//\//g')

    PREV_IFS=$IFS
    IFS=$'\n'
    for user in ${Users[@]}; do
        # echo "[DEBUG]: user $user"

        src_userdata=$(grep $user $SRC_USERS)
        # echo "[DEBUG]: src_userdata $src_userdata"
        loc_userdata=$(cat /etc/passwd | grep $user)
        # echo "[DEBUG]: loc_userdata $loc_userdata"

        # Does user need to be created?
        # if [[ $src_userdata != $loc_userdata ]]; then # (BAR): Uncomment to debug this conditional
        if [[ $src_userdata == $loc_userdata ]]; then
            echo "SKIP $user"
            continue
        fi
        
        UNAME=""
        PWORD=""
        UUID=""
        GID=""
        GECOS=""
        HOME=""
        SHELL=""

        # BUGFIX: when a double IFS is encountered, that value is skipped
        # i.e. alarm:x:1000:1000::/home/alarm:/bin/bash contains a blank GECOS.
        #                       ^^
        # That value will be skipped because the for loop thinks its to be passed
        # over. Because of this, the GECOS value will evaluate as the next value
        # such as the home directory.
        #
        # Append the src_userdata to leave a space between :: for the IFS loop 
        src_userdata=$(echo $src_userdata | sed 's|::|: :|g')
        # echo "[DEBUG]: Appended src_userdata $src_userdata"
        key=0
        
        PREV_IFS=$IFS
        # Input Field Separator
        IFS=":"
        for result in ${src_userdata}; do
            # echo "[DEBUG]: result $result"
            for dat in ${result}; do
                # echo "[DEBUG]: dat $dat"
                case ${key} in
                    0)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        UNAME=$dat
                        key=1
                        ;;
                    1)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        PWORD=$dat
                        key=2
                        ;;
                    2)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        UUID=$dat
                        key=3
                        ;;
                    3)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        GID=$dat
                        key=4
                        ;;
                    4)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        GECOS=$dat
                        key=5
                        ;;
                    5)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        HOME=$dat
                        key=6
                        ;;
                    6)
                        # echo "[DEBUG]: dat[$key] ($dat)"
                        SHELL=$dat
                        key=0
                        ;;
                esac
            done
            IFS=$'\n'
        done

        if [[ $UNAME != $user ]]; then
            # echo "[DEBUG]: Ignoring ($UNAME)"
            continue
        fi

        # We know that the root password is to be hardcoded as root
        # We also know that the system will have a root user.. no need to create it again
        if [[ $UNAME == "root" ]]; then
            echo 'root:root' | chpasswd
            echo "USER root updated" | tee -a $LOG_FILE
            continue
        else
            echo "USER useradd $UNAME -u $UUID -g $GID -c '$GECOS' -d $HOME -s $SHELL"
            useradd $UNAME -u $UUID -g $GID -c "$GECOS" -d $HOME -s $SHELL
            if [[ $? -eq 0 ]]; then
                echo "USERADD $UNAME Successful" | tee -a $LOG_FILE
            else
                # Try incrementing the UID to make it unique to the system
                UUID=$((UUID+1))
                useradd $UNAME -u $UUID -g $GID -c "$GECOS" -d $HOME -s $SHELL

                if [[ $? -eq 0 ]]; then
                    echo "USERADD $UNAME Successful" | tee -a $LOG_FILE
                else
                    # Try incrementing the GID
                    # Note: this should be fixed, where the GID is updated by the group creating process
                    # if it needed to be incremented for the same reasons
                    GID=$((GID+1))
                    useradd $UNAME -u $UUID -g $GID -c "$GECOS" -d $HOME -s $SHELL

                    if [[ $? -eq 0 ]]; then
                        echo "USERADD $UNAME Successful" | tee -a $LOG_FILE
                    else
                        echo "ERROR: Could not add user $UNAME" | tee -a $LOG_FILE
                    fi
                fi
            fi
        fi 
          
        if [[ $PWORD == "x" ]]; then
            # Check the migrated /etc/shadow for the encrypted password
            PASSWD_FILE=$(echo $SRC_WD/$MIGRATE/etc/shadow | sed 's/\/\//\//g')
            if [[ -f $PASSWD_FILE ]]; then
                passwordline=$(cat $PASSWD_FILE | grep $UNAME)
                echo -e "echo '$passwordline' >> /etc/shadow\n\n" | tee -a $LOG_FILE
                echo '$passwordline' >> /etc/shadow
            else
                echo "ERROR: Unable to set password for $UNAME" | tee -a $LOG_FILE
            fi
        fi
        
        IFS=$PREV_IFS
    done

}

scan_groups ()
{
    echo -e "\n\n  Scanning groups...\n" | tee -a $LOG_FILE
    
    # Output the list of groups to a file
    USR_GRP_WD=$TMP_WD/$USR_GRP
    mkdir -p $USR_GRP_WD && cat /etc/group > $USR_GRP_WD/groups

    # Scan for each group
    for group in ${Groups[@]}; do
        RESULT=$(grep $group $USR_GRP_WD/groups 1>/dev/null)

        # Was the grep successful?
        if [[ $? -eq 0 ]]; then
            echo "FOUND $group" | tee -a $LOG_FILE
        else
            echo "MISSING $group" | tee -a $LOG_FILE
        fi
    done        
}

create_groups ()
{
    echo -e "\n\n  Creating required groups...\n" | tee -a $LOG_FILE

    SRC_WD=$1
    USR_GRP_WD=$SRC_WD/$USR_GRP
    SRC_GROUPS=$(echo $USR_GRP_WD/groups | sed 's/\/\//\//g')
    
    # Save previous input field separator
    PREV_IFS=$IFS
    IFS=$'\n'
    for group in ${Groups[@]}; do
        # echo -e "\n\n[DEBUG]: SCAN GROUP: $group"

        src_groupdata=$(grep $group $SRC_GROUPS)
        # echo "[DEBUG]: src_groupdata $src_groupdata"
        loc_groupdata=$(cat /etc/group | grep $group)
        # echo "[DEBUG]: loc_groupdata $loc_groupdata"

        # Does group need to be created?
        # if [[ $src_groupdata != $loc_groupdata ]]; then # (BAR): Uncomment to debug this conditional
        if [[ $src_groupdata == $loc_groupdata ]]; then
            echo "SKIP $group" | tee -a $LOG_FILE
            continue
        fi
        
        
        # Parse /etc/group data
        IFS=$'\n'
        for result in ${src_groupdata}; do
            # echo "[DEBUG]:             result $result"
            GNAME=""
            PWORD=""
            GID=""
            MLIST=""

            key=0
            IFS=':'
            for dat in ${result}; do

                case ${key} in
                    0)
                        # echo "[DEBUG]:                        dat[$key] $dat"
                        GNAME=$dat
                        key=1
                        ;;
                    1)
                        # echo "[DEBUG]:                        dat[$key] $dat"
                        PWORD=$dat
                        key=2
                        ;;
                    2)
                        # echo "[DEBUG]:                        dat[$key] $dat"
                        GID=$dat
                        key=3
                        ;;
                    3)
                        # echo "[DEBUG]:                        dat[$key] $dat"
                        MLIST=$dat
                        key=0
                        ;;
                esac
            done
            IFS=$'\n'
            
            if [[ $GNAME != $group ]]; then
                # echo "[DEBUG]: Ignoring $GNAME"
                continue
            fi

            # echo "[DEBUG]:$src_groupdata"
            # echo "[DEBUG]:groupadd
            # groupname   : $GNAME
            # password    : $PWORD
            # gid         : $GID
            # memberlist  : $MLIST
            # "
            # We know that the root group password is to be hardcoded as root
            # We also know that the system will have a root group.. no need to create it again
            if [[ $GNAME == "root" ]]; then
                # echo "[DEBUG]: echo 'root:root' | chgpasswd"
                echo 'root:root' | chgpasswd
                echo "GROUP (root) updated" | tee -a $LOG_FILE
                continue
            else
                echo "[DEBUG]: groupadd -g $GID $GNAME"
                groupadd -g $GID $GNAME
                if [[ $? -eq 0 ]]; then
                    echo "GROUP ($GNAME) Created" | tee -a $LOG_FILE
                else
                    # Increment the group ID number to make it 'unique' to the new system
                    GID=$((GID+1))
                    groupadd -g $GID $GNAME
                    if [[ $? -eq 0 ]]; then
                        echo "GROUP ($GNAME) Created" | tee -a $LOG_FILE
                        # TODO (BAR): Update the $SRC_GROUPS file with the new GID
                    else
                        echo "ERROR: GROUP ($GNAME) GID:$GID cannot be created" | tee -a $LOG_FILE
                    fi
                fi
            fi

            DAT_IFS=$IFS
            IFS=","
            for user in ${MLIST}; do
                echo "usermod -a -G $GNAME $user" | tee -a $LOG_FILE
                usermod -a -G $GNAME $user
                echo "GROUP ($user) added to $GNAME" | tee -a $LOG_FILE
            done
            IFS=$DAT_IFS
            IFS=$PREV_IFS

            if [[ $PWORD == "x" ]]; then
                # Check the migrated /etc/shadow for the encrypted password
                PASSWD_FILE=$(echo $SRC_WD/$MIGRATE/etc/gshadow | sed 's/\/\//\//g')
                if [[ -f $PASSWD_FILE ]]; then
                    passwordline=$(cat $PASSWD_FILE | grep $GNAME)
                    # echo -e "[DEBUG]: echo '$passwordline' >> /etc/gshadow\n\n"
                    echo '$passwordline' >> /etc/shadow
                    echo "GROUP $GNAME password updated" | tee -a $LOG_FILE
                else
                    echo "ERROR: Unable to set password for $GNAME" | tee -a $LOG_FILE
                fi
            fi
        done
    done

    IFS=$PREV_IFS
}

capture_dmseg ()
{
    echo -e "\n\n  Capturing dmesg...\n" | tee -a $LOG_FILE
    
    CONFIG_WD=$TMP_WD/$CONFIG
    mkdir -p $CONFIG_WD && dmesg > $CONFIG_WD/dmsg
}

package_snapshot ()
{   # Must supply a destination argument
    # Prepares links to files and 'package_snapshot' them in the TMP_WD/migrate directory
    
    DST_WD=$TMP_WD
    DST_WD=$(echo $DST_WD | sed 's/\/\//\//g')

    # echo -e "\n\n  Packaging files...\n"
    # Package the files up
    packagefile=$(echo $TMP_WD/$MIGRATE_FILE | sed 's/\/\//\//g')
    # echo "[DEBUG]: Packagefile $packagefile migrate_wd $DST_WD"
    tar -zcvpf $packagefile $DST_WD
    if [[ $? -eq 0 ]]; then
        echo "TAR $packagefile $DST_WD Successful"
    else
        echo "TAR $packagefile $DST_WD Unsuccessful"
        exit 1
    fi
}

clean ()
{  
    echo -e "\n\n  Cleaning...\n" | tee -a $LOG_FILE
    rm -rf $TMP_WD
}


usage ()
{
    echo -e "\nUsage:  system_migrate [option]"
    echo -e "\nScans for dependencies on an old or deprecated machine and installs those dependencies onto new machine."
    echo -e "Dependencies include directories, files, links, users, groups and services that are needed for the system"
    echo -e "to be fully operational."
    echo -e "\nArguments:"
    echo -e "        -i, --install [source]     Automatically detect and replace needed directories"
    echo -e "        -s, --scan                 Scan image for required dependencies and stage dependencies for export"
    echo -e "        -v, --version              Display script version information"
    echo -e "        -h, --help                 Display this help menu"
    echo -e "\nExamples:"
    echo -e "\nsystem_migrate -s                  Scans the filesystem for dependencies; creates metadata files"
    echo -e "                                   and stages files and metadata into /tmp/\n"
    echo -e "\nsystem_migrate -i /root/         Checks for missing dependencies, installs the required dependencies"
    echo -e "                                   from the source directory, /root/\n"
    echo -e "\nUsing the tool:"
    echo -e "1. Run this tool on the system to be migrated. This will analyze the filesystem, and stage the files to be migrated in /tmp/migrate.tar.gz"
    echo -e "   [root@alarmpi /]# ./system_migrate -s\n "
    echo -e "2. Retrieve the files and metadata from the scan from a remote system:"
    echo -e "   user@remote-system:~/$ sshpass -p root scp root@<ip>:/tmp/migrate.tar.gz . \n"
    echo -e "3. Send this script and the ~/ directory to the targeted machine:"
    echo -e "   user@remote-system:~/$ sshpass -p root scp system_migrate root@<ip>: "
    echo -e "   user@remote-system:~/$ sshpass -p root scp migrate.tar.gz root@<ip>: \n"
    echo -e "4. Invoke the target machine to scan the new environment:"
    echo -e "   user@remote-system:~/$ sshpass -p root ssh -o 'StrictHostKeyChecking=no' root@<ip> 'sys_migrate -s\n"
    echo -e "5. Invoke the target machine to install all missing dependencies:"
    echo -e "   user@remote-system:~/$ sshpass -p root ssh -o 'StrictHostKeyChecking=no' root@<ip> 'sys_migrate -i /home/root/\n"
    echo -e "6. Reboot the target system"
    echo -e "   "
}

display_version ()
{
    echo -e "system_migrate Version $VERSION\n"
}

scan_dependencies ()
{
    scan_users
    scan_groups
    scan_directories
    scan_files
    scan_commands
    scan_configs 
    scan_services 
    scan_devices
    capture_dmseg

    if [[ $MACHINE == *"ARCH"* ]]; then
        package_snapshot
    fi
}

install_dependencies ()
{
    if [[ $MACHINE == *"WSL"* && $MACHINE != *"ARCH"* ]]; then
        echo -e "\n\n You probably don't want to install this to your personal machine, dummy"
        exit
    fi

    INSTALL_WD=$1
    packagefile=$(echo $INSTALL_WD/$MIGRATE_FILE | sed 's/\/\//\//g')
    if [[ ! -f $packagefile ]]; then
        echo "ERROR: $packagefile not found" | tee -a $LOG_FILE
        exit 1
    else
        tar -zxvf $packagefile -C $INSTALL_WD
        if [[ $? -eq 0 ]]; then
            echo "UNTAR $packagefile Successful" | tee -a $LOG_FILE
        else
            echo "UNTAR $packagefile Unsuccessful" | tee -a $LOG_FILE
            exit 1
        fi
    fi      

    create_groups $INSTALL_WD/$TMP_WD
    create_users $INSTALL_WD/$TMP_WD
    install_directories $INSTALL_WD/$TMP_WD
    install_files $INSTALL_WD/$TMP_WD
    install_commands $INSTALL_WD/$TMP_WD
    install_configs $INSTALL_WD/$TMP_WD
    install_services $INSTALL_WD
}

### MAIN STARTS HERE ###

# Root privelege check
if [[ ! $(echo $UID) -eq 0 ]]; then
    echo -e "\n  ERROR: system_migrate must be run as root\n"
    exit 1
fi

# Differentiate between old or new machine
MACHINE=$(uname -a | awk '{print substr($3,1)}' | tr -d '\n')
echo "Executing system_migrate from $MACHINE"

mkdir -p $TMP_WD
echo "system_migrate Log" > $LOG_FILE

# Parse args
while getopts ":i:svh-" option; do
    case ${option} in
        i | -install)
            install_dependencies $OPTARG
        exit;;
        s | -scan)
            scan_dependencies
        exit;;
        v | -version)
            display_version
        exit;;
        h | -help)
            usage
        exit;;
        /? )
            echo "-$OPTARG is not a valid option" | tee -a $LOG_FILE
            usage
        exit;;
        : )
            echo "Supply an option dummy" | tee -a $LOG_FILE
        exit;;
    esac
    shift $((OPTIND - 1))
done

echo -e "\n\n  Finished...\n" | tee -a $LOG_FILE
