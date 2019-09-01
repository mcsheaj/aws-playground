#!/bin/bash -xe

# Install jq
yum -y install jq

cd /tmp

# Populate some variables from meta-data
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

# Populate some variables from tags (need jq installed first)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)

# Create user accounts for administrators
if ! [ -z "$ADMIN_GROUP" ]
then
    yum -y install git
    wget --no-cache https://raw.githubusercontent.com/mcsheaj/aws-ec2-ssh/master/install.sh
    chmod 755 install.sh
    ./install.sh -i $ADMIN_GROUP -s $ADMIN_GROUP
else 
    echo "No ADMIN_GROUP specified, skipping aws-ect-ssh configuration"
fi

# Update the motd banner
if ! [ -z "$MOTD_BANNER" ]
then
    wget --no-cache -O /etc/update-motd.d/30-banner $MOTD_BANNER
    update-motd --force
    update-motd --disable
else 
    echo "No MOTD_BANNER specified, skipping motd configuration"
fi

# Remove the ec2-user
userdel -f ec2-user

# Turn on IPV4 forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

VPC_CIDR=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/$/vpc-ipv4-cidr-block)

# Enable nat in iptables for our VPC CIDDR
iptables -t nat -A POSTROUTING -o eth0 -s ${VPC_CIDR} -j MASQUERADE

# Download the script to update the default routes on the private networks and run it
wget --no-cache https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/aws-auto-healing-nat.sh
mv aws-auto-healing-nat.sh /sbin
chmod 700 /sbin/aws-auto-healing-nat.sh
/sbin/aws-auto-healing-nat.sh

# Re-enable nat and reset the private route tables on boot
echo "iptables -t nat -A POSTROUTING -o eth0 -s ${VPC_CIDR} -j MASQUERADE" >> /etc/rc.d/rc.local
echo "/sbin/aws-auto-healing-nat.sh" >> /etc/rc.d/rc.local
chmod 700 /etc/rc.d/rc.local

# Update the instance name to include the stack name
if [[ $NAME != *-$STACK_NAME ]]
then
    NEW_NAME="$NAME-$STACK_NAME"
    aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Name,Value=$NEW_NAME --region $REGION
else
    NEW_NAME=$NAME
fi

# Run system updates
yum -y update