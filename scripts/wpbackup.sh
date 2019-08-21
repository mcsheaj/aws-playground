#!/bin/bash -e

SRC_DIR=
PREFIX=
RETAIN=4

# Print help
function usage()
{
   echo ""
   echo "$0 [options]"
   echo "   --src-dir    - the directory to be archived (required)"
   echo "   --dst-bucket - the name of the bucket to which to copy the archive,"
   echo "                  will be copied to backup/${prefix}/{prefix}-{date}.tar.gz (required)"
   echo "   --prefix     - the name of the backup folder and the prefix of the "
   echo "                  backup file (required)"
   echo "   --retain     - the number of archives to retains (default is 4)"
   echo "   --access-id  - the access key id of an IAM account you want to run under (optional)"
   echo "   --secret-key - the secret key of the IAM account (optional)"
   echo ""
}

# Get options
while [ "$1" != "" ]; do
    case $1 in
        --src-dir)      shift
                        SRC_DIR=$1
                        ;;
        --dst-bucket)   shift
                        DST_BUCKET=$1
                        ;;
        --prefix)       shift
                        PREFIX=$1
                        ;;
        --retain)       shift
                        RETAIN=$1
                        ;;
        --access-id)    shift
                        export AWS_ACCESS_KEY_ID=$1
                        ;;
        --secret-key)   shift
                        export AWS_SECRET_ACCESS_KEY=$1
                        ;;
        *)              echo "Unknown parameter: $1"
                        usage
                        exit 1
                        ;;
    esac
    shift
done

if [[ -z $SRC_DIR || -z $PREFIX ]]; then
    usage
    exit 1
fi

DIR_NAME=$(dirname $SRC_DIR)
BASE_NAME=$(basename $SRC_DIR)

export AWS_DEFAULT_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)

SUFFIX=$(date +"-%Y-%m-%d-%H-%M-%S-%Z")
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
NAME=$(aws ec2 describe-tags --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" --query "Tags[0].Value" --output text)
FILE_NAME="${PREFIX}${SUFFIX}.tar.gz"

DST_BUCKET=$(awk -F "=" '/AWS_BUCKET/ {print $2}' /root/.aws/bootstrap.properties)

# The backup server is the first server to come back from describe-instance with filter Name=$NAME
BACKUP_SERVER=$(aws ec2 describe-instances --query "Reservations" --filters "Name=tag:Name,Values=${NAME}" | jq .[0].Instances[0].InstanceId -r)

cd $DIR_NAME

if [ $INSTANCE_ID = $BACKUP_SERVER ]
then
    tar -czf /tmp/${FILE_NAME} ${BASE_NAME} | true
    aws s3 cp /tmp/${FILE_NAME} s3://${DST_BUCKET}/backup/${PREFIX}/${FILE_NAME}
    rm /tmp/${FILE_NAME}

    BACKUP_FILES=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${PREFIX}/${PREFIX} --query "Contents[?contains(Key, '.tar.gz')] | sort_by(@, &LastModified)")
    NUM_FILES=$(echo ${BACKUP_FILES} | jq length)

    if [ ${NUM_FILES} -gt ${RETAIN} ]
    then

        let "EXCESS_FILES=$NUM_FILES - ${RETAIN}"
        if [ ${EXCESS_FILES} -gt 0 ]
        then
            TODELETE=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${PREFIX}/${PREFIX} --query "Contents[?contains(Key, '.tar.gz')] | sort_by(@, &LastModified) | [0:${EXCESS_FILES}][].Key" --output text)

            for F  in $TODELETE
            do
                aws s3 rm s3://${DST_BUCKET}/${F}
            done
        fi
        
    fi
fi

