#!/bin/bash
# echo '* * * * * root /vddos/auto-switch/vddos-sensor.sh' >> /etc/crontab

# if you usually backup on Thursday, you might want to disable cpu, ram... check on Thursday (because it can misrepresent when cpu, network... highload because of backup operation)
# today=`date '+%A'`
# backup_yn=n
# if [ $today = "Thursday" ]; then
# backup_yn=y
# fi

# Check vddos-sensor still running?

if [ -f /vddos/auto-switch/vddos-sensor.tmp ] || [ -f /vddos/auto-switch/vddos-autoswitch.tmp ]; then
exit 0
fi



source /vddos/auto-switch/setting.conf
touch /vddos/auto-switch/vddos-sensor.tmp

if [ ! -f /usr/bin/vddos-switch ] || [ ! -f /usr/bin/vddos-autoswitch ] || [ ! -f /usr/bin/vddos-sensor ]; then
chmod 700 /vddos/auto-switch/*.sh  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-autoswitch.sh /usr/bin/vddos-autoswitch  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-switch.sh /usr/bin/vddos-switch  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-sensor.sh /usr/bin/vddos-sensor  >/dev/null 2>&1
fi
if [ ! -f /vddos/auto-switch/protect/waiting-time-to-release.db ]; then
	mkdir -p /vddos/auto-switch/protect/
	touch /vddos/auto-switch/protect/waiting-time-to-release.db
fi


################################################################################
# SET MAX LIMIT:
# If the following 8 indicators are exceeded, vDDoS will enable challenge mode:

CPU_Problems_Sensor_MAX_Limit=$(grep -c processor /proc/cpuinfo)				#Max number of cores the server has to enable_challenge
RAM_Problems_Sensor_MAX_Limit=90												#Max RAM the server can use (unit of measure: %) to enable_challenge
IOdisk_Problems_Sensor_MAX_Limit=70												#Limit 70% IO Disk to enable_challenge
NET_Problems_Sensor_MAX_Limit=10000												#Max Bandwidth/sec of IN + OUT combined (unit of measure: kB/s)
Connections_Problems_Sensor_MAX_Limit=10000										#Max connections/sec
IPconnections_Problems_Sensor_MAX_Limit=1000									#Max number IPs connect
status444_Problems_Sensor_MAX_Limit=10											#Percentage of Deny/Allow connections (unit of measure: %)
Backendstatus_Problems_Sensor_MAX_Limit=$maximum_allowable_delay_for_backend	




function disable_challenge ()
{
vddos-switch allsite $default_switch_mode_not_attack

if [ "$vddos_master_slave_mode" = "no" ]; then
	vddos reload
else
	vddos reload; vddos-master synall; vddos-master reloadall
fi

return
}


function check_waiting_time ()
{
time_remaining=`cat  /vddos/auto-switch/protect/waiting-time-to-release.db| grep ^$1 | awk 'NR==1 {print $2}'`
if [ "$time_remaining" = "" ]; then
	echo "


  Checking: [$1] not on the protected list (waiting-time-to-release.db)" 
	already_protected_yn=n
	out_of_time_yn=""
else
	already_protected_yn=y
	the_present_time=`date +"%s"`
	echo "


  Checking: [$1] already on the protected list (waiting-time-to-release.db)" 
	if [ "$the_present_time" > "$time_remaining"  ] ; then
		out_of_time_yn=y; 
	else
		out_of_time_yn=n;
	fi
	
fi
return
}

function put_waiting_time ()
{
	sed -i "/^$1.*/d" /vddos/auto-switch/protect/waiting-time-to-release.db  >/dev/null 2>&1
	the_present_time=`date +"%s"`
	waiting_time=`date +"%s" -d '+ '$default_waiting_time_to_release' minutes'`
	echo "$1 $waiting_time (set at $the_present_time)" >> /vddos/auto-switch/protect/waiting-time-to-release.db
return
}


check_waiting_time allsite
((time_remaining>the_present_time)) && out_of_time_yn=n
((time_remaining<the_present_time)) && out_of_time_yn=y
if [ "$already_protected_yn" = "y" ] && [ "$out_of_time_yn" = "n" ] ; then
	already_allsite_yn=y 
	echo "===> [SKIP, [allsite] will be released later... ($(((the_present_time-time_remaining)*-1)) seconds left)]"
	rm -f /vddos/auto-switch/vddos-sensor.tmp
	exit 0
