#!/bin/bash

#chmod 700 /vddos/auto-switch/vddos-autoswitch.sh
#ln -s /vddos/auto-switch/vddos-autoswitch.sh /usr/bin/vddos-autoswitch
#chmod 700 /vddos/auto-switch/vddos-switch.sh
#ln -s /vddos/auto-switch/vddos-switch.sh /usr/bin/vddos-switch

# Example:
# Auto check/switch security mode for a domain (in website.conf) if it is being slow/high load:
# vddos-autoswitch [checkdomain] your-domain.com 5s

# Auto check/switch security mode for each domain in the list website.conf if it is being slow/high load:
# vddos-autoswitch [checkalldomain] 5s

# Auto check/switch for each domain in the list domains if it is being slow/high load:
# vddos-autoswitch [checklist] /etc/listdomains.txt 5s

# Flush all security mode for all domain (in website.conf) if they are not slow/high load:
# vddos-autoswitch [flushalldomain] /etc/listdomains.txt no
# OR:
# vddos-switch [allsite] [no/307/200...] ; vddos restart



if [ ! -f /usr/bin/vddos-switch ] || [ ! -f /usr/bin/vddos-autoswitch ] || [ ! -f /usr/bin/vddos-sensor ]; then
chmod 700 /vddos/auto-switch/*.sh  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-autoswitch.sh /usr/bin/vddos-autoswitch  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-switch.sh /usr/bin/vddos-switch  >/dev/null 2>&1
ln -s /vddos/auto-switch/vddos-sensor.sh /usr/bin/vddos-sensor  >/dev/null 2>&1
fi
source /vddos/auto-switch/setting.conf

if [ -f /vddos/auto-switch/vddos-sensor.tmp ]; then
exit 0
fi
touch /vddos/auto-switch/vddos-autoswitch.tmp

function showerror()
{
echo 'ERROR!

Command is ['$1'] ...
Website or List is ['$2'] ...
Security mode is ['$3']

# Example:
# Auto check/switch security mode for a domain (in website.conf) if it is being slow/high load:
 vddos-autoswitch [checkdomain] your-domain.com 5s

# Auto check/switch security mode for each domain in the list website.conf if it is being slow/high load:
 vddos-autoswitch [checkalldomain] 5s

# Auto check/switch for each domain in the list domains if it is being slow/high load:
 vddos-autoswitch [checklist] /etc/listdomains.txt 5s


# Flush all security mode for all domain (in website.conf) if they are not slow/high load:
 vddos-switch [allsite] no
# OR:
 vddos-switch [allsite] [no/307/200...]

'|tee -a /vddos/auto-switch/log.txt
return 0
}
function checklog()
{
echo '
(Check logs at /vddos/auto-switch/log.txt)
'
return 0
}






Command="$1"
Security_mode="$3"


if [ "$1" = "" ] || [ "$2" = "" ]; then
showerror
rm -f /vddos/auto-switch/vddos-autoswitch.tmp
exit 0
fi	

if [ "$Command" != "checkdomain" ] && [ "$Command" != "checklist" ] && [ "$Command" != "checkalldomain" ];  then
showerror
rm -f /vddos/auto-switch/vddos-autoswitch.tmp
exit 0
fi

if [ "$Command" = "checkdomain" ] || [ "$Command" = "checklist" ];  then
if [ "$3" = "" ]; then
showerror
rm -f /vddos/auto-switch/vddos-autoswitch.tmp
exit 0
fi
fi



if [ "$Command" = "checkdomain" ]; then
	echo "
		[[[[[[[ `date` ]]]]]]]
	" > /vddos/auto-switch/log.txt

	md5sum_website_conf_latest=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`

	Website="$2"
	Available=`awk -F: "/^$Website/" /vddos/conf.d/website.conf`
	WebsiteSecurityModeCurrent=`awk -F: "/^$Website/" /vddos/conf.d/website.conf| awk 'NR==1 {print $5}'`
	if [ "$Available" = "" ]; then
		echo '- Re-check: ['$Website'] is not available in /vddos/conf.d/website.conf ===> Skip!'|tee -a /vddos/auto-switch/log.txt
	fi
	if [ "$Available" != "" ]; then
		if [ "$WebsiteSecurityModeCurrent" = "$Security_mode" ]; then
			echo '- Re-check: ['$Website'] is already ['$WebsiteSecurityModeCurrent'] security mode ===> Skip!'|tee -a /vddos/auto-switch/log.txt
		fi
		if [ "$WebsiteSecurityModeCurrent" != "$Security_mode" ]; then
			websitestatus=`curl --user-agent "vDDoS Auto Switch Check" --connect-timeout $maximum_allowable_delay_for_website --max-time $maximum_allowable_delay_for_website -s -o /dev/null -L -I -w "%{http_code}" $Website | awk '{print substr($0,1,1)}'`
			if [ "$websitestatus" != "2" ] && [ "$websitestatus" != "3" ]; then
				echo ' Found ['$Website'] in /vddos/conf.d/website.conf seems to be in the offline state: ['$websitestatus'xx']|tee -a /vddos/auto-switch/log.txt
				/usr/bin/vddos-switch $Website $Security_mode
			fi
			if [ "$websitestatus" = "2" ] || [ "$websitestatus" = "3" ]; then
				echo '- Re-check: ['$Website'] seems to be in the online state: ['$websitestatus'xx] ===> Skip!'|tee -a /vddos/auto-switch/log.txt
			fi
		fi
	fi
	md5sum_website_conf_new=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`
	if [ "$md5sum_website_conf_latest" != "$md5sum_website_conf_new" ]; then
		/usr/bin/vddos reload |tee -a /vddos/auto-switch/log.txt
	fi
	checklog
	rm -f /vddos/auto-switch/vddos-autoswitch.tmp
	exit 0
fi

if [ "$Command" = "checklist" ]; then
	listdomains_source="$2";
	listdomains="/vddos/auto-switch/list/listdomains.txt"
	if [ ! -f $listdomains_source ]; then
		showerror
		echo ''$listdomains_source' not found!'
		rm -f /vddos/auto-switch/vddos-autoswitch.tmp
		exit 0
	fi

	if [ ! -d /vddos/auto-switch/list/ ]; then
		mkdir -p /vddos/auto-switch/list/
	fi

	md5sum_website_conf_latest=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`

	echo "
		[[[[[[[ `date` ]]]]]]]
	" > /vddos/auto-switch/log.txt
	echo "`cat $listdomains_source | grep . | awk '!x[$0]++'`" > $listdomains
	numberlinelistdomains=`cat $listdomains | grep . | wc -l`
	startlinenumber=1

	dong=$startlinenumber
	while [ $dong -le $numberlinelistdomains ]
	do
		echo $dong
		Website=`cat $listdomains|awk 'NR == '$dong' {print $1}'`; echo " $Website "
		URL_Website=`cat $listdomains|awk  'NR == '$dong' {print $2}'`; echo " $URL_Website "
		Available=`awk -F: "/^$Website/" /vddos/conf.d/website.conf`
		WebsiteSecurityModeCurrent=`awk -F: "/^$Website/" /vddos/conf.d/website.conf| awk 'NR==1 {print $5}'`
		if [ "$Available" = "" ]; then
			echo '- Re-check: ['$Website'] is not available in /vddos/conf.d/website.conf ===> Skip!'|tee -a /vddos/auto-switch/log.txt
		fi
		if [ "$URL_Website" = "" ]; then
			if [ "$Available" != "" ]; then
				if [ "$WebsiteSecurityModeCurrent" = "$Security_mode" ]; then
					echo '- Re-check: ['$Website'] is already ['$WebsiteSecurityModeCurrent'] security mode ===> Skip!'|tee -a /vddos/auto-switch/log.txt
				fi
				if [ "$WebsiteSecurityModeCurrent" != "$Security_mode" ]; then
					if [ "$Available" != "" ]; then
						websitestatus=`curl --user-agent "vDDoS Auto Switch Check" --connect-timeout $maximum_allowable_delay_for_website --max-time $maximum_allowable_delay_for_website -s -o /dev/null -L -I -w "%{http_code}" $Website | awk '{print substr($0,1,1)}'`
						if [ "$websitestatus" != "2" ] && [ "$websitestatus" != "3" ]; then
							echo ' Found ['$Website'] in '$listdomains_source' seems to be in the offline state: ['$websitestatus'xx']|tee -a /vddos/auto-switch/log.txt
							/usr/bin/vddos-switch $Website $Security_mode
						fi
						if [ "$websitestatus" = "2" ] || [ "$websitestatus" = "3" ]; then
							echo '- Re-check: ['$Website'] seems to be in the online state: ['$websitestatus'xx] ===> Skip!'|tee -a /vddos/auto-switch/log.txt
						fi
					fi
				fi
			fi
		fi
		if [ "$URL_Website" != "" ]; then
			if [ "$Available" != "" ]; then
				if [ "$WebsiteSecurityModeCurrent" = "$Security_mode" ]; then
					echo '- Re-check: ['$URL_Website'] is already ['$WebsiteSecurityModeCurrent'] security mode ===> Skip!'|tee -a /vddos/auto-switch/log.txt
				fi
				if [ "$WebsiteSecurityModeCurrent" != "$Security_mode" ]; then
					if [ "$Available" != "" ]; then
						websitestatus=`curl --user-agent "vDDoS Auto Switch Check" --connect-timeout $maximum_allowable_delay_for_website --max-time $maximum_allowable_delay_for_website -s -o /dev/null -L -I -w "%{http_code}" $URL_Website | awk '{print substr($0,1,1)}'`
						if [ "$websitestatus" != "2" ] && [ "$websitestatus" != "3" ]; then
							echo ' Found ['$URL_Website'] in '$listdomains_source' seems to be in the offline state: ['$websitestatus'xx']|tee -a /vddos/auto-switch/log.txt
							/usr/bin/vddos-switch $Website $Security_mode
						fi
						if [ "$websitestatus" = "2" ] || [ "$websitestatus" = "3" ]; then
							echo '- Re-check: ['$URL_Website'] seems to be in the online state: ['$websitestatus'xx] ===> Skip!'|tee -a /vddos/auto-switch/log.txt
						fi
					fi
				fi
			fi
		fi


		dong=$((dong + 1))
	done

	md5sum_website_conf_new=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`
	if [ "$md5sum_website_conf_latest" != "$md5sum_website_conf_new" ]; then
		/usr/bin/vddos reload |tee -a /vddos/auto-switch/log.txt
	fi
	checklog
	rm -f /vddos/auto-switch/vddos-autoswitch.tmp
	exit 0
fi



if [ "$Command" = "checkalldomain" ]; then
	Security_mode="$2"
	listdomains_source="/vddos/conf.d/website.conf"
	listdomains="/vddos/auto-switch/checkalldomain/listdomains.txt"
	if [ ! -f $listdomains_source ]; then
		showerror
		echo ''$listdomains_source' not found!'
		rm -f /vddos/auto-switch/vddos-autoswitch.tmp
		exit 0
	fi

	if [ ! -d /vddos/auto-switch/checkalldomain/ ]; then
		mkdir -p /vddos/auto-switch/checkalldomain/
	fi

	echo "
		[[[[[[[ `date` ]]]]]]]
	" > /vddos/auto-switch/log.txt
	echo "`cat $listdomains_source | grep .| awk '!x[$0]++'|grep -v '^#'|grep -v '^*'|grep -v '^default' | awk '{print $1" "$2}'| tr : " " |awk '{print $1" "$2"://"$1":"$4"/"}'`" > $listdomains

	/usr/bin/vddos-autoswitch checklist $listdomains $Security_mode
	rm -f /vddos/auto-switch/vddos-autoswitch.tmp
	exit 0
fi




if [ "$Command" = "flushalldomain" ]; then
	listdomains_source="$2"
	listdomains="/vddos/auto-switch/flushalldomain/listdomains.txt"
	if [ ! -f $listdomains_source ]; then
		showerror
		echo ''$listdomains_source' not found!'
		rm -f /vddos/auto-switch/vddos-autoswitch.tmp
		exit 0
	fi

	if [ ! -d /vddos/auto-switch/flushalldomain/ ]; then
		mkdir -p /vddos/auto-switch/flushalldomain/
	fi

	md5sum_website_conf_latest=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`

	echo "
		[[[[[[[ `date` ]]]]]]]
	" > /vddos/auto-switch/log.txt
	echo "`cat $listdomains_source | grep .|grep -v '^#'|grep -v '^*' | awk '{print $1}'| awk '!x[$0]++'`" > $listdomains
	numberlinelistdomains=`cat $listdomains | grep . | wc -l`
	startlinenumber=1

	dong=$startlinenumber
	while [ $dong -le $numberlinelistdomains ]
	do
		Website=$(awk " NR == $dong " $listdomains);
		Available=`awk -F: "/^$Website/" /vddos/conf.d/website.conf`
		WebsiteSecurityModeCurrent=`awk -F: "/^$Website/" /vddos/conf.d/website.conf| awk 'NR==1 {print $5}'`
		if [ "$Available" = "" ]; then
			echo '- Re-check: ['$Website'] is not available in /vddos/conf.d/website.conf ===> Skip!'|tee -a /vddos/auto-switch/log.txt
		fi
		if [ "$Available" != "" ]; then
			if [ "$WebsiteSecurityModeCurrent" = "$Security_mode" ]; then
				echo '- Re-check: ['$Website'] is already ['$WebsiteSecurityModeCurrent'] security mode ===> Skip!'|tee -a /vddos/auto-switch/log.txt
			fi
			if [ "$WebsiteSecurityModeCurrent" != "$Security_mode" ]; then
				if [ "$Available" != "" ]; then
					/usr/bin/vddos-switch $Website $Security_mode
				fi
			fi
		fi
		dong=$((dong + 1))
	done

	md5sum_website_conf_new=`cat /vddos/conf.d/website.conf| grep . | awk '!x[$0]++'| md5sum | awk 'NR==1 {print $1}'`
	if [ "$md5sum_website_conf_latest" != "$md5sum_website_conf_new" ]; then
		/usr/bin/vddos reload |tee -a /vddos/auto-switch/log.txt
	fi
	checklog
	rm -f /vddos/auto-switch/vddos-autoswitch.tmp
	exit 0
fi

rm -f /vddos/auto-switch/vddos-autoswitch.tmp








