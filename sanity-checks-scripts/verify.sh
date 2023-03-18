## Author : Sagar Fale
script_base=/home/applmgr/scripts_itc
HOSTNAME=`hostname`
mkdir -p /home/applmgr/scripts_itc/sanitychecks_log
HOST=`hostname | awk -F\. '{print $1}'`
tlog=`date "+sanity_checks-%d%b%Y_%H%M".log`
script_base=/home/applmgr/scripts_itc
logfile=`echo /home/applmgr/scripts_itc/sanitychecks_log/${tlog}`

## setting the env
. ../auth-infra-details/colors.env
. ../auth-infra-details/$1-auth-details.env
auth_file=$(realpath ../auth-infra-details/"$1"-auth-details.env)
wlst_conn_additions_temp=$(realpath ../static-files/wlst-conn-additions.txt)
wlst_conn_additions_temp_apex=$(realpath ../static-files/wlst-conn-additions_apex.txt)


. ${ENV_BASE}/EBSapps.env RUN  >> ${logfile}

clear 
echo "*** Running Sanity checks for $TWO_TASK"
echo ""
## DB Check

db_check()
{
   output3=`sqlplus -s apps/${apps_pass} <<EOF
   set feedback off pause off pagesize 0 heading off verify off linesize 500 term off
   select open_mode  from v\\$DATABASE;
   exit
EOF
`
   if [ "$output3" = "READ WRITE" ] 
   then 
   date  >> ${logfile}
   echo -e "${yellow}Database Services on ${DBHOSTS}: ${c_clear}"
   echo -e "DB Connection 					${green}: OK${c_clear}"
   else
   date  >> ${logfile}
   echo -e "DB Connection 					${red}: FAILED${c_clear}" 
   exit
   fi
}
db_check
tnsping_check()
{
tnsping $TWO_TASK | grep OK > /dev/null
		if [ $? -eq 0 ];
			then
  			 	echo -e "TNSping 					${green}: OK${c_clear}"
			else 
				echo -e "TNSping 					${red}: FAILED${c_clear}"
			fi

}
tnsping_check

weblogic_checks()
{

		> /tmp/t1.log
		> /tmp/t2.log
		echo ""
		echo -e "${yellow}EBS Weblogic Services on ${WEBLOGIC_ADMIN_HOST}:${c_clear}"
		echo "adminUsername = '${WeblogicUsername}'" > /tmp/p1.py
		echo "adminPassword = '${WeblogicPassword}'" >> /tmp/p1.py
		weblogic_admin_port=`grep wls_adminport $CONTEXT_FILE | sed -n 's/.*>\(.*\)<\/wls_adminport>/\1/p'`
		echo "adminURL = 't3://${WEBLOGIC_ADMIN_HOST}:${weblogic_admin_port}'" >> /tmp/p1.py
		cat ${wlst_conn_additions_temp} >> /tmp/p1.py
		cd $FMW_HOME/user_projects/domains/EBS_domain*/bin/
		. ./setDomainEnv.sh
		java weblogic.WLST /tmp/p1.py > /tmp/t1.log
		grep -i ServerRuntime /tmp/t1.log | grep "MBean\|State" /tmp/t1.log | awk -F'[,:]' '{ if ($4 != "") printf("%-20s\t\t\t\t%s\n", $6, $4=="HEALTH_OK"? "\033[32m: OK\033[0m" : "\033[31m"$4"\033[0m") }' | sort
}
weblogic_checks
echo ""
echo -e "${yellow}Concurrent Services on vlmgrcebsap01p.oci.mgrc.com:${c_clear}"
fndopp_check()
{
target_proc=`sqlplus -s apps/${apps_pass} <<EOF
   set feedback off pause off pagesize 0 verify off linesize 500 term off
   set pages 80
   set head off
   set line 120
   set echo off
   select TARGET_PROCESSES from fnd_concurrent_queues where CONCURRENT_QUEUE_ID= (select CONCURRENT_QUEUE_ID from FND_CONCURRENT_QUEUES where CONCURRENT_QUEUE_NAME='FNDCPOPP'); 
EOF
` 


	sqlplus -s apps/${apps_pass} <<EOF > /tmp/pid.data
	   set feedback off pause off pagesize 0 verify off linesize 500 term off
	   set pages 80
	   set head off
	   set line 120
	   set echo off
	   select OS_PROCESS_ID  from  fnd_concurrent_processes where process_status_code='A' and  CONCURRENT_QUEUE_ID=(select CONCURRENT_QUEUE_ID from  FND_CONCURRENT_QUEUES where  CONCURRENT_QUEUE_NAME='FNDCPOPP');
	   exit
EOF

sed -i  '/\S/!d' /tmp/pid.data

count=0
for i in `cat /tmp/pid.data`
do
ps -ef |grep  $i | grep -v grep > /dev/null
if [ $? -eq 0 ] ; then 
echo "Process is running." >> ${logfile}
count=$((${count}+1)) 
else 
echo "invalid process" >> ${logfile}
fi  
echo "Count is $count" >> ${logfile}
done	
echo "main count is : $count" >> ${logfile}

if [ ${target_proc} -eq ${count} ]; then 
	echo -e "Output Post processor\t\t\t\t${green}: OK${c_clear}"
else
    echo -e "Output Post processor\t\t\t\t${red}: FAILED${c_clear}"
fi 

target_status=`sqlplus -s apps/${apps_pass} <<EOF
   set feedback off pause off pagesize 0 verify off linesize 500 term off
   set pages 80
   set head off
   set line 120
   set echo off
   select  Component_status from  fnd_svc_components where COMPONENT_TYPE='WF_MAILER';
EOF
` 
if [ ${target_status} == "RUNNING" ]; then 
	echo -e "Workflow Mailer\t\t\t\t\t${green}: OK${c_clear}"
else
    echo -e "Workflow Mailer\t\t\t\t\t${red}: FAILED${c_clear}"
fi 

}
fndopp_check


