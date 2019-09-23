#!/bin/bash -xe

cd /tmp

# Install jq
yum -y install jq

# Populate some variables from meta-data and tags
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)
MAC_ADDRESS=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/)
VPC_CIDR=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/vpc-ipv4-cidr-block)

# Update the motd banner
if ! [ -z "$MOTD_BANNER" ]
then
    wget --no-cache -O /etc/update-motd.d/30-banner $MOTD_BANNER
    update-motd --force
    update-motd --disable
else 
    echo "No MOTD_BANNER specified, skipping motd configuration"
fi

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

# Disable source/destination IP check so forwarding will work
aws ec2 modify-instance-attribute --instance-id ${INSTANCE_ID} --source-dest-check "{\"Value\": false}" --region ${REGION}

# Turn on IPV4 forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# Enable nat in iptables for our VPC CIDDR
iptables -t nat -A POSTROUTING -o eth0 -s ${VPC_CIDR} -j MASQUERADE

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

# Delete the ec2-user and its home directory
userdel ec2-user || true
rm -rf /home/ec2-user || true

# Call cfn-init, which reads the launch configration metadata and uses it to
# configure and runs cfn-hup as a service, so we can get a script run on updates to the metadata
/opt/aws/bin/cfn-init -v --stack ${STACK_NAME} --resource LaunchConfig --configsets cfn_install --region ${REGION}

# Send a signal indicating we're done
/opt/aws/bin/cfn-signal -e $? --stack ${STACK_NAME} --resource NatScalingGroup --region ${REGION} || true
