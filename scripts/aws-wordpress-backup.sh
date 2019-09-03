#/bin/bash -ex

SRC_DIR=
PREFIX=
INTERVAL=
RETAIN=4

# Print help
function usage()
{
   echo ""
   echo "$0 [options]"
   echo "   --src-dir    - the directory to be archived (required)"
   echo "   --prefix     - the prefix of the backup folder and file (required)"
   echo "   --interval   - the frequency of the backups, i.e. hour or daily, appended to "
   echo "                  the prefix of the backup folder (required)"
   echo "   --dst-bucket - the name of the bucket to which to copy the archive,"
   echo "                  will be copied to backup/${prefix}/{prefix}-{date}.tar.gz (optional, default is value of /root/.aws/bootstrap.properties DST_BUCKET)"
   echo "   --retain     - the number of archives to retains (default is 4)"
   echo ""
}

# Get options
while [ "$1" != "" ]
do
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
        --prefix)       shift
                        PREFIX=$1
                        ;;
        --interval)      shift
                        INTERVAL=$1
                        ;;
        --retain)       shift
                        RETAIN=$1
                        ;;
        *)              echo "Unknown parameter: $1"
                        usage
                        exit 1
                        ;;
    esac
    shift
done

# Exit with usage if required params are missing
if [[ -z $SRC_DIR || -z $PREFIX  || -z $INTERVAL ]]
then
    usage
    exit 1
fi

# If DST_BUCKET param wasn't passed, get it from bootstrap.properties
if [[ -z $DST_BUCKET ]]
then
    DST_BUCKET=$(awk -F "=" '/AWS_BUCKET/ {print $2}' /root/.aws/bootstrap.properties)
fi

# Init some variables from metadata
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
export AWS_DEFAULT_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)

# Calculate some variables
SUFFIX=$(date +"-%Y-%m-%d-%H-%M-%S-%Z")
DIR_NAME=$(dirname $SRC_DIR)
BASE_NAME=$(basename $SRC_DIR)

# Construct the folder and file names for the two backups
FOLDER="${PREFIX}-${INTERVAL}"
FILE_NAME="${PREFIX}-${INSTANCE_ID}${SUFFIX}.tar.gz"
DB_FOLDER="db-${PREFIX}-${INTERVAL}"
DB_FILE_NAME="db-${PREFIX}-${INSTANCE_ID}${SUFFIX}.sql.gz"

# Read the database connection params from bootstrap.properties
DB_HOST=$(awk -F "=" '/DB_SERVER/ {print $2}' /root/.aws/bootstrap.properties)
DB_USER=$(awk -F "=" '/DB_USER/ {print $2}' /root/.aws/bootstrap.properties)
DB_PASS=$(awk -F "=" '/DB_PASSWORD/ {print $2}' /root/.aws/bootstrap.properties)
DB=$(awk -F "=" '/DB_DATABASE/ {print $2}' /root/.aws/bootstrap.properties | sed "s/intellipoint_/${PREFIX}_/")

# The backup server is the first server to come back from describe-instance with filter Name=${NAME}
NAME=$(aws ec2 describe-tags --filters "Name=key,Values=Name" "Name=resource-id,Values=$INSTANCE_ID" --query "Tags[0].Value" --output text)
BACKUP_SERVER=$(aws ec2 describe-instances --query "Reservations" --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running" | jq .[0].Instances[0].InstanceId -r)

cd $DIR_NAME

# If I'm the backup server, do the backup
if [ $INSTANCE_ID = $BACKUP_SERVER ]
then
    # tar/gz the backup and copy to S3 bucket
    tar -czf /tmp/${FILE_NAME} ${BASE_NAME} | true
    aws s3 cp /tmp/${FILE_NAME} s3://${DST_BUCKET}/backup/${FOLDER}/${FILE_NAME}
    rm -rf /tmp/${FILE_NAME}

    # See how many backup files we have under prefix (i.e. folder)
    BACKUP_FILES=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${FOLDER}/${PREFIX} --query "Contents[?contains(Key, '.tar.gz')] | sort_by(@, &LastModified)")
    NUM_FILES=$(echo ${BACKUP_FILES} | jq length)

    # If more than ${RETAIN}, delete the excess
    if [ ${NUM_FILES} -gt ${RETAIN} ]
    then

        let "EXCESS_FILES=$NUM_FILES - ${RETAIN}"
        if [ ${EXCESS_FILES} -gt 0 ]
        then
            TODELETE=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${FOLDER}/${PREFIX} --query "Contents[?contains(Key, '.tar.gz')] | sort_by(@, &LastModified) | [0:${EXCESS_FILES}][].Key" --output text)

            for F  in $TODELETE
            do
                aws s3 rm s3://${DST_BUCKET}/${F}
            done
        fi  

    fi

    # Dump the mysql db, gz it, and upload to S3 bucket
    mysqldump --add-drop-table --host=$DB_HOST --user=$DB_USER --password=$DB_PASS $DB | gzip > /tmp/${DB_FILE_NAME}
    aws s3 cp /tmp/${DB_FILE_NAME} s3://${DST_BUCKET}/backup/${DB_FOLDER}/${DB_FILE_NAME}
    rm -rf /tmp/${DB_FILE_NAME}

    # See how many backup files we have under prefix (i.e. folder)
    BACKUP_FILES=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${DB_FOLDER}/db-${PREFIX} --query "Contents[?contains(Key, '.gz')] | sort_by(@, &LastModified)")
    NUM_FILES=$(echo ${BACKUP_FILES} | jq length)

    # If more than ${RETAIN}, delete the excess
    if [ ${NUM_FILES} -gt ${RETAIN} ]
    then

        let "EXCESS_FILES=$NUM_FILES - ${RETAIN}"
        if [ ${EXCESS_FILES} -gt 0 ]
        then
            TODELETE=$(aws s3api list-objects --bucket ${DST_BUCKET} --prefix backup/${DB_FOLDER}/db-${PREFIX} --query "Contents[?contains(Key, '.gz')] | sort_by(@, &LastModified) | [0:${EXCESS_FILES}][].Key" --output text)

            for F  in $TODELETE
            do
                aws s3 rm s3://${DST_BUCKET}/${F}
            done
        fi  

    fi

fi

