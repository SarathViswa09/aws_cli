set -e

AWS_REGION="ap-southeast-1"
BUCKET_NAME="sarath-1-transfer-bucket"
TRANSFER_USERNAME="tf-user-sarath"
LAMBDA_FUNCTION_NAME="tf-file-automating"
ACCOUNT_ID="440883867769"
LAMBDA_ROLE_NAME="LambdaTransferTriggerRole"
TRANSFER_ROLE_IAM_NAME="TransferS3AccessRole"
TRANSFER_ROLE_ARN=arn:aws:iam::$ACCOUNT_ID:role/TransferS3AccessRole

# Creating S3
echo "Creating S3 bucket: $BUCKET_NAME"
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"

# Create IAM role for tf
echo "Creating IAM role for tf"
TRUST_POLICY='{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Service": "transfer.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
    }]
}'

#fetching arn
TRANSFER_ROLE_ARN=$(aws iam create-role --role-name "TransferS3AccessRole" --assume-role-policy-document "$TRUST_POLICY" --query 'Role.Arn' --output text)

# Create IAM policy for S3 access
echo "Creating S3 access policy"
S3_POLICY_DOCUMENT='{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::'"$BUCKET_NAME"'",
            "arn:aws:s3:::'"$BUCKET_NAME"'/*"
        ]
    }]
}'

aws iam put-role-policy \
    --role-name "TransferS3AccessRole" --policy-name $TRANSFER_ROLE_IAM_NAME \
    --policy-document "$S3_POLICY_DOCUMENT"

# Create IAM role for Lambda
echo "Creating Lambda role for execution"
LAMBDA_ROLE_ARN=$(aws iam create-role \
    --role-name "LambdaTransferTriggerRole" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }' --query 'Role.Arn' --output text)

#Lambda execution policy
aws iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

sleep 10
#Lambda function
echo "Creating Lambda function"
aws lambda create-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --runtime python3.9 \
  --role arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://test-tf.zip \
  --region "$AWS_REGION"



aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --action "lambda:InvokeFunction" \
    --principal "s3.amazonaws.com" \
    --source-arn "arn:aws:s3:::$BUCKET_NAME" \
    --statement-id "s3-trigger-1-$(date +%s)" \
    --region "$AWS_REGION"

# 2. Now apply the S3 bucket notification
aws s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "LambdaFunctionArn": "'"arn:aws:lambda:ap-southeast-1:440883867769:function:tf-file-automating"'",
            "Events": ["s3:ObjectCreated:*"]
        }]
    }'
##"LambdaFunctionArn": "'"arn:aws:lambda:ap-southeast-1:${ACCOUNT_ID}:function:${LAMBDA_ROLE_ARN}"'",

# Create Transfer Family server
echo "Creating Transfer Family server"
SERVER_ID=$(aws transfer create-server \
    --protocols SFTP \
    --region "$AWS_REGION" \
    --query 'ServerId' \
    --output text)


# Create Transfer Family user

echo "Creating Transfer user $TRANSFER_USERNAME"

USER_PASSWORD="server123#"

aws transfer create-user \
    --server-id "$SERVER_ID" \
    --user-name "$TRANSFER_USERNAME" \
    --role "$TRANSFER_ROLE_ARN" \
    --home-directory "/$BUCKET_NAME" \
    --region "$AWS_REGION"

aws transfer import-ssh-public-key \
  --server-id   "$SERVER_ID" \
  --user-name   "$TRANSFER_USERNAME" \
  --ssh-public-key-body file://~/.ssh/transfer_family_key.pub

aws transfer describe-server \
  --server-id "${SERVER_ID}" \
  --region "${AWS_REGION}" \
  --query 'Server.EndpointType' \
  --output text

ENDPOINT="${SERVER_ID}.server.transfer.${AWS_REGION}.amazonaws.com"
echo "End Point = sftp -i ~/.ssh/transfer_family_key -P 22 $TRANSFER_USERNAME@$ENDPOINT"
#connect with the above endpoint

# Output the connection details
echo "!!!!!Setup complete!"

echo "S3 Bucket: $BUCKET_NAME"
echo "Transfer Server ID: $SERVER_ID"
echo "SFTP Username: $TRANSFER_USERNAME"
echo "SFTP Password: $USER_PASSWORD"
echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "connect to endpoint---"
