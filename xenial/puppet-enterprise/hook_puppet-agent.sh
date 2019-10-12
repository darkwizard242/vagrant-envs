#!/bin/bash -e

# Function to ping provided IP and confirm if local system can reach to it.
check_ip_reachable () {
  if ping -c 4 ${pe_ip} &> /dev/null;
  then
    echo -e "\nPuppet Enterprise Server is reachable via IP address:\t${pe_ip}\n"
  else
    echo -e "\nPuppet Enterprise Server is not reachable via IP address:\t${pe_ip}\n"
  fi
}

# Function to add entry into /etc/hosts
edit_host () {
  echo -e "\n${pe_ip} ${pe_fqdn} ${pe_shn}" >> /etc/hosts
}

# Function to puppetize
puppetize () {
  curl -k https://${pe_fqdn}:8140/packages/current/install.bash | sudo bash
  puppet agent -t
}

echo
read -p "Enter the IP of Puppet Enterprise Server: " pe_ip
read -p "Enter FQDN of Puppet Enterprise Server: " pe_fqdn
read -p "Enter Short hostname of Puppet Enterprise Server: " pe_shn
check_ip_reachable
edit_host
puppetize