icm_check()
{

sqlplus -s apps/${apps_pass} <<EOF > /tmp/pid.data
   set feedback off pause off pagesize 0 verify off linesize 500 term off
   set pages 80
   set head off
   set line 120
   set echo off
   select OS_PROCESS_ID  from  fnd_concurrent_processes where process_status_code='A' and  CONCURRENT_QUEUE_ID=(select CONCURRENT_QUEUE_ID from  FND_CONCURRENT_QUEUES where  CONCURRENT_QUEUE_NAME='FNDICM');
   exit
EOF
sed -i  '/\S/!d' /tmp/pid.data
ps -ef |grep  $i | grep -v grep > /dev/null
	if [ $? -eq 0 ] ; then 
		echo -e "Internal Concurrent Manager\t\t\t${green}: OK${c_clear}"
	else 
		echo -e "Internal Concurrent Manager\t\t\t${red}: FAILED${c_clear}"
	fi  
}
icm_check

login_page_url_check()
{
echo "$EBS_LOGIN_PAGE"
echo -e "${yellow}Application URLs:${c_clear}"
if wget -q --spider "${EBS_LOGIN_PAGE}" --no-check-certificate ; then
    echo -e "EBS Login url\t\t\t\t\t${green}: OK${c_clear}"
else
    echo -e "EBS Login url\t\t\t\t\t${red}: FAILED${c_clear}"
fi
}

markview_checks()
{
		> /tmp/markview.py
		echo ""
		echo -e "${yellow}Markview Weblogic Services:${c_clear}"
		echo "adminUsername = '${WEBLOGIC_PROD_MARKVIEW_USERNAME}'" > /tmp/markview.py
		echo "adminPassword = '${WEBLOGIC_PROD_MARKVIEW_PASSWORD}'" >> /tmp/markview.py
		echo "adminURL = '${WEBLOGIC_PROD_MARKVIEW_URL}'" >> /tmp/markview.py
		cat ${wlst_conn_additions_temp} >> /tmp/markview.py
		cd $FMW_HOME/user_projects/domains/EBS_domain*/bin/
		. ./setDomainEnv.sh
		java weblogic.WLST /tmp/markview.py > /tmp/markview.log
		grep -i ServerRuntime /tmp/markview.log | grep "MBean\|State" /tmp/markview.log| awk -F'[,:]' '{ if ($4 != "") printf("%-20s\t\t\t\t%s\n", $6, $4=="HEALTH_OK"? "\033[32m: OK\033[0m" : "\033[31m"$4"\033[0m") }' | sort
}
if [ ${MARKVIEW} == "YES" ]; then markview_checks; fi
echo ""

apex_checks()
{
		> /tmp/apex.py
		echo -e "${yellow}Apex Weblogic Services:${c_clear}"
		cp ${wlst_conn_additions_temp_apex} /tmp/get_wls_serverstate.py		
		sed -i "s/weblogic_admin_user/$WEBLOGIC_PROD_APEX_USERNAME/" /tmp/get_wls_serverstate.py	
		sed -i "s/weblogic_admin_pass/$WEBLOGIC_PROD_APEX_PASSWORD/" /tmp/get_wls_serverstate.py	
		sed -i "s|url|$WEBLOGIC_PROD_APEX_URL|" /tmp/get_wls_serverstate.py	
		cd $FMW_HOME/user_projects/domains/EBS_domain*/bin/
		. ./setDomainEnv.sh
		java weblogic.WLST /tmp/get_wls_serverstate.py	 | grep  -i Current > /tmp/apex.log
		content=$(cat /tmp/apex.log)
		servers=$(echo "$content" | sed -nE "s/Current state of '(.*)' : (RUNNING|FAILED)/\1:\2/p")

		# loop through the servers and print their status
		for server in $servers
		do
		    name=$(echo "$server" | cut -d ':' -f 1)
		    status=$(echo "$server" | cut -d ':' -f 2)
		    if [ "$status" == "RUNNING" ]; then
		        echo -e "$name\t\t\t\t\t${green}: OK${c_clear}"
		    else
		        echo -e "$name\t\t\t\t\t${red}: FAILED${c_clear}"
		    fi
		done

		
}
if [ ${APEX} == "YES" ]; then apex_checks; fi

login_page_url_check()
{
source "$auth_file"
echo ""
echo -e "${yellow}Application URL:${c_clear}"
URLS=$(grep "LOGIN_PAGE" "$auth_file" | sed "s/\(.*\)=\(.*\)/\1='\2'/")

while read -r line; do
    eval "$line"
    url=$(echo "$line" | cut -d= -f2 | sed "s/'//g")
    if wget -q --spider "$url" --no-check-certificate ; then
    echo -e "$(echo "$line" | sed "s/'//g") \t\t${green} : OK${c_clear}"
    else
    echo -e "$(echo "$line" | sed "s/'//g") \t\t${red}: FAILED${c_clear}"
    fi

done <<< "$URLS"
}

login_page_url_check

echo ""