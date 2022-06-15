#!/bin/bash


# *-----------------------------------------------------------------------
# IPMI-Thermostat.sh
#
# Control the server temperature via IMPI calls
#
# Works by checking the temperature reported by the ambient temp sensor,
# and sets the fan speed accordingly
#
# Requires:
# ipmitool (`apt install ipmitool`)
# ------------------------------------------------------------------------

# IPMI SETTINGS:
IPMIHOST=192.168.1.2
IPMIUSER=root
IPMIPW=calvin

# TEMPERATURE TABLE
# If the temp goes above MAXTEMP, it will cause dynamic fan control to kick in (get ready for a loud fan again)
MAXTEMP=35
MINSPEED=0x15

# TODO:
# Create an array (dict) where x = temp, y = fanspeed
# Great example at https://www.shell-tips.com/bash/arrays/#bash-associative-array-dictionaries-hash-table-or-keyvalue-pair
# e.g.
# Temp, Fanspeed
# 27, $MINSPEED
# 28, $($MINSPEED + 0x02) or 0x17
# 29, 0x19
# 30, 0x1b
# 31, 0x1d
# 32, 0x1f
# 33, 0x22
# 34, 0x26
# 35, 0x40

# TODO
# Make a function that determines what the fan output should be, instead of all the if/elifs down below

# TODO: Use the $IPMIHOST and other variables instead of hardcoding the ip address, username, and password

# Send a command to capture the Ambient temp and store to the TEMP variable
# TEMP=$(ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW sdr type temperature | grep Ambient | awk {' print $10 '})
TEMP=$(ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin sdr type temperature | grep Ambient | awk {' print $10 '})

if [[ $TEMP -eq "" ]]; # TODO: We should ping the iDRAC service prior and make sure it's available rather than just checking if the output is blank
  then
    printf "ERROR: Unable to determine server temp!" | systemd-cat -t R710-IPMI-TEMP
    exit -1
elif [[ $TEMP -gt $MAXTEMP ]];
  then
    printf "WARN: ($TEMP C) Temperature too high! Activating dynamic fan control " | systemd-cat -t R710-IPMI-TEMP
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x01
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x01
elif [[ $TEMP -eq 29 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x19" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x19
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y  raw 0x30 0x30 0x02 0xff 0x19
elif [[ $TEMP -eq 30 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x1b" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H $IPMIHOST -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x1b
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y  raw 0x30 0x30 0x02 0xff 0x1b
elif [[ $TEMP -eq 31 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x1d" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x1d
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y  raw 0x30 0x30 0x02 0xff 0x1d
elif [[ $TEMP -eq 32 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x1f" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x1f
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y  raw 0x30 0x30 0x02 0xff 0x1f
elif [[ $TEMP -eq 33 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x22" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x22
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x02 0xff 0x22
elif [[ $TEMP -eq 34 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x26" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x26
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x02 0xff 0x26
elif [[ $TEMP -eq 35 ]];
  then
    printf "Temperature is $TEMP C; Setting fans to 0x40" | systemd-cat -t R710-IPMI-TEMP
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x01 0x00
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H 192.168.1.2 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x40
    # ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y raw 0x30 0x30 0x02 0xff 0x40
else
    printf "Temperature is stable and needs no ($TEMP C)" | systemd-cat -t R710-IPMI-TEMP
fi

