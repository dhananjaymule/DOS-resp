	#!/bin/bash
	#set log level
	set -xe
	#if website is under maintainance then do not run the script
	curl https://www.abuseipdb.com/  > /tmp/abused-ip-list

#	grep "Down for maintenance" /tmp/abused-ip-list
	if grep -e "Down for maintenance" /tmp/abused-ip-list
	#if [ $? -eq 0 ]
	   then
		 exit 0

	 else

	#primary files creations
	touch /tmp/primary_acl 
	touch /tmp/final_database
	Entry_no=1
	#######################################################################################################################3

	# check from old database if the abused lavel is reduced of not
	while read line
	do 
	  ABUSED_IP="$(echo $line | awk '{print $1}')"
	  Abused_level="$(echo $line | awk '{print $2}')"
	  
	  ABUSED_LEVEL="$(curl https://www.abuseipdb.com/check/$i |grep 'Confidence' |grep -Eo '([0-9][0-9]|100)'\% | cut -d '%' -f 1)"



	  if [ $ABUSED_LEVEL > $Abused_level ]
	   then
		echo '$ABUSED_IP  $ABUSED_LEVEL' >> /tmp/final_database
	  fi
	done < /tmp/final_database

	#check top abused IP's on internet

	curl https://www.abuseipdb.com/  > /tmp/abused-ip-list

	grep -E -o "([0-9]{1,3}[\.]){3}[0-9]"  /tmp/abused-ip-list > /tmp/abused-ip-list.txt

	for i in $(cat /tmp/abused-ip-list.txt)
	 do 
	  ABUSED_LEVEL="$(curl https://www.abuseipdb.com/check/$i |grep 'Confidence' |grep -Eo '([0-9][0-9]|100)'\% | cut -d '%' -f 1)"

	  echo -e '$i $ABUSED_LEVEL \n' 1>> /tmp/primary_acl # primary database is generated
	  
	  if [ $ABUSED_LEVEL > 65 ]
	  then 
		 echo "$i $ABUSED_LEVEL" >> /tmp/final_database
	  fi
	 done

	cat /tmp/final_database | sort -u -k1,1 |sort -k 2 -n >/tmp/final_database_sorted

	################################################################################################
	#list availabe route tables
	aws ec2 describe-route-tables | grep 'RouteTableId' | cut -d '"' -f 4 | uniq > /tmp/route_table_list
	#check how many route-tables have entry for '0.0.0.0/0'
	for i in $(cat /tmp/route_table_list)
	 do
	  aws ec2 describe-route-tables --route-table-ids $i | grep "0.0.0.0"
	  if [ $? == 0 ]
	   then 
		 echo $i >> /tmp/routes_to_be_addressed
	  fi
	 done

	# list the subnets to be addressed
	for i in $(cat /tmp/routes_to_be_addressed)
	 do
	  aws ec2 describe-route-tables --route-table-ids $i |  grep  SubnetId | cut -d '"' -f 4 | uniq > /tmp/subnets_to_be_blocked
	 done
	##############################################################################################

	aws ec2 describe-network-acls | grep NetworkAclId | cut -d '"' -f 4 | uniq > /tmp/list_of_nacl

	for i  in $(cat /tmp/list_of_nacl)
	 do
		for j in $(cat /tmp/subnets_to_be_blocked)
		do
		 aws ec2 describe-network-acls --network-acl-ids $i  | grep $j
	#    grep $i /tmp/subnets_to_be_blocked
		 if [ $? -eq 0 ]
		  then
		  echo $i >>/tmp/nacls_to_be_updated_final_db
		 fi
		done
	 done

	#update the NACL entries to deny the traffic from abused IP's

	while read line
	do
	  while read line1
	  do
		ABUSED_IP="$(echo $line1 | awk '{print $1}')"
		aws ec2 create-network-acl-entry --network-acl-id $line --ingress --rule-number $Entry_no --protocol -1  --cidr-block $ABUSED_IP/32 --rule-action deny 
		((Entry_no=Entry_no+1))
		if [ $Entry_no -ge 125 ];
		 then
			exit 0
		fi
	  done < /tmp/final_database_sorted

	done < /tmp/nacls_to_be_updated_final_db

	fi
