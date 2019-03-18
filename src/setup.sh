#!/bin/bash
#
# Prepare a cluster of Pis
#
# License: GPLv3
# License URI: http://www.gnu.org/licenses/gpl.txt
#
# Copyright 2019 AbdAllah Aly Saad (github.com/aaly)
#

temp_update_password="temp_password" 
setup_user=("root" "pi" "root" "pi" "root")
setup_password=("1234" "raspberry" "bananapi" "bananapi" "${temp_update_password}")

cluster_user="cluster"
cluster_password="clusterPassword"

pkgs="fabric"

echo_ok()
{
    echo -e "\033[32m[OK]\033[0m $@"
}

echo_err()
{
    echo -e "\033[31m[ERROR]\033[0m $@" 1>&2
}

echo_war()
{
    echo -e "\033[33m[WARNING]\033[0m $@"
}

echo_info()
{
    echo -e "\033[34m[INFO]\033[0m $@"
}

nodes=[] #list of the nodes , predefined manually or by discoverNodes()
getNodes()
{
    #sudo nmap  --open -p 22  -sA 192.168.0.1/24  | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
    sudo arp -a | grep "\? *" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
}

getNodeIP()
{
    sudo nmap  --open -p 22  -sV 192.168.0.1/24
}

discoverNodes()
{
    nodes=$(getNodes)
    for node in $nodes
	do
        echo_info "Discovered ${node}"
    done
}

#nodes="192.168.0.105" #list of the nodes , predefined manually or by discoverNodes()


if [ "${1}" == "monitor" ]
then
        for node in $nodes
        do
            echo "status of $node"
		    ssh root@$node armbian
        done
elif [ "${1}" == "blink" ]
then
		discoverNodes

        while true
        do
            for node in $nodes
            do
                echo_war "turning off of $node"
                sshpass -p $cluster_password ssh  -t  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $cluster_user@$node "sudo bash -c ' echo 0 > /sys/class/leds/orangepi\:red\:status/brightness'" &
                sshpass -p $cluster_password ssh  -t  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $cluster_user@$node "sudo bash -c 'echo 0 > /sys/class/leds/red_led/brightness'"
                #sleep 1s
            done

            for node in $nodes
            do
                #echo "status of $node"
                echo_info "turning on of $node"
                sshpass -p $cluster_password ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $cluster_user@$node "sudo bash -c 'echo 1 > /sys/class/leds/orangepi\:red\:status/brightness'" &
                sshpass -p $cluster_password ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $cluster_user@$node "sudo bash -c  'echo 1 > /sys/class/leds/red_led/brightness'"
                #sleep 1s
            done
        done

elif [ "${1}" == "shutdown" ]
then
		discoverNodes

		for node in $nodes
		do
			sshpass -p $cluster_password ssh  -t  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $cluster_user@$node "sudo /sbin/shutdown"
		done
		
elif [ "${1}" == "remote-prepare" ]
then
		discoverNodes

		if [[ ${#setup_user[@]} != ${#setup_password[@]} ]]
		then
			echo_err "list size of users and password do not match"
			return
		fi
		
        for node in $nodes
        do
            echo_info "Preparing [$node]"
           
            tmp_user=""
            tmp_pass=""
            usersListSize=${#setup_user[@]}
             
            for (( i=0; i<$usersListSize; i++ ))
            do
				sshpass -p "${setup_password[$i]}" ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  "${setup_user[$i]}"@$node "ls" &> /dev/null
				result=$?
				#echo_err "result : $result"
				if [[ $result == 0 || $result == 1 ]]
				then
					tmp_user="${setup_user[$i]}"
					tmp_pass="${setup_password[$i]}"
					echo_ok "using user [${tmp_user}/${tmp_pass}] for ${node}"
					break
				fi
            done
            
            if [[ "${tmp_user}" == "" ]]
            then
				echo_err "could not find a login for $node"
				continue
            fi
            
            
            sshpass -p "${tmp_pass}" ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  "${tmp_user}"@$node "true"
            
            result=$?
            echo_err "result : $result"
            if [[ $result == 1 ]]
            then
				echo_war "updating expired password"
				./sshpch.exp "${tmp_pass}" "${temp_update_password}" "${tmp_user}"@$node
				tmp_pass="${temp_update_password}"
            fi
            
            homePath=""
            if [[ "${tmp_user}" == "root" ]]
            then
				homePath="/${tmp_user}"
			else
				homePath="/home/${tmp_user}"
			fi
            sshpass -p "${tmp_pass}" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  "$0" "${tmp_user}"@$node:"${homePath}"
            sshpass -p "${tmp_pass}" ssh  -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  "${tmp_user}"@$node "/usr/bin/sudo /bin/bash ${homePath}/$0 prepare"
        
			done
elif [ "${1}" == "prepare" ]
then
	apt update
	apt install -y ${pkgs}
	/usr/sbin/useradd ${cluster_user}
	sudo mkdir /home/${cluster_user}
	chown -hR ${cluster_user} /home/${cluster_user}
	echo "${cluster_user}:${cluster_password}"|chpasswd
	#echo "${cluster_user} ALL=(ALL) ALL" >> /etc/sudoers
	echo "${cluster_user}  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers	
	
fi
