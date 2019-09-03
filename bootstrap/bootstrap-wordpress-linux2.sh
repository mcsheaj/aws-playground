#!/bin/bash -xe

# Populate some variables from meta-data
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')

# Install jq
yum -y install jq

# Populate some variables from tags (need jq installed first)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r)

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
#userdel -f ec2-user

# Stop httpd and prevent it from starting on boot
systemctl disable httpd | true
systemctl start httpd | true

# Remove any existing versions of httpd and php
yum -y remove php* httpd* mod_ssl
rm -rf /etc/httpd/conf.d/ssl.conf
rm -rf /etc/pki/tls/private/localhost.key
rm -rf /etc/pki/tls/certs/localhost.crt

# Install 
amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2

# Install php-xml
yum install -y php-xml.*

# Generate self-signed certificate
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt

# Configure SSL with self-signed certificate (real cert is on the load balancer) and vhosts
yum install -y mod_ssl
wget --no-cache -O /etc/httpd/conf.d/ssl.conf https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/ssl-l2.conf

cd /tmp
rm -rf /var/www/bak
mkdir /var/www/bak

# Get intellipoint wordpress files from S3 and move to /var/www/html
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/intellipoint-hourly/intellipoint- --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/intellipointsolutions.com.tar.gz
tar -xzf intellipointsolutions.com.tar.gz
rm -rf intellipointsolutions.com.tar.gz
sed -i "s/define( *'DB_USER', '.*' *);/define( 'DB_USER', '${DB_USER}' );/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_PASSWORD', '.*' *);/define( 'DB_PASSWORD', '${DB_PASSWORD}' );/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_NAME', '.*' *);/define( 'DB_NAME', '${DB_DATABASE}' );/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_HOST', '.*' *);/define( 'DB_HOST', '${DB_SERVER}' );/" intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > intellipointsolutions.com/html/info.php
chown -R apache:apache intellipointsolutions.com
mv -f /var/www/intellipointsolutions.com /var/www/bak | true
mv -f intellipointsolutions.com /var/www
rm -rf intellipointsolutions.com

# Get joemcshea.intellipoint files from S3 and move to /var/www/joemcshea.intellipointsolutions.com
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/joemcshea-hourly/joemcshea- --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/joemcshea.intellipointsolutions.com.tar.gz
tar -xzf joemcshea.intellipointsolutions.com.tar.gz
rm -rf joemcshea.intellipointsolutions.com.tar.gz
DB_JOEMCSHEA=$(echo ${DB_DATABASE} | sed 's/intellipoint_/joemcshea_/')
sed -i "s/define( *'DB_USER', '.*' *);/define( 'DB_USER', '${DB_USER}' );/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_PASSWORD', '.*' *);/define( 'DB_PASSWORD', '${DB_PASSWORD}' );/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_NAME', '.*' *);/define( 'DB_NAME', '${DB_JOEMCSHEA}' );/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_HOST', '.*' *);/define( 'DB_HOST', '${DB_SERVER}' );/" joemcshea.intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > joemcshea.intellipointsolutions.com/html/info.php
chown -R apache:apache joemcshea.intellipointsolutions.com
mv -f /var/www/joemcshea.intellipointsolutions.com /var/www/bak | true
mv -f joemcshea.intellipointsolutions.com /var/www
rm -rf joemcshea.intellipointsolutions.com

# Get speasyforms.intellipoint files from S3 and move to /var/www/speasyforms.intellipointsolutions.com
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/speasyforms-hourly/speasyforms- --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/speasyforms.intellipointsolutions.com.tar.gz
tar -xzf speasyforms.intellipointsolutions.com.tar.gz
rm -rf speasyforms.intellipointsolutions.com.tar.gz
DB_SPEASYFORMS=$(echo ${DB_DATABASE} | sed 's/intellipoint_/speasyforms_/')
sed -i "s/define( *'DB_USER', '.*' *);/define( 'DB_USER', '${DB_USER}' );/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_PASSWORD', '.*' *);/define( 'DB_PASSWORD', '${DB_PASSWORD}' );/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_NAME', '.*' *);/define( 'DB_NAME', '${DB_SPEASYFORMS}' );/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( *'DB_HOST', '.*' *);/define( 'DB_HOST', '${DB_SERVER}' );/" speasyforms.intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > speasyforms.intellipointsolutions.com/html/info.php
chown -R apache:apache speasyforms.intellipointsolutions.com
mv -f /var/www/speasyforms.intellipointsolutions.com /var/www/bak | true
mv -f speasyforms.intellipointsolutions.com /var/www
rm -rf speasyforms.intellipointsolutions.com

# Setup the backup script
wget --no-cache -O /etc/cron.d/aws-wordpress-backup.cron https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/aws-wordpress-backup.cron
chmod 600 /etc/cron.d/aws-wordpress-backup.cron
wget --no-cache -O /sbin/aws-wordpress-backup.sh https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/aws-wordpress-backup.sh
chmod 700 /sbin/aws-wordpress-backup.sh 
systemctl restart crond

# Start the httpd service and configure it to start on boot
sudo systemctl enable httpd
sudo systemctl start httpd

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

# 
mkdir -p /root/.aws
chmod 700 /root/.aws

cat << EOF > /root/.aws/bootstrap.properties
ADMIN_GROUP=$ADMIN_GROUP
MOTD_BANNER=$MOTD_BANNER
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_DATABASE=$DB_DATABASE
DB_SERVER=$DB_SERVER
AWS_BUCKET=$AWS_BUCKET
EOF
chmod 600 /root/.aws/bootstrap.properties