fi

if [ "$already_protected_yn" = "y" ] && [ "$out_of_time_yn" = "y" ]; then
	echo "===> [CONGRATULATIONS, [allsite] released at `date`]"
	echo > /vddos/auto-switch/protect/waiting-time-to-release.db
	disable_challenge
	if [ "$send_notifications" = "yes" ] && [ "$notifications_yn" = "y" ]; then
	send_notifications
	fi
	rm -f /vddos/auto-switch/vddos-sensor.tmp
	exit 0
fi


function send_notifications ()
{
now=`date +"TIME:%Hh%M_DATE:%d"`
subject="[$now] CPU: $CPU_Problems_Sensor_Current_Now/$CPU_Problems_Sensor_MAX_Limit(Core) | RAM: $RAM_Problems_Sensor_Current_Now(%) | IO: $IOdisk_Problems_Sensor_Current_Now(%) | NET: $NET_Problems_Sensor_Current_Now(kB/s) | Connections: $Connections_Problems_Sensor_Current_Now | $IPconnections_Problems_Sensor_Current_Now(IP) | BACKEND: $Backendstatus"
tail -n200 /vddos/auto-switch/log.txt >> /vddos/auto-switch/send_notifications.tmp
body=`cat /vddos/auto-switch/send_notifications.tmp`

/vddos/auto-switch/sendmsg.sh -s "$subject" -m "$body" -f "$hostname <$smtp_username>" -S "$smtp_server" -u "$smtp_username" -p "$smtp_password" -t "Receiver <$send_notifications_to>"
rm -f /vddos/auto-switch/send_notifications.tmp
return
}

function enable_challenge ()
{
vddos-switch allsite $default_switch_mode_under_attack

if [ "$vddos_master_slave_mode" = "no" ]; then
	vddos reload
else
	vddos reload; vddos-master synall; vddos-master reloadall
fi

return
}

function log_overload ()
{
echo '===> WARNING: '$1'-Overload '$2'/'$3'' |tee -a /vddos/auto-switch/send_notifications.tmp
return
}

################################################################################
# CURRENT NOW:
BWsar="`sar -n DEV 1 1`"
NETBW_IN=$(echo "scale=3;(`echo "$BWsar"|grep Average:| grep -v "IFACE"| awk {'print $5'} |tr "\n" "+"`0)"| bc -q| awk '{printf "%.0f\n", $0}')
NETBW_OUT=$(echo "scale=3;(`echo "$BWsar"|grep Average:| grep -v "IFACE"| awk {'print $6'} |tr "\n" "+"`0)"| bc -q| awk '{printf "%.0f\n", $0}')
io_raw=`cat  <(cat /sys/block/sda/stat && cat /proc/uptime) <(sleep 1 && cat /sys/block/sda/stat && cat /proc/uptime)`
a1=`echo "$io_raw" | awk 'NR==1 {print $10}'| tr . " "| awk '{printf $1}'`;a2=`echo "$io_raw" | awk 'NR==3 {print $10}'| tr . " "| awk '{printf $1}'`;
b1=`echo "$io_raw" | awk 'NR==2 {print $1}'| tr . " "| awk '{printf $1}'`;b2=`echo "$io_raw" | awk 'NR==4 {print $1}'| tr . " "| awk '{printf $1}'`;
IO=$(((a2-a1)/(b2-b1)/10))
RAM_Now=$(free -m| awk 'NR==2 {print $3}')	
RAM_MAX=$(free -m| awk 'NR==2 {print $2}')

CPU_Problems_Sensor_Current_Now=$(cat /proc/loadavg |tr . " " | awk {'print $1'}) 	#LoadAVG now (number of cores needed - unit of measure: cpu or core)
RAM_Problems_Sensor_Current_Now=$((RAM_Now*100/RAM_MAX))							#RAM Used now (unit of measure: %)
IOdisk_Problems_Sensor_Current_Now=$IO 												#Current IO usage percentage (unit of measure: %)


