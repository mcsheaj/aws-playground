#!/bin/bash -xe

# Populate some variables from meta-data
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')

# Populate some variables from tags (need jq installed first)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" | jq .Tags[0].Value -r)

# Run system updates
yum -y update

# Install jq
yum -y install jq

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

# Get intellipoint wordpress files from S3 and move to /var/www/html
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/intellipoint-hourly/intellipoint-hourly --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/intellipointsolutions.com.tar.gz
tar -xzf intellipointsolutions.com.tar.gz
sed -i "s/define( 'DB_USER', '.*' );/define('DB_USER, '$DB_USER');/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_PASSWORD', '.*' );/define('DB_PASSWORD, '$DB_PASSWORD');/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_NAME', '.*' );/define('DB_NAME, '$DB_DATABASE');/" intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_HOST', '.*' );/define('DB_HOST, 'DB_SERVER');/" intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > intellipointsolutions.com/html/info.php
chown -R apache:apache intellipointsolutions.com
mv -n intellipointsolutions.com /var/www

# Get joemcshea.intellipoint files from S3 and move to /var/www/joemcshea.intellipointsolutions.com
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/joemcshea-hourly/joemcshea-hourly --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/intellipointsolutions.com.tar.gz
tar -xzf joemcshea.intellipointsolutions.com.tar.gz
sed -i "s/define( 'DB_USER', '.*' );/define('DB_USER, '$DB_USER');/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_PASSWORD', '.*' );/define('DB_PASSWORD, '$DB_PASSWORD');/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_NAME', '.*' );/define('DB_NAME, '$DB_DATABASE');/" joemcshea.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_HOST', '.*' );/define('DB_HOST, 'DB_SERVER');/" joemcshea.intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > joemcshea.intellipointsolutions.com/html/info.php
chown -R apache:apache joemcshea.intellipointsolutions.com
mv -n joemcshea.intellipointsolutions.com /var/www

# Get speasyforms.intellipoint files from S3 and move to /var/www/speasyforms.intellipointsolutions.com
BACKUP=$(aws s3api list-objects --bucket ${AWS_BUCKET} --prefix backup/speasyforms-hourly/speasyforms-hourly --query "Contents[?contains(Key, '.tar.gz')] | reverse(sort_by(@, &LastModified)) | [0]" | jq .Key -r)
aws s3 cp s3://${AWS_BUCKET}/${BACKUP} /tmp/intellipointsolutions.com.tar.gz
tar -xzf speasyforms.intellipointsolutions.com.tar.gz
sed -i "s/define( 'DB_USER', '.*' );/define('DB_USER, '$DB_USER');/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_PASSWORD', '.*' );/define('DB_PASSWORD, '$DB_PASSWORD');/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_NAME', '.*' );/define('DB_NAME, '$DB_DATABASE');/" speasyforms.intellipointsolutions.com/html/wp-config.php
sed -i "s/define( 'DB_HOST', '.*' );/define('DB_HOST, 'DB_SERVER');/" speasyforms.intellipointsolutions.com/html/wp-config.php
echo "<?php phpinfo() ?>" > speasyforms.intellipointsolutions.com/html/info.php
chown -R apache:apache speasyforms.intellipointsolutions.com
mv -n speasyforms.intellipointsolutions.com /var/www

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

# Setup the backup script
wget --no-cache -O /etc/cron.d/wordpress_backup https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/wordpress_backup
chmod 600 /etc/cron.d/wordpress_backup
wget --no-cache -O /sbin/wpbackup.sh https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/wpbackup.sh
chmod 700 /sbin/wpbackup.sh 
systemctl restart crond

# Update aws-cfn-bootstrap and call cfn-signal
#yum update -y aws-cfn-bootstrap* | true
#/opt/aws/bin/cfn-signal -e $? --stack $STACK_NAME --resource NatScalingGroup --region $REGION

cat << EOF > /root/.aws/config
[default]
output = $AWS_DEFAULT_OUTPUT
region = $AWS_DEFAULT_REGION
EOF
chmod 600 /root/.aws/config

cat << EOF > /root/.aws/credentials
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
chmod 600 /root/.aws/credentials

cat << EOF > /root/.aws/bootstrap.properties
ADMIN_GROUP=$ADMIN_GROUP
MOTD_BANNER=$MOTD_BANNER
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_DATABASE=$DB_DATABASE
DB_SERVER=$DB_SERVER
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
AWS_DEFAULT_OUTPUT=$AWS_DEFAULT_OUTPUT
AWS_BUCKET=$AWS_BUCKET
EOF
chmod 600 /root/.aws/bootstrap.properties

mkdir -p /root/.aws
chmod 700 /root/.aws

