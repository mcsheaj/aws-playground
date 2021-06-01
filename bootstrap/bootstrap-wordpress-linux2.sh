#!/bin/bash -xe

cd /tmp

# Install jq
yum -y install jq

# Populate some variables from meta-data and tags
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)
STACK_NAME=$(aws ec2 describe-tags --region us-east-1 --filters "Name=key,Values=StackName" "Name=resource-id,Values=$INSTANCE_ID" --output json | jq .Tags[0].Value -r)

# Read some variables from bootstrap.properties
MOTD_BANNER=$(awk -F "=" '/MOTD_BANNER/ {print $2}' /root/.aws/bootstrap.properties)
ADMIN_GROUP=$(awk -F "=" '/ADMIN_GROUP/ {print $2}' /root/.aws/bootstrap.properties)
AWS_BUCKET=$(awk -F "=" '/AWS_BUCKET/ {print $2}' /root/.aws/bootstrap.properties)

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

################################################################################
# BEGIN WordPress Setup
################################################################################

DB_USER=$(awk -F "=" '/DB_USER/ {print $2}' /root/.aws/bootstrap.properties)
DB_PASSWORD=$(awk -F "=" '/DB_PASSWORD/ {print $2}' /root/.aws/bootstrap.properties)
DB_DATABASE=$(awk -F "=" '/DB_DATABASE/ {print $2}' /root/.aws/bootstrap.properties)
DB_SERVER=$(awk -F "=" '/DB_SERVER/ {print $2}' /root/.aws/bootstrap.properties)

# Install amazon linux extras lamp
amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2

# Install php-xml
yum install -y php-xml.* php-mbstring.*

# Generate self-signed certificate
cd /etc/pki/tls/certs
./make-dummy-cert localhost.crt
cd /tmp

# Configure SSL with self-signed certificate (real cert is on the load balancer) and vhosts
yum install -y mod_ssl
wget --no-cache -O /etc/httpd/conf.d/ssl.conf https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/ssl-l2.conf

# Enable gzip compression
cat << EOF >> /etc/httpd/conf/httpd.conf

AddOutputFilterByType DEFLATE text/plain
AddOutputFilterByType DEFLATE text/html
AddOutputFilterByType DEFLATE text/xml
AddOutputFilterByType DEFLATE text/css
AddOutputFilterByType DEFLATE application/xml
AddOutputFilterByType DEFLATE application/xhtml+xml
AddOutputFilterByType DEFLATE application/rss+xml
AddOutputFilterByType DEFLATE application/javascript
AddOutputFilterByType DEFLATE application/x-javascript
EOF

rm -rf /var/www/bak
mkdir /var/www/bak

echo "<?php phpinfo() ?>" > /var/www/html/info.php
echo "<html><head><title>Coming Soon</title></head><body><h2>Coming Soon</h2></body></html>" > /var/www/html/index.html
chown -R apache:apache /var/www/html

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
mv -f /var/www/intellipointsolutions.com /var/www/bak | true
mv -f intellipointsolutions.com /var/www
rm -rf intellipointsolutions.com

# Configure cache expiry for static content
cat << EOF > /var/www/intellipointsolutions.com/html/.htaccess

# BEGIN WordPress
# The directives (lines) between "BEGIN WordPress" and "END WordPress" are
# dynamically generated, and should only be modified via WordPress filters.
# Any changes to the directives between these markers will be overwritten.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>

# END WordPress
<IfModule mod_expires.c>
ExpiresActive On
# Images
ExpiresByType image/jpeg "access plus 1 year"
ExpiresByType image/gif "access plus 1 year"
ExpiresByType image/png "access plus 1 year"
ExpiresByType image/webp "access plus 1 year"
ExpiresByType image/svg+xml "access plus 1 year"
ExpiresByType image/x-icon "access plus 1 year"
ExpiresByType image/x-icon "access 1 year"
# Video
ExpiresByType video/mp4 "access plus 1 year"
ExpiresByType video/mpeg "access plus 1 year"
# CSS, JavaScript
ExpiresByType text/css "access plus 1 year"
ExpiresByType text/javascript "access plus 1 year"
ExpiresByType application/javascript "access plus 1 year"
# Others
ExpiresByType application/pdf "access plus 1 year"
ExpiresByType application/x-shockwave-flash "access plus 1 year"
</IfModule>
EOF

# Lock down .htaccess
chmod 644 /var/www/intellipointsolutions.com/html/.htaccess

