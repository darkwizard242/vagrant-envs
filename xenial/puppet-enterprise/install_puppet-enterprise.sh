#!/bin/bash -e

# Update repository cache and upgrade packages on XENIAL.
apt-get update
apt-get upgrade -y

## Installing packages required.
dependencies="wget tar"

for dependency in $dependencies;
do
  if dpkg -s "$dependency" &> /dev/null;
    then
      echo -e "\n$dependency is already available and installed within the system."
    else
      echo -e "About to install:\t$dependency."
      DEBIAN_FRONTEND=non-interactive apt-get install "$dependency" -y
  fi
done


## Download, install and configure PUPPET ENTERPRISE
alt1=$(hostname)
alt2=$(hostname -f)
distro="ubuntu"
version="2019.1.0"
osarch="amd64"
release="16.04"
extract_path="/opt"
binary="puppet-enterprise"

# Creating folder to untar PUPPET ENTERPRISE into.
if [ -e ${extract_path}/${binary}-${version} ]
then
  echo -e "\nDirectory:\t${extract_path}/${binary}-${version}\texists. About to remove it.\n"
  rm -rf ${extract_path}/${binary}-${version}
  echo -e "\nRecreating:\t${extract_path}/${binary}-${version}"
  mkdir -pv ${extract_path}/${binary}-${version}
else
  echo -e "\nDirectory:\t${extract_path}/${binary}-${version}\tdoesn't exist. Creating:\t${extract_path}/${binary}-${version}\t\n"
  mkdir -pv ${extract_path}/${binary}-${version}
fi

# Download and extract PUPPET ENTPERISE
echo -e "\nDownloading:\t${binary}-${version}!\n"
wget "https://pm.puppetlabs.com/cgi-bin/download.cgi?dist=${distro}&rel=${release}&arch=${osarch}&ver=${version}" -O /tmp/${binary}-${version}.tar.gz
echo -e "\nExtracting: /tmp/${binary}-${version}.tar.gz \t to:\t ${extract_path}/${binary}-${version}"
tar -xzf /tmp/${binary}-${version}.tar.gz -C ${extract_path}/${binary}-${version} --strip-components=1
echo -e "\nRemoving:\t/tmp/${binary}.tar.gz" && rm -rfv /tmp/${binary}-${version}.tar.gz

# Create custom config file to use for installation.
cat > /tmp/pe.conf <<EOF
{
  "console_admin_password": "password",
  "puppet_enterprise::puppet_master_host": "%{::trusted.certname}",
  "puppet_enterprise::profile::master::java_args": {
    "Xms": "512m",
    "Xmx": "1024m"
  },
  "pe_install::puppet_master_dnsaltnames": [
    "${alt1}",
    "${alt2}",
    "puppet"
  ]
}
EOF

# Execute PUPPET ENTERPRISE installer using the config file
${extract_path}/${binary}-${version}/puppet-enterprise-installer -c /tmp/pe.conf

# Remove custom config file
rm -v /tmp/pe.conf

# Remove the extracted directory.
echo -e "\nREMOVING THE PATH IN WHICH PUPPET ENTERPRISE WAS EXTRACTED!\n" && rm -rf ${extract_path}/${binary}-${version}

# Enable autosign and set permissions
echo "*" > /etc/puppetlabs/puppet/autosign.conf && chown pe-puppet:pe-puppet /etc/puppetlabs/puppet/autosign.conf

# Run puppet agent twice based on successful execution of first to make sure changes are there.
puppet agent -t && puppet agent -t

# Another run of puppet agent
puppet agent -t || true

# Check for puppet infrastructure status
echo -e "\nChecking and printing the status of Puppet Enterprise Infrastructure Services.\n"
/opt/puppetlabs/bin/puppet-infrastructure status
