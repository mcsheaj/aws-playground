#!/bin/bash -xe

#
# Get the account id from identity credentials
#
export ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info/ | jq .AccountId -r)

#
# Get the instance profile ARN
#
export INSTANCE_PROFILE_ARN=$(curl -s http://169.254.169.254/latest/meta-data/iam/info | jq .InstanceProfileArn -r)

#
# Get the instance role name and construct the ARN
#
export INSTANCE_ROLE_NAME=$(curl http://169.254.169.254/latest/meta-data/iam/security-credentials/)
export INSTANCE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE}"

#
# Get the IAM security credentials for assuming the instance role
#
export TMP_CREDENTIALS=$(curl http://169.254.169.254/latest/meta-data/iam/security-credentials/${ROLE})

#
# Parse the AWS CLI environment variables from the IAM security credentials
#
export ACCESS_KEY_ID=$(echo $TMP_CREDENTIALS | jq .AccessKeyId -r)
export SECRET_ACCESS_KEY=$(echo $TMP_CREDENTIALS | jq .SecretAccessKey -r)
export AWS_SESSION_TOKEN=$(echo $TMP_CREDENTIALS | jq .Token -r)


aws sts assume-role --role-arn ${INSTANCE_ROLE_ARN} --role-session-name "BastionSession" --profile ${INSTANCE_PROFILE_ARN}