# Set owner on web root folder and contents
chown -R apache:apache /var/www/intellipointsolutions.com

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
mv -f /var/www/joemcshea.intellipointsolutions.com /var/www/bak | true
mv -f joemcshea.intellipointsolutions.com /var/www
rm -rf joemcshea.intellipointsolutions.com

# Configure cache expiry for static content
cat << EOF > /var/www/joemcshea.intellipointsolutions.com/html/.htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
<IfModule mod_expires.c>
ExpiresActive On
# Images
ExpiresByType image/jpeg "access plus 1 year"
ExpiresByType image/gif "access plus 1 year"
ExpiresByType image/png "access plus 1 year"
ExpiresByType image/webp "access plus 1 year"
ExpiresByType image/svg+xml "access plus 1 year"
ExpiresByType image/x-icon "access plus 1 year"
ExpiresByType image/x-icon "access 1 year"
# Video
ExpiresByType video/mp4 "access plus 1 year"
ExpiresByType video/mpeg "access plus 1 year"
# CSS, JavaScript
ExpiresByType text/css "access plus 1 year"
ExpiresByType text/javascript "access plus 1 year"
ExpiresByType application/javascript "access plus 1 year"
# Others
ExpiresByType application/pdf "access plus 1 year"
ExpiresByType application/x-shockwave-flash "access plus 1 year"
</IfModule>
EOF

# Lock down .htaccess
chmod 644 /var/www/joemcshea.intellipointsolutions.com/html/.htaccess

# Set owner on web root folder and contents
chown -R apache:apache /var/www/joemcshea.intellipointsolutions.com

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

# Configure cache expiry for static content
cat << EOF > /var/www/speasyforms.intellipointsolutions.com/html/.htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
<IfModule mod_expires.c>
ExpiresActive On
# Images
ExpiresByType image/jpeg "access plus 1 year"
ExpiresByType image/gif "access plus 1 year"
ExpiresByType image/png "access plus 1 year"
ExpiresByType image/webp "access plus 1 year"
ExpiresByType image/svg+xml "access plus 1 year"
ExpiresByType image/x-icon "access plus 1 year"
ExpiresByType image/x-icon "access 1 year"
# Video
ExpiresByType video/mp4 "access plus 1 year"
ExpiresByType video/mpeg "access plus 1 year"
# CSS, JavaScript
ExpiresByType text/css "access plus 1 year"
ExpiresByType text/javascript "access plus 1 year"
ExpiresByType application/javascript "access plus 1 year"
# Others
ExpiresByType application/pdf "access plus 1 year"
ExpiresByType application/x-shockwave-flash "access plus 1 year"
</IfModule>
EOF

# Lock down .htaccess
chmod 660 /var/www/speasyforms.intellipointsolutions.com/html/.htaccess

# Set owner on web root folder and contents
chown -R apache:apache /var/www/speasyforms.intellipointsolutions.com

# Setup the backup script
wget --no-cache -O /etc/cron.d/aws-wordpress-backup.cron https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/aws-wordpress-backup.cron
chmod 600 /etc/cron.d/aws-wordpress-backup.cron
wget --no-cache -O /sbin/aws-wordpress-backup.sh https://raw.githubusercontent.com/mcsheaj/aws-playground/master/scripts/aws-wordpress-backup.sh
chmod 700 /sbin/aws-wordpress-backup.sh 
systemctl restart crond

# Disable php7.2 and enable php7.4 in amazon-linux-extras
amazon-linux-extras disable php7.2
amazon-linux-extras disable lamp-mariadb10.2-php7.2
amazon-linux-extras enable php7.4
yum clean metadata 

# Stop the php FastCGI Process Manager (created/started by the LAMP package for php7.2)
systemctl stop php-fpm

# Remove php7.2 and install php 7.4
yum remove php* -y
yum install php php-cli php-common php-fpm php-json php-mbstring php-mysqlnd php-pdo php-xml php-gd -y

# Copy up our php.ini
aws s3 cp s3://${AWS_BUCKET}/backup/php.ini /etc/php.ini

# Start the php FastCGI Process Manager (now php7.4)
systemctl start php-fpm

# Start the httpd service and configure it to start on boot
systemctl enable httpd
systemctl start httpd

################################################################################
# END WordPress Setup
################################################################################

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
/opt/aws/bin/cfn-signal -e $? --stack ${STACK_NAME} --resource WordPressGroup --region ${REGION} || true
