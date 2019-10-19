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

# Function to set Ubuntu's RELEASE VERSION only if bionic (18.04) or xenial (16.04)
rel_ver () {
  if [[ $(lsb_release -cs) == "bionic" ]];
  then
    codename="18.04"
  elif [[ $(lsb_release -cs) == "xenial" ]];
  then
    codename="16.04"
  else
    exit 1
  fi
}


# Function to install Puppet Development Kit based on Ubuntu only if bionic (18.04) or xenial (16.04).
install_pdk () {
  if [[ $(lsb_release -cs) == "bionic" ]];
  then
    echo -e "\nInstalling pdk (Puppet Development Kit)\n"
    wget https://apt.puppet.com/puppet-tools-release-bionic.deb
    dpkg -i puppet-tools-release-bionic.deb
    apt-get update
    apt-get install pdk -y
    apt-get install -f
  elif [[ $(lsb_release -cs) == "xenial" ]];
  then
    echo -e "\nInstalling pdk (Puppet Development Kit)\n"
    wget https://apt.puppet.com/puppet-tools-release-xenial.deb
    dpkg -i puppet-tools-release-xenial.deb
    apt-get update
    apt-get install pdk -y
    apt-get install -f
  else
    exit 1
  fi
}

# Call function rel_var to set the VERSION of Ubuntu in Puppet Enterprise download URL.
# Applies only if system is Ubuntu with VERSIONs bionic (18.04) or xenial (16.04).
rel_ver

# Call function to install Puppet Development Kit based on the codename.
# Applies only if system is Ubuntu with VERSIONs bionic (18.04) or xenial (16.04).
install_pdk

## Download, install and configure PUPPET ENTERPRISE
ALT1=$(hostname)
ALT2=$(hostname -f)
PASS="password"
R10K_REMOTE_REPO="git@github.com:darkwizard242/puppet-control-repo.git"
DISTRO="ubuntu"
VERSION="latest"
OSARCH="amd64"
RELEASE="${codename}"
EXTRACT_PATH="/opt"
BINARY="puppet-enterprise"
DEPLOY_PRIV_KEY_FILE_ORIG="/tmp/id-control_repo.rsa"
DEPLOY_PRIV_KEY_FILE_DEST="/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa"

# Creating folder to untar PUPPET ENTERPRISE into.
if [ -e ${EXTRACT_PATH}/${BINARY}-${VERSION} ]
then
  echo -e "\nDirectory:\t${EXTRACT_PATH}/${BINARY}-${VERSION}\texists. About to remove it.\n"
  rm -rf ${EXTRACT_PATH}/${BINARY}-${VERSION}
  echo -e "\nRecreating:\t${EXTRACT_PATH}/${BINARY}-${VERSION}"
  mkdir -pv ${EXTRACT_PATH}/${BINARY}-${VERSION}
else
  echo -e "\nDirectory:\t${EXTRACT_PATH}/${BINARY}-${VERSION}\tdoesn't exist. Creating:\t${EXTRACT_PATH}/${BINARY}-${VERSION}\t\n"
  mkdir -pv ${EXTRACT_PATH}/${BINARY}-${VERSION}
fi

# Download and extract PUPPET ENTPERISE
echo -e "\nDownloading:\t${BINARY}-${VERSION}!\n"
wget "https://pm.puppetlabs.com/cgi-bin/download.cgi?dist=${DISTRO}&rel=${RELEASE}&arch=${OSARCH}&ver=${VERSION}" -O /tmp/${BINARY}-${VERSION}.tar.gz  &> /dev/null
echo -e "\nExtracting: /tmp/${BINARY}-${VERSION}.tar.gz \t to:\t ${EXTRACT_PATH}/${BINARY}-${VERSION}"
tar -xzf /tmp/${BINARY}-${VERSION}.tar.gz -C ${EXTRACT_PATH}/${BINARY}-${VERSION} --strip-components=1
echo -e "\nRemoving:\t/tmp/${BINARY}.tar.gz" && rm -rfv /tmp/${BINARY}-${VERSION}.tar.gz

# Create custom config file to use for installation.
cat > /tmp/pe.conf <<EOF
{
	"console_admin_password": "${PASS}",
	"puppet_enterprise::puppet_master_host": "%{::trusted.certname}",
	"puppet_enterprise::profile::console::rbac_token_auth_lifetime": "1y",
	"puppet_enterprise::profile::master::java_args": {
		"Xms": "2048m",
		"Xmx": "2048m"
	},
	"pe_install::puppet_master_dnsaltnames": [
		"${ALT1}",
		"${ALT2}",
		"puppet"
	],
	"puppet_enterprise::profile::master::r10k_remote": "${R10K_REMOTE_REPO}",
	"puppet_enterprise::profile::master::r10k_private_key": "${DEPLOY_PRIV_KEY_FILE_DEST}",
	"puppet_enterprise::profile::master::code_manager_auto_configure": true
}
EOF

# Execute PUPPET ENTERPRISE installer using the config file
${EXTRACT_PATH}/${BINARY}-${VERSION}/puppet-enterprise-installer -c /tmp/pe.conf

# Remove custom config file
rm -v /tmp/pe.conf

# Remove the extracted directory.
echo -e "\nREMOVING THE PATH IN WHICH PUPPET ENTERPRISE WAS EXTRACTED!\n" && rm -rf ${EXTRACT_PATH}/${BINARY}-${VERSION}

# Add private key for the deploy public key set up for Puppet Control Repo in GitHub.
cp -v ${DEPLOY_PRIV_KEY_FILE_ORIG} ${DEPLOY_PRIV_KEY_FILE_DEST}
chown -Rv pe-puppet:pe-puppet ${DEPLOY_PRIV_KEY_FILE_DEST}
chmod 0400 ${DEPLOY_PRIV_KEY_FILE_DEST}

# Set up puppet access for generating and using token.
echo ${PASS} | puppet access login --username admin

# Enable autosign and set permissions
echo "*" > /etc/puppetlabs/puppet/autosign.conf && chown pe-puppet:pe-puppet /etc/puppetlabs/puppet/autosign.conf

/opt/puppetlabs/bin/puppet-code deploy production --wait

# Run puppet agent twice based on successful execution of first to make sure changes are there.
puppet agent -t && puppet agent -t

# Another run of puppet agent
puppet agent -t || true

# Installing desired gems using gem provided by puppet.
/opt/puppetlabs/puppet/bin/gem install puppet-lint

# Check for puppet infrastructure status
echo -e "\nChecking and printing the status of Puppet Enterprise Infrastructure Services.\n"
/opt/puppetlabs/bin/puppet-infrastructure status
