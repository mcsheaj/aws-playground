#!/bin/bash -xe

# Install jq
yum -y install jq

cd /tmp

# Populate some variables from meta-data
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
ADMIN_GROUP=$1
MOTD_BANNER=$2

# Populate some variables from tags (need jq installed first)
NAME=`aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r`
STACK_NAME=`aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r`

# Update the instance name to include the stack name
if [[ $NAME != *-$STACK_NAME ]]
then
    NEW_NAME="$NAME-$STACK_NAME"
    aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Name,Value=$NEW_NAME --region $REGION
else
    NEW_NAME=$NAME
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

# Run system updates
yum -y update

# Update the motd banner
if ! [ -z "$MOTD_BANNER" ]
then
    wget --no-cache -O /etc/update-motd.d/30-banner $MOTD_BANNER
    update-motd --force
    update-motd --disable
else 
    echo "No MOTD_BANNER specified, skipping motd configuration"
fi
