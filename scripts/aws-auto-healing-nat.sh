#!/bin/bash

# This script is to set a default route for route tables that need NAT in the same VPC.

MAC_ADDRESS=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/)
VPC_ID=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/vpc-id)
INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
TAG_KEY="Network"
TAG_VALUE="Private"

# Print help
function usage()
{
   echo ""
   echo "${0} [options]"
   echo "   --tag-key - route table tag key to indicate if it is a private subnet (default: ${TAG_KEY})"
   echo "   --tag-value - route table tag value to indicate if it is a private subnet (default: ${TAG_VALUE})"
   echo ""
}

# Get options
while [ "${1}" != "" ]; do
    case ${1} in
        --tag-key)      shift
                        ${TAG_KEY}=$1
                        ;;
        --tag-value)    shift
                        ${TAG_VALUE}=$1
                        ;;
        *)              usage
                        exit
                        ;;
    esac
    shift
done

# Determine route tables that need to use NAT for the same VPC
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" --region ${REGION} --output json | jq .RouteTables[].RouteTableId -r)

for ROUTE_TABLE  in ${ROUTE_TABLES}
do
   TARGET=$(aws ec2 describe-route-tables --filters "Name=route-table-id,Values=${ROUTE_TABLE}" --region ${REGION} --output json | jq '.RouteTables[].Routes[] | select(.DestinationCidrBlock == "0.0.0.0/0")' | jq .InstanceId -r)

   echo "Checking ${ROUTE_TABLE}"
   if [ "${TARGET}" = "" ]; then
      # Create default route 
      echo "No default route is detected. Creating default route for ${ROUTE_TABLE}"
      aws ec2 create-route --route-table-id ${ROUTE_TABLE} --destination-cidr-block 0.0.0.0/0 --instance-id ${INSTANCE_ID} --region ${REGION}
   elif [ "${TARGET}" != "${INSTANCE_ID}" ]; then
      # Replace default route
      echo "Default route is set to ${TARGET}. Replacing default route to ${INSTANCE_ID}"
      aws ec2 replace-route --route-table-id ${ROUTE_TABLE} --destination-cidr-block 0.0.0.0/0 --instance-id ${INSTANCE_ID} --region ${REGION}
   else
      echo "No change is required"
   fi

done