NET_Problems_Sensor_Current_Now=$((NETBW_IN+NETBW_OUT))								#Total net-traffic used by the server in 1 second (unit of measure: KB/s)
Connections_Problems_Sensor_Current_Now=$(netstat -n | grep :| wc -l)				#Total connections to server in 1 second
IPconnections_Problems_Sensor_Current_Now=$(netstat -anp |grep 'tcp\|udp' | awk '{print $5}' | cut -d: -f1 | sort | uniq -c| wc -l) # Number of IPs connected to the server


echo "
	[[[[[[[ `date` ]]]]]]

	SERVER ($hostname) Current Status:
	-CPU used: $CPU_Problems_Sensor_Current_Now/$CPU_Problems_Sensor_MAX_Limit(core)
	-RAM used: $RAM_Problems_Sensor_Current_Now%
	-IO Disk used: $IOdisk_Problems_Sensor_Current_Now%

	-Network: $NET_Problems_Sensor_Current_Now(kB/s)
	-Connections per second: $Connections_Problems_Sensor_Current_Now(connections/s)
	-Number of IPs connected per second: $IPconnections_Problems_Sensor_Current_Now(IP/s)
" |tee -a /vddos/auto-switch/log.txt


################################################################################
# IF CURRENT NOW > MAX LIMIT ----> WHAT TO DO:

enable_challenge_yn=n

if [ "$CPU_Problems_Sensor_Current_Now" -gt "$CPU_Problems_Sensor_MAX_Limit" ]; then 
	log_overload CPU $CPU_Problems_Sensor_Current_Now $CPU_Problems_Sensor_MAX_Limit;
	enable_challenge_yn=y
	
fi
if [ "$RAM_Problems_Sensor_Current_Now" -gt "$RAM_Problems_Sensor_MAX_Limit" ]; then 
	log_overload RAM $RAM_Problems_Sensor_Current_Now $RAM_Problems_Sensor_MAX_Limit; 
	enable_challenge_yn=y
fi
if [ "$IOdisk_Problems_Sensor_Current_Now" -gt "$IOdisk_Problems_Sensor_MAX_Limit" ]; then 
	log_overload IOdisk $IOdisk_Problems_Sensor_Current_Now $IOdisk_Problems_Sensor_MAX_Limit; 
	enable_challenge_yn=y
fi

if [ "$NET_Problems_Sensor_Current_Now" -gt "$NET_Problems_Sensor_MAX_Limit" ]; then 
	log_overload NET $NET_Problems_Sensor_Current_Now $NET_Problems_Sensor_MAX_Limit; 
	enable_challenge_yn=y
fi
if [ "$Connections_Problems_Sensor_Current_Now" -gt "$Connections_Problems_Sensor_MAX_Limit" ]; then 
	log_overload Connections $Connections_Problems_Sensor_Current_Now $Connections_Problems_Sensor_MAX_Limit; 
	enable_challenge_yn=y
fi
if [ "$IPconnections_Problems_Sensor_Current_Now" -gt "$IPconnections_Problems_Sensor_MAX_Limit" ]; then 
	log_overload IPconnections $IPconnections_Problems_Sensor_Current_Now $IPconnections_Problems_Sensor_MAX_Limit; 
	enable_challenge_yn=y
fi

if [ "$backend_url_check" != "no" ]; then
	Backendstatus_Problems_Sensor_Current_Now=`curl --insecure --user-agent "vDDoS Auto Sensor Switch Check" --connect-timeout $maximum_allowable_delay_for_website --max-time $maximum_allowable_delay_for_website -s -o /dev/null -L -I -w "%{http_code}" $backend_url_check | awk '{print substr($0,1,1)}'`
	if [ "$Backendstatus_Problems_Sensor_Current_Now" != "2" ] && [ "$Backendstatus_Problems_Sensor_Current_Now" != "3" ]; then
		echo ' Found Backend ['$backend_url_check'] seems to be in the offline state: ['$Backendstatus_Problems_Sensor_Current_Now'xx']|tee -a /vddos/auto-switch/log.txt
		Backendstatus=DOWN
		enable_challenge_yn=y
	fi
	if [ "$Backendstatus_Problems_Sensor_Current_Now" = "2" ] || [ "$Backendstatus_Problems_Sensor_Current_Now" = "3" ]; then
		echo '- Re-check: ['$backend_url_check'] seems to be in the online state: ['$Backendstatus_Problems_Sensor_Current_Now'xx] ===> Skip!'|tee -a /vddos/auto-switch/log.txt
		Backendstatus=UP
	fi
