#!/bin/bash -xe

cd /tmp

# Install jq
yum -y install jq

# Populate some variables from meta-data and tags
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=${INSTANCE_ID}" | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=${INSTANCE_ID}" | jq .Tags[0].Value -r)

# Update the motd banner
if ! [ -z "${MOTD_BANNER}" ]
then
    wget --no-cache -O /etc/update-motd.d/30-banner ${MOTD_BANNER}
    update-motd --force
    update-motd --disable
else 
    echo "No MOTD_BANNER specified, skipping motd configuration"
fi

# Create user accounts for administrators
if ! [ -z "${ADMIN_GROUP}" ]
then
    yum -y install git
    wget --no-cache https://raw.githubusercontent.com/mcsheaj/aws-ec2-ssh/master/install.sh
    chmod 755 install.sh
    ./install.sh -i ${ADMIN_GROUP} -s ${ADMIN_GROUP}
else 
    echo "No ADMIN_GROUP specified, skipping aws-ect-ssh configuration"
fi

# Update the instance name to include the stack name
if [[ ${NAME} != *-${STACK_NAME} ]]
then
    NEW_NAME="${NAME}-${STACK_NAME}"
    aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Name,Value=$NEW_NAME --region $REGION
else
    NEW_NAME=${NAME}
fi

# Move sshd to port 2222
#sed -i "s/#Port 22/Port 2222/" /etc/ssh/sshd_config
#systemctl restart sshd

# Install the RedHat epel yum repo
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

# Install iptables-service and fail2ban from the epel repo
yum -y install iptables-service 
#fail2ban

# Enable iptables to start on boot, and start it now
systemctl enable iptables
systemctl start iptables

# Configure iptables:
# 1. accept anything on the loopback adapter
# 2. accept incoming packets that belong to a connection that has already been established (using the state module)
# 3. accept tcp on port 2222 (where we're running sshd)
# 4. drop anything else
# and persist the config
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -A INPUT -j DROP
iptables-save > /etc/sysconfig/iptables

# Enable fail2ban to start on boot, and start it now
#systemctl enable fail2ban
#systemctl start fail2ban

# Configure fail2ban
# 1. lower maxretry to 3
# 2. enable the sshd-iptables jail
# and restart fail2ban
#cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
#sed -i "s/maxretry = 5/maxretry = 3/" /etc/fail2ban/jail.local
#sed -i "s/^\[sshd\]/[sshd]\nenabled=true/" /etc/fail2ban/jail.local
#sed -i "s/port *= *ssh/port    = 2222/" /etc/fail2ban/jail.local
#systemctl restart fail2ban

# Run system updates
yum -y update

# Delete the ec2-user and its home directory
userdel ec2-user || true
rm -rf /home/ec2-user || true

# Call cfn-init, which reads the launch configration metadata and uses it to
# configure and runs cfn-hup as a service, so we can get a script run on updates to the metadata
/opt/aws/bin/cfn-init -v --stack ${STACK_NAME} --resource LaunchConfig --configsets cfn_install --region ${REGION}

# Send a signal indicating we're done
/opt/aws/bin/cfn-signal -e $? --stack ${STACK_NAME} --resource BastionScalingGroup --region ${REGION} || true