else
	Backendstatus='no'
fi


if [ "$enable_challenge_yn" = "y" ]; then 
	notifications_yn=y
	if [ "$backup_yn" != "y" ]; then 
	put_waiting_time allsite;
	enable_challenge; 
	fi
fi


function status444_calculator ()
{
rawcons=`tail -n500 /var/log/vddos/$1.access.log|awk 'NF'`; echo "   Check 444 logs: $1"
allcons=$(echo "$rawcons"|awk 'NF'|grep -v access.log| wc -l);  if [ "$allcons" = "0" ]; then allcons=1; fi; echo " + $allcons (number of connections obtained)"
only444=$(echo "$rawcons"|grep ' "444" '| wc -l); echo " + $only444 (connection 444)"
status444_Problems_Sensor_Current_Now=$((only444*100/allcons)); echo "   --> Result: $status444_Problems_Sensor_Current_Now%"
return
}

if [ "$enable_challenge_yn" = "n" ]; then 
	vddosreload_yn=n
	ls -1 /var/log/vddos/|grep -v error.log|grep -v 444.log|grep -v ^access.log|awk '{ print substr( $0, 1, length($0)-11 ) }' > /vddos/auto-switch/status444.tmp
	ten_file_chua_list="/vddos/auto-switch/status444.tmp"
	so_dong_file_chua_list=`cat $ten_file_chua_list | grep . | wc -l`
	so_dong_bat_dau_tim=1
	dong=$so_dong_bat_dau_tim
	while [ $dong -le $so_dong_file_chua_list ]
	do
	ten=$(awk " NR == $dong " $ten_file_chua_list)
	#
	check_waiting_time $ten
	((time_remaining>the_present_time)) && out_of_time_yn=n
	((time_remaining<the_present_time)) && out_of_time_yn=y
		if [ "$already_protected_yn" = "y" ] && [ "$out_of_time_yn" = "n" ]; then
			skip_yn=y
			echo "===> [SKIP, $ten will be released later... ($(((the_present_time-time_remaining)*-1)) seconds left)]"
		fi

		if [ "$already_protected_yn" = "y" ] && [ "$out_of_time_yn" = "y" ]; then
			echo "===> [CONGRATULATIONS, $ten released at `date`]"
			sed -i "/^$ten.*/d" /vddos/auto-switch/protect/waiting-time-to-release.db  >/dev/null 2>&1
			vddos-switch "$ten" "$default_switch_mode_not_attack"
			vddosreload_yn=y
		fi
		
		if [ "$already_protected_yn" = "n" ] ; then
			status444_calculator $ten
			if [ "$status444_Problems_Sensor_Current_Now" -gt "$status444_Problems_Sensor_MAX_Limit" ]; then 
				log_overload "$ten"_status444 "$status444_Problems_Sensor_Current_Now" "$status444_Problems_Sensor_MAX_Limit";
				echo '===> WARNING: '$ten' status444: '$status444_Problems_Sensor_Current_Now'%' |tee -a /vddos/auto-switch/send_notifications.tmp
				challenge_extended_to=`date -d '+ '$default_waiting_time_to_release' minutes'`
				echo "===> WARNING: Turn on the challenge for the domain $ten $default_waiting_time_to_release minutes [Will be released at: $challenge_extended_to]" |tee -a /vddos/auto-switch/send_notifications.tmp
				vddos-switch "$ten" "$default_switch_mode_under_attack"
				put_waiting_time $ten;
				vddosreload_yn=y
			else
				echo '===> SKIP!'
			fi
		fi


	#
	dong=$((dong + 1))
	done
	rm -f $ten_file_chua_list


	if [ "$vddosreload_yn" = "y" ]; then 
		if [ "$vddos_master_slave_mode" = "no" ]; then
			vddos reload
		else
			vddos reload; vddos-master synall; vddos-master reloadall
		fi
		notifications_yn=y
	fi
fi


if [ "$send_notifications" = "yes" ] && [ "$notifications_yn" = "y" ]; then
	send_notifications
fi
##################################################################################












# Notification vddos-sensor End:
rm -f /vddos/auto-switch/send_notifications.tmp
rm -f /vddos/auto-switch/vddos-sensor.tmp

